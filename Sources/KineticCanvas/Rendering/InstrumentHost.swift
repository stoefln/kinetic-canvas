import AppKit
import AVFoundation
import CoreAudioKit
import Foundation

/// Vital-only AU instrument host.
///
/// Discovers the registered Vital music-device component, hosts a small pool of
/// instances inside the shared `ClipAudioEngine` graph, routes line MIDI to them,
/// and captures/restores `fullState` through property-list sidecars. It is not a
/// general plugin browser or effect rack.
///
/// On Apple Silicon Vital's bundle is x86_64-only, so instances are requested
/// out-of-process; the AU runs in the system's audio component service and the
/// engine sees it as a normal node.
final class InstrumentHost: @unchecked Sendable {
    /// Simultaneously hosted Vital instances. The target is ~3.
    static let slotCapacity = 3

    private final class Slot {
        let id = UUID()
        var lineID: UUID?
        var unit: AVAudioUnitMIDIInstrument?
        var mixer: AVAudioMixerNode?
        var reference: AUStateReference?
        var heldNotes: [UInt8] = []
        var message: String?
        var loading = false
    }

    private let queue = DispatchQueue(label: "kineticcanvas.instrument-host", qos: .userInitiated)
    /// Runs a graph edit on the audio engine's control queue.
    private let performGraphEdit: (@escaping @Sendable (AVAudioEngine, AVAudioMixerNode) -> Void) -> Void

    private let componentDescription: AudioComponentDescription?
    private let componentName: String
    private let componentManufacturer: String
    private var slots: [Slot] = []
    private var lineToSlot: [UUID: UUID] = [:]
    private var vitalLines: [SampleLine] = []

    private(set) var availability: InstrumentAvailability
    /// Called on the host queue when availability is first resolved.
    var onAvailabilityChange: (@Sendable (InstrumentAvailability) -> Void)?
    /// Called on the host queue when any line's slot status changes.
    var onStatusChange: (@Sendable ([UUID: InstrumentLineStatus]) -> Void)?

    init(performGraphEdit: @escaping (@escaping @Sendable (AVAudioEngine, AVAudioMixerNode) -> Void) -> Void) {
        self.performGraphEdit = performGraphEdit
        let found = Self.findVital()
        if let found {
            componentDescription = found.audioComponentDescription
            componentName = found.name
            componentManufacturer = found.manufacturerName
            availability = .available(name: found.name)
        } else {
            componentDescription = nil
            componentName = "Vital"
            componentManufacturer = ""
            availability = .unavailable(message: "Vital AU unavailable")
        }
    }

    /// Finds the registered Vital music device without hard-coding file paths or
    /// component IDs.
    private static func findVital() -> AVAudioUnitComponent? {
        var description = AudioComponentDescription()
        description.componentType = kAudioUnitType_MusicDevice
        description.componentSubType = 0
        description.componentManufacturer = 0
        description.componentFlags = 0
        description.componentFlagsMask = 0
        let components = AVAudioUnitComponentManager.shared().components(matching: description)
        return components.first { $0.name.localizedCaseInsensitiveContains("vital") }
            ?? components.first { $0.manufacturerName.localizedCaseInsensitiveContains("vital") }
    }

    // MARK: - Configuration

    /// Reconciles the hosted slots with the lines that ask for a Vital
    /// destination. Up to `slotCapacity` lines get a slot; extras report a
    /// capacity error and stay silent. Instances are reused, never recreated for
    /// a sound change.
    func configure(lines: [SampleLine], enabled: Bool) {
        let requested = enabled ? lines.filter { $0.destination == .vital && $0.isEnabled } : []
        queue.async { [self] in
            while slots.count < Self.slotCapacity { slots.append(Slot()) }
            vitalLines = requested
            let requestedIDs = Set(requested.map(\.id))
            lineToSlot = lineToSlot.filter { requestedIDs.contains($0.key) }

            // Release slots whose line went away; the instance stays attached.
            for slot in slots where slot.lineID != nil && !requestedIDs.contains(slot.lineID!) {
                releaseNotes(slot)
                ramp(slot, to: 0)
                slot.lineID = nil
                slot.reference = nil
                slot.message = nil
            }

            // Assign new lines to free slots in list order.
            for line in requested where lineToSlot[line.id] == nil {
                guard let free = slots.first(where: { $0.lineID == nil }) else { continue }
                free.lineID = line.id
                lineToSlot[line.id] = free.id
            }

            for slot in slots {
                guard let lineID = slot.lineID,
                      let line = requested.first(where: { $0.id == lineID }) else { continue }
                if slot.reference != line.instrument {
                    slot.reference = line.instrument
                    if slot.unit != nil { restore(slot) }
                }
                ensureLoaded(slot)
            }
            publish()
        }
    }

    func stop() {
        queue.async { [self] in
            for slot in slots {
                releaseNotes(slot)
                ramp(slot, to: 0)
                slot.lineID = nil
                slot.reference = nil
            }
            lineToSlot.removeAll()
            vitalLines.removeAll()
            publish()
        }
    }

    // MARK: - MIDI routing

    /// Delivers one line's MIDI event to its hosted instrument.
    func handle(_ event: LineInstrumentEvent) {
        queue.async { [self] in
            guard let slotID = lineToSlot[event.lineID],
                  let slot = slots.first(where: { $0.id == slotID }),
                  let unit = slot.unit else { return }
            unit.sendMIDIEvent(event.status, data1: event.data1, data2: event.data2)
            switch event.status & 0xF0 {
            case 0x90 where event.data2 > 0:
                if !slot.heldNotes.contains(event.data1) { slot.heldNotes.append(event.data1) }
            case 0x80, 0x90:
                slot.heldNotes.removeAll { $0 == event.data1 }
            default:
                break
            }
        }
    }

    // MARK: - Slots

    private func ensureLoaded(_ slot: Slot) {
        guard slot.unit == nil, !slot.loading, let description = componentDescription else { return }
        slot.loading = true
        AVAudioUnit.instantiate(with: description, options: [.loadOutOfProcess]) { [weak self] unit, error in
            guard let self else { return }
            self.queue.async {
                slot.loading = false
                guard error == nil, let unit = unit as? AVAudioUnitMIDIInstrument else {
                    slot.message = "Vital failed to load"
                    self.publish()
                    return
                }
                let mixer = AVAudioMixerNode()
                mixer.outputVolume = 0
                self.performGraphEdit { engine, output in
                    engine.attach(mixer)
                    engine.attach(unit)
                    engine.connect(unit, to: mixer, format: nil)
                    engine.connect(mixer, to: output, format: nil)
                }
                slot.unit = unit
                slot.mixer = mixer
                slot.message = nil
                self.restore(slot)
                self.publish()
            }
        }
    }

    /// Restores a captured sound into a slot. The gain ramps down, the state is
    /// applied on this serialized queue, then the gain ramps back up so a sound
    /// swap never clicks or strands a voice.
    private func restore(_ slot: Slot) {
        guard let unit = slot.unit else { return }
        guard let reference = slot.reference else {
            slot.message = nil
            ramp(slot, to: 1)
            return
        }
        guard let state = AUStateStore.load(id: reference.id) else {
            // Keep the slot audible so Vital's own editor still works; the line
            // just restores to whatever the instance currently holds.
            slot.message = "Sound missing"
            ramp(slot, to: 1)
            return
        }
        releaseNotes(slot)
        ramp(slot, to: 0) { [weak self] in
            unit.auAudioUnit.fullState = state
            slot.message = nil
            self?.ramp(slot, to: 1)
        }
    }

    private func releaseNotes(_ slot: Slot) {
        guard let unit = slot.unit else { return }
        for pitch in slot.heldNotes { unit.sendMIDIEvent(0x80, data1: pitch, data2: 0) }
        slot.heldNotes.removeAll()
        unit.sendMIDIEvent(0xB0, data1: 123, data2: 0)  // All Notes Off
        unit.sendMIDIEvent(0xB0, data1: 120, data2: 0)  // All Sound Off
    }

    private func ramp(_ slot: Slot, to target: Float, completion: (() -> Void)? = nil) {
        guard let mixer = slot.mixer else {
            completion?()
            return
        }
        let steps = 6
        let duration = 0.03
        let interval = duration / Double(steps)
        let start = mixer.outputVolume
        for step in 1...steps {
            let value = start + (target - start) * Float(step) / Float(steps)
            queue.asyncAfter(deadline: .now() + interval * Double(step)) { mixer.outputVolume = value }
        }
        if let completion {
            queue.asyncAfter(deadline: .now() + duration + 0.005, execute: completion)
        }
    }

    // MARK: - Capture and editor

    /// Reads the live sound from a line's slot, writes it to a sidecar, and
    /// returns the lightweight reference a preset stores. When `existing` is
    /// given the same sidecar/catalog entry is overwritten, so an automatic
    /// recapture on preset save does not grow the library.
    func captureState(forLine lineID: UUID, name: String,
                      replacing existing: AUStateReference? = nil) async -> AUStateReference? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let slotID = lineToSlot[lineID],
                      let slot = slots.first(where: { $0.id == slotID }),
                      let unit = slot.unit,
                      let state = unit.auAudioUnit.fullState else {
                    continuation.resume(returning: nil)
                    return
                }
                let reference = AUStateReference(
                    id: existing?.id ?? UUID(),
                    name: name,
                    componentName: componentName,
                    componentManufacturer: componentManufacturer,
                    componentType: componentDescription?.componentType ?? 0,
                    componentSubType: componentDescription?.componentSubType ?? 0,
                    componentManufacturerCode: componentDescription?.componentManufacturer ?? 0
                )
                guard AUStateStore.save(state, id: reference.id) else {
                    continuation.resume(returning: nil)
                    return
                }
                AUStateStore.addToCatalog(reference)
                slot.reference = reference
                publish()
                continuation.resume(returning: reference)
            }
        }
    }

    /// Requests the AU's editor view controller. Must run on the main thread, as
    /// AppKit builds the view there.
    func requestEditor(forLine lineID: UUID) async -> NSViewController? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let slotID = lineToSlot[lineID],
                      let slot = slots.first(where: { $0.id == slotID }),
                      let unit = slot.unit else {
                    continuation.resume(returning: nil)
                    return
                }
                DispatchQueue.main.async {
                    unit.auAudioUnit.requestViewController { viewController in
                        continuation.resume(returning: viewController)
                    }
                }
            }
        }
    }

    // MARK: - Status

    private func publish() {
        var statuses: [UUID: InstrumentLineStatus] = [:]
        for line in vitalLines {
            if let slot = slots.first(where: { $0.lineID == line.id }) {
                statuses[line.id] = InstrumentLineStatus(soundName: slot.reference?.name,
                                                         loaded: slot.unit != nil,
                                                         message: slot.message)
            } else {
                statuses[line.id] = InstrumentLineStatus(
                    soundName: line.instrument?.name,
                    loaded: false,
                    message: availability.isAvailable
                        ? "Capacity reached (max \(Self.slotCapacity))"
                        : availability.label)
            }
        }
        onStatusChange?(statuses)
    }
}

/// Versioned property-list sidecars for captured Vital `fullState` dictionaries.
/// Presets store only a reference, so a large state blob never bloats preset JSON.
enum AUStateStore {
    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kinetic Canvas/AU States", isDirectory: true)
    }

    static func save(_ state: [String: Any], id: UUID) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0)
            try data.write(to: fileURL(id), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func load(id: UUID) -> [String: Any]? {
        guard let data = try? Data(contentsOf: fileURL(id)) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
    }

    /// Removes a sidecar and its catalog entry. Not called by the app, which
    /// keeps captured states so a preset referencing them still restores; used
    /// for cleanup in tests.
    static func delete(id: UUID) {
        try? FileManager.default.removeItem(at: fileURL(id))
        var sounds = catalog()
        sounds.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(sounds) {
            try? data.write(to: catalogURL, options: .atomic)
        }
    }

    /// Every saved sound, name-sorted. The app writes this index on capture, so a
    /// line's picker can list sounds captured from any preset.
    static func catalog() -> [AUStateReference] {
        guard let data = try? Data(contentsOf: catalogURL),
              let sounds = try? JSONDecoder().decode([AUStateReference].self, from: data) else {
            return []
        }
        return sounds.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Adds or replaces a sound in the on-disk index.
    static func addToCatalog(_ reference: AUStateReference) {
        var sounds = (try? Data(contentsOf: catalogURL))
            .flatMap { try? JSONDecoder().decode([AUStateReference].self, from: $0) } ?? []
        sounds.removeAll { $0.id == reference.id }
        sounds.append(reference)
        guard let data = try? JSONEncoder().encode(sounds) else { return }
        try? data.write(to: catalogURL, options: .atomic)
    }

    private static var catalogURL: URL {
        directory.appendingPathComponent("index.json")
    }

    private static func fileURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).plist")
    }
}
