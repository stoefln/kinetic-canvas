import CoreMIDI
import Foundation

/// A single sixteenth-note clock. All mutable state lives on `queue`.
final class LineSamplerMIDI: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dancefx.line-sampler-midi", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var client = MIDIClientRef()
    /// Shared port used in `.single` mode.
    private var source = MIDIEndpointRef()
    /// One virtual source per MIDI channel, created lazily in `.perLine` mode.
    private var channelSources: [UInt8: MIDIEndpointRef] = [:]
    private var portMode: SampleMIDIPortMode = .perLine
    /// Last requested CC7 value, re-applied to ports created later.
    private var masterVolume = 0.8
    private var lines: [SampleLine] = []
    private var harmony = SampleHarmony()
    private var enabled = false
    private var bpm = 120.0
    /// Called on `queue` whenever the sounding/blocked segment picture changes.
    var onStateChange: (@Sendable (SamplerVisualState) -> Void)?
    private var lastVisualState = SamplerVisualState()
    /// One bit per key; a multi-octave line can exceed 16 keys, so 64 bits.
    private var bitsets: [UUID: UInt64] = [:]
    /// Per-segment brightness (0...255) from the latest occupancy pass; drives
    /// Note On velocity.
    private var levels: [UUID: [UInt8]] = [:]
    /// Global minimum average brightness (0...1) for a segment to trigger.
    private var triggerThreshold = 0.2
    /// When on, note onsets wait for the next 16th-note grid line.
    private var quantize = true
    private var transposeMode: SampleTransposeMode = .diatonic
    /// Last CC value sent per modulation line; a missing entry forces a resend.
    private var modulationValues: [UUID: UInt8] = [:]
    private var emptyFrames: [UUID: [Int: Int]] = [:]
    private var lastFrame: Double = 0
    private var nextStep: Double = 0
    private var stepIndex: Int64 = 0
    private var active: [UUID: [Int: Voice]] = [:]
    /// Note On/Off triples collected during one callback, grouped by destination
    /// port so each is sent in a single `MIDIReceived` call.
    private var pendingByPort: [MIDIEndpointRef: [UInt8]] = [:]
    private static let maxPacketBytes = 256
    /// Stride of the per-line occupancy buffer; 4 chromatic octaves is 48 keys.
    static let maxSections = 64
    private struct Voice { let pitch: Int; let channel: UInt8; let offAt: Double }

    init() {
        MIDIClientCreate("DanceFX" as CFString, nil, nil, &client)
        if client != 0 { MIDISourceCreate(client, "DanceFX Line Sampler" as CFString, &source) }
    }

    deinit {
        timer?.cancel()
        // `deinit` cannot safely drain an in-flight queue; the app calls stop on shutdown.
        for (_, endpoint) in channelSources { MIDIEndpointDispose(endpoint) }
        if source != 0 { MIDIEndpointDispose(source) }
        if client != 0 { MIDIClientDispose(client) }
    }

    func configure(lines newLines: [SampleLine], harmony newHarmony: SampleHarmony,
                   bpm newBPM: Double, threshold newThreshold: Double,
                   quantize newQuantize: Bool, transposeMode newTransposeMode: SampleTransposeMode,
                   portMode newPortMode: SampleMIDIPortMode, enabled newEnabled: Bool) {
        queue.async { [self] in
            triggerThreshold = min(1, max(0.01, newThreshold))
            quantize = newQuantize
            transposeMode = newTransposeMode
            if newPortMode != portMode {
                // Release notes on the ports they were played on before switching,
                // otherwise a mode change would strand them on the old port.
                stopAll()
                flushMessages()
                portMode = newPortMode
            }
            let old = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0) })
            let now = ProcessInfo.processInfo.systemUptime
            let oldDuration = 15 / bpm
            let clampedBPM = min(240, max(30, newBPM))
            if clampedBPM != bpm && nextStep > 0 {
                nextStep = now + (nextStep - now) * (15 / clampedBPM) / oldDuration
            }
            bpm = clampedBPM
            // Root and scale are global, so changing either changes every line's
            // pitches. Release existing voices instead of letting stale pitches ring.
            if newHarmony.root != harmony.root || newHarmony.scale != harmony.scale {
                stopAll()
            }
            harmony = newHarmony
            for (id, voices) in active {
                guard let prior = old[id], let next = newLines.first(where: { $0.id == id }),
                      newEnabled, next.midiEnabled, !next.isModulationSource,
                      prior.octave == next.octave,
                      prior.keyCount == next.keyCount,
                      prior.isMonophonic == next.isMonophonic,
                      prior.rhythm == next.rhythm, prior.triggerMode == next.triggerMode,
                      prior.midiChannel == next.midiChannel
                else { voices.keys.forEach { stop(id: id, segment: $0) }; continue }
            }
            lines = Array(newLines.prefix(16))
            enabled = newEnabled
            if !enabled || !lines.contains(where: \.midiEnabled) {
                stopAll()
                nextStep = 0
                stepIndex = 0
                timer?.cancel()
                timer = nil
            } else if nextStep == 0 {
                nextStep = now
                stepIndex = 0
                if timer == nil {
                    let source = DispatchSource.makeTimerSource(queue: queue)
                    source.schedule(deadline: .now(), repeating: .milliseconds(5), leeway: .milliseconds(2))
                    source.setEventHandler { [weak self] in self?.tick() }
                    timer = source
                    source.resume()
                }
            }
            // Flush any Note Offs before ports are torn down, then send the
            // current volume to ports that were just created.
            flushMessages()
            reconcileChannelSources(for: lines)
            flushMessages()
            emitVisualState()
        }
    }

    func updateOccupancy(_ states: [UUID: [UInt8]]) {
        queue.async { [self] in
            var stabilized: [UUID: UInt64] = [:]
            var normalized: [UUID: [UInt8]] = [:]
            for (id, observed) in states {
                var value: UInt64 = 0
                for segment in 0..<Self.maxSections {
                    let level = segment < observed.count ? observed[segment] : 0
                    let bit = UInt64(1) << UInt64(segment)
                    if Self.isOccupied(level: level, threshold: triggerThreshold) {
                        emptyFrames[id, default: [:]][segment] = 0
                        value |= bit
                    } else if (bitsets[id] ?? 0) & bit != 0 {
                        // One stale frame keeps a just-lost segment alive, which
                        // suppresses edge flicker without visibly holding notes.
                        let count = (emptyFrames[id]?[segment] ?? 0) + 1
                        emptyFrames[id, default: [:]][segment] = count
                        if count < 2 { value |= bit }
                    }
                }
                stabilized[id] = value
                normalized[id] = observed.count >= Self.maxSections
                    ? Array(observed[0..<Self.maxSections])
                    : observed + Array(repeating: 0, count: Self.maxSections - observed.count)
            }
            bitsets = stabilized
            levels = normalized
            lastFrame = ProcessInfo.processInfo.systemUptime
            emitModulation()
        }
    }

    static func isOccupied(level: UInt8, threshold: Double) -> Bool {
        Double(level) / 255.0 >= threshold
    }

    /// Maps segment brightness to velocity across a wide range (16...127) so a
    /// dim region and a bright one are clearly distinguishable in the host.
    static func velocity(forLevel level: UInt8) -> UInt8 {
        let scaled = 16 + Int((Double(level) / 255.0) * 111.0)
        return UInt8(min(127, max(1, scaled)))
    }

    /// Turns each modulation line's brightness-weighted position along A→B into
    /// its own MIDI CC. A line is sampled with `maxSections` buckets, so the
    /// value has up to 64 positions of resolution. A dark line holds its last
    /// value rather than snapping the parameter down, and an unchanged value is
    /// not resent, so this stays a few bytes per camera frame.
    private func emitModulation() {
        guard enabled else { return }
        var changed = false
        for line in lines where line.isModulationSource {
            guard (0..<16).contains(line.midiChannel),
                  let lineLevels = levels[line.id],
                  let value = Self.modulationValue(levels: lineLevels, threshold: triggerThreshold)
            else { continue }
            guard value != modulationValues[line.id] else { continue }
            modulationValues[line.id] = value
            enqueueCC(channel: UInt8(line.midiChannel),
                      controller: UInt8(min(127, max(0, line.modulationCC))), value: value)
            changed = true
        }
        if changed { flushMessages() }
    }

    /// Brightness-weighted position of the lit region along a modulation line,
    /// mapped to a 0...127 CC value. Weights below the trigger threshold are
    /// ignored so a dim uniform background holds the parameter steady. Returns
    /// nil when nothing is lit.
    static func modulationValue(levels: [UInt8], threshold: Double) -> UInt8? {
        guard levels.count > 1 else { return nil }
        let floor = threshold * 255.0
        var weighted = 0.0
        var total = 0.0
        for index in levels.indices {
            let level = Double(levels[index])
            guard level > floor else { continue }
            let weight = level - floor
            weighted += weight * Double(index)
            total += weight
        }
        guard total > 0 else { return nil }
        let position = weighted / total / Double(levels.count - 1)
        return UInt8(min(127, max(0, Int((position * 127).rounded()))))
    }

    /// Picks the one segment a monophonic line should sound: the segment it
    /// already holds if that segment is still lit, otherwise the brightest lit
    /// segment (lowest index breaks ties). Returns nil when nothing is lit.
    static func monophonicSegment(mask: UInt64, levels: [UInt8]?, held: Int?) -> Int? {
        guard mask != 0 else { return nil }
        if let held, mask & (UInt64(1) << UInt64(held)) != 0 { return held }
        var best: Int?
        var bestLevel: UInt8 = 0
        for segment in 0..<maxSections where mask & (UInt64(1) << UInt64(segment)) != 0 {
            let level: UInt8 = {
                guard let levels, segment < levels.count else { return 0 }
                return levels[segment]
            }()
            if best == nil || level > bestLevel {
                best = segment
                bestLevel = level
            }
        }
        return best
    }

    private func monophonicSegment(for line: SampleLine, mask: UInt64) -> Int? {
        Self.monophonicSegment(mask: mask, levels: levels[line.id], held: active[line.id]?.keys.min())
    }

    func stop() {
        // `sync` bounds the wait to one cheap tick (≤5 ms) and guarantees the
        // final Note Offs are committed before the app exits, avoiding stuck notes.
        queue.sync {
            enabled = false
            stopAll()
            // Tracking can miss a voice (for example a host that dropped an
            // earlier Note Off). Sweep every pitch on every channel so quitting
            // never leaves a note ringing.
            sendAllNotesOff()
            nextStep = 0
            stepIndex = 0
            timer?.cancel()
            timer = nil
            flushMessages()
            emitVisualState()
        }
    }

    /// Queues Note Off for every pitch on the given channel, plus the standard
    /// All Notes Off (CC123) and All Sound Off (CC120) controllers. Some hosts
    /// ignore the controllers, and some ignore note-offs for a pitch they never
    /// saw start, so sending all three is the reliable way to clear a stuck note.
    private func queueAllNotesOff(channel: UInt8, to port: MIDIEndpointRef) {
        var bytes: [UInt8] = [
            0xB0 | channel, 123, 0,   // All Notes Off
            0xB0 | channel, 120, 0,   // All Sound Off
        ]
        bytes.reserveCapacity(6 + 128 * 3)
        for pitch in 0..<128 {
            bytes.append(contentsOf: [0x80 | channel, UInt8(pitch), 0])
        }
        pendingByPort[port, default: []].append(contentsOf: bytes)
    }

    /// Sends the panic sweep to every port this instance already published.
    /// Only existing ports are touched, so a stop never creates new devices.
    private func sendAllNotesOff() {
        switch portMode {
        case .single:
            guard source != 0 else { return }
            for channel in UInt8(0)..<16 { queueAllNotesOff(channel: channel, to: source) }
        case .perLine:
            for (channel, port) in channelSources { queueAllNotesOff(channel: channel, to: port) }
        }
    }

    /// Diagnostic: sounds one note at a fixed velocity on channel 1 so a host's
    /// velocity response can be checked without relying on pixel detection.
    func sendTestNote(pitch: Int, velocity: UInt8) {
        queue.async { [self] in
            enqueue(status: 0x90, pitch: pitch, velocity: min(127, max(1, velocity)))
            flushMessages()
            queue.asyncAfter(deadline: .now() + 0.45) { [self] in
                enqueue(status: 0x80, pitch: pitch, velocity: 0)
                flushMessages()
            }
        }
    }

    /// Diagnostic: sends one modulation CC at mid value so a synth's MIDI-learn
    /// can bind it without waiting for a lit line.
    func sendTestModulation(channel: Int, controller: Int) {
        guard (0..<16).contains(channel) else { return }
        let cc = UInt8(min(127, max(0, controller)))
        queue.async { [self] in
            enqueueCC(channel: UInt8(channel), controller: cc, value: 64)
            flushMessages()
        }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        for (id, voices) in active {
            for (segment, voice) in voices where voice.offAt <= now { stop(id: id, segment: segment) }
        }
        if enabled, nextStep > 0 {
            let fresh = lastFrame > 0 && now - lastFrame < 0.3
            if lastFrame > 0 && !fresh { stopAll() }
            let duration = 15 / bpm
            if now - nextStep > duration * 2 {
                let skipped = Int64((now - nextStep) / duration)
                stepIndex += skipped
                nextStep += Double(skipped) * duration
            }
            let onGrid = now >= nextStep
            let lead = leadDegree
            // Single-shot lines follow pixel presence continuously; with
            // quantization on they wait for the next 16th-note grid line.
            reconcileSingleShots(fresh: fresh, allowOnsets: !quantize || onGrid, leadDegree: lead)
            if onGrid {
                for line in lines where line.midiEnabled && !line.isModulationSource && line.triggerMode == .rhythm {
                    guard stepIndex % Int64(max(1, line.rhythm)) == 0 else { continue }
                    guard (0..<16).contains(line.midiChannel) else { continue }
                    let channel = UInt8(line.midiChannel)
                    let mask = fresh ? (bitsets[line.id] ?? 0) : 0
                    let gate = duration * Double(max(1, line.rhythm)) * 0.5
                    let pitches = effectivePitches(for: line, leadDegree: lead)
                    let segments: [Int]
                    if line.isMonophonic {
                        // Release anything this line is not about to retrigger so
                        // it never holds two notes. A lit-but-held segment wins
                        // over a brighter newcomer, which keeps a mono note from
                        // flickering between adjacent lit segments.
                        let chosen = monophonicSegment(for: line, mask: mask)
                        active[line.id]?.keys.filter { $0 != chosen }.forEach { stop(id: line.id, segment: $0) }
                        segments = chosen.map { [$0] } ?? []
                    } else {
                        segments = pitches.indices.filter {
                            mask & (UInt64(1) << UInt64($0)) != 0
                        }
                    }
                    for segment in segments {
                        guard segment < pitches.count else { continue }
                        // Release this segment first so its own previous note does
                        // not count as a clash when deciding whether to retrigger.
                        stop(id: line.id, segment: segment)
                        guard harmony.allows(pitches[segment], against: soundingPitches) else { continue }
                        let velocity = Self.velocity(forLevel: levels[line.id]?[segment] ?? 255)
                        enqueue(status: 0x90 | channel, pitch: pitches[segment], velocity: velocity)
                        active[line.id, default: [:]][segment] = Voice(pitch: pitches[segment], channel: channel, offAt: now + gate)
                    }
                }
                stepIndex += 1
                nextStep += duration
            }
        }
        flushMessages()
        emitVisualState()
    }

    /// Holds a note on for every single-shot segment that currently has pixels
    /// and releases it as soon as the segment empties (or the feed goes stale).
    /// Releases always happen now; `allowOnsets` is false between grid lines
    /// when quantization is on.
    private func reconcileSingleShots(fresh: Bool, allowOnsets: Bool, leadDegree: Int) {
        for line in lines where line.midiEnabled && !line.isModulationSource && line.triggerMode == .singleShot {
            guard (0..<16).contains(line.midiChannel) else {
                active[line.id]?.keys.forEach { stop(id: line.id, segment: $0) }
                continue
            }
            let channel = UInt8(line.midiChannel)
            let mask = fresh ? (bitsets[line.id] ?? 0) : 0
            if let voices = active[line.id] {
                for segment in voices.keys where mask & (UInt64(1) << UInt64(segment)) == 0 {
                    stop(id: line.id, segment: segment)
                }
            }
            let pitches = effectivePitches(for: line, leadDegree: leadDegree)
            let candidates: [Int]
            if line.isMonophonic {
                // A single held segment wins while it stays lit; release any other
                // sounding voice so the line never holds a chord.
                let chosen = monophonicSegment(for: line, mask: mask)
                active[line.id]?.keys.filter { $0 != chosen }.forEach { stop(id: line.id, segment: $0) }
                candidates = chosen.map { [$0] } ?? []
            } else {
                candidates = pitches.indices.filter {
                    mask & (UInt64(1) << UInt64($0)) != 0
                }
            }
            guard allowOnsets else { continue }
            for segment in candidates {
                guard segment < pitches.count else { continue }
                guard active[line.id]?[segment] == nil else { continue }
                guard harmony.allows(pitches[segment], against: soundingPitches) else { continue }
                let velocity = Self.velocity(forLevel: levels[line.id]?[segment] ?? 255)
                enqueue(status: 0x90 | channel, pitch: pitches[segment], velocity: velocity)
                // `.infinity` keeps the voice out of the timed gate release.
                active[line.id, default: [:]][segment] = Voice(pitch: pitches[segment], channel: channel, offAt: .infinity)
            }
        }
    }

    /// Every pitch currently held across all lines, used to gate new candidates.
    private var soundingPitches: [Int] {
        active.values.flatMap { $0.values.map(\.pitch) }
    }

    /// The lead line's active scale degree, or 0 when there is no lead or it is
    /// silent. The lowest occupied segment wins if several are lit.
    private var leadDegree: Int {
        guard let lead = lines.first(where: { $0.isLead && $0.midiEnabled && !$0.isModulationSource }),
              let mask = bitsets[lead.id], mask != 0 else { return 0 }
        let count = max(1, harmony.scale.offsets.count)
        // A multi-octave lead may be lit above the first octave; fold the key
        // index back to a scale degree so transposition stays in 0..<count.
        return Int(mask.trailingZeroBitCount) % count
    }

    private func effectivePitches(for line: SampleLine, leadDegree: Int) -> [Int] {
        harmony.effectivePitches(octave: line.octave, keyCount: line.keyCount,
                                 leadDegree: leadDegree, mode: transposeMode, isLead: line.isLead)
    }

    private func currentVisualState() -> SamplerVisualState {
        guard enabled else { return SamplerVisualState() }
        var masks: [UUID: UInt64] = [:]
        for (id, voices) in active where !voices.isEmpty {
            var mask: UInt64 = 0
            for segment in voices.keys { mask |= UInt64(1) << UInt64(segment) }
            masks[id] = mask
        }
        // Transposition shifts non-lead lines, so blocked degrees differ per
        // line. The fourth/fifth distinction is measured from the lower note,
        // so blocked status depends on absolute octaves and cannot be reduced
        // to pitch classes.
        let lead = leadDegree
        let sounding = soundingPitches
        var blocked: [UUID: UInt64] = [:]
        for line in lines where line.midiEnabled && !line.isModulationSource {
            var mask: UInt64 = 0
            for (segment, pitch) in effectivePitches(for: line, leadDegree: lead).enumerated()
            where !harmony.allows(pitch, against: sounding) {
                mask |= UInt64(1) << UInt64(segment)
            }
            blocked[line.id] = mask
        }
        return SamplerVisualState(activeMasks: masks, blockedMasks: blocked, leadDegree: lead)
    }

    /// Publishes only real changes; the 5 ms tick would otherwise re-render the
    /// sampler visuals on every frame.
    private func emitVisualState() {
        let state = currentVisualState()
        guard state != lastVisualState else { return }
        lastVisualState = state
        onStateChange?(state)
    }

    private func stop(id: UUID, segment: Int) {
        guard let voice = active[id]?.removeValue(forKey: segment) else { return }
        if active[id]?.isEmpty == true { active.removeValue(forKey: id) }
        // Several lines may share a channel, and a host treats one channel+pitch
        // as a single voice. Only release the note once no other line still holds
        // that exact pitch, otherwise this line's release would cut the other short.
        let stillHeld = active.values.contains { voices in
            voices.values.contains { $0.channel == voice.channel && $0.pitch == voice.pitch }
        }
        guard !stillHeld else { return }
        enqueue(status: 0x80 | voice.channel, pitch: voice.pitch, velocity: 0)
    }

    private func stopAll() {
        for (id, voices) in active { voices.keys.forEach { stop(id: id, segment: $0) } }
        bitsets.removeAll()
        levels.removeAll()
        emptyFrames.removeAll()
        lastFrame = 0
        modulationValues.removeAll()
    }

    /// Resolves the destination port for a channel under the current mode.
    private func port(for channel: UInt8) -> MIDIEndpointRef? {
        switch portMode {
        case .single:
            return source == 0 ? nil : source
        case .perLine:
            return channelSource(channel)
        }
    }

    /// Returns (creating if needed) the virtual source dedicated to a channel.
    private func channelSource(_ channel: UInt8) -> MIDIEndpointRef? {
        if let existing = channelSources[channel] { return existing }
        guard client != 0 else { return nil }
        var endpoint = MIDIEndpointRef()
        let name = "DanceFX Ch \(Int(channel) + 1)"
        MIDISourceCreate(client, name as CFString, &endpoint)
        guard endpoint != 0 else { return nil }
        channelSources[channel] = endpoint
        // A new port starts at the current master volume.
        let level = UInt8(min(127, max(0, Int((masterVolume * 127).rounded()))))
        pendingByPort[endpoint, default: []].append(contentsOf: [0xB0 | channel, 7, level])
        return endpoint
    }

    /// Creates one port per in-use channel. Ports are intentionally *not* torn
    /// down while the app runs: a host binds its track inputs to these virtual
    /// devices, and disposing one (for example while switching to a preset that
    /// uses fewer lines, or when no line sampler is present) makes the host drop
    /// the input and forget the routing. Once a `DanceFX Ch N` port has been
    /// published it stays available until the app exits, so preset switches and
    /// temporary absences of a line never disturb the host's track inputs.
    /// Creates one port per channel that has a line.
    /// A port is published as soon as a line exists on its channel, not only when
    /// the line currently sends notes or CC. Hosts like Tracktion Waveform
    /// enumerate MIDI inputs once and do not rescan while running, so the device
    /// has to exist before the user can bind it — and a line can be toggled to
    /// notes or modulation at any time. Ports are never torn down while the app
    /// runs (see the lifetime note on `channelSource`).
    private func reconcileChannelSources(for lines: [SampleLine]) {
        guard portMode == .perLine else { return }
        var needed = Set<UInt8>()
        for line in lines where (0..<16).contains(line.midiChannel) {
            needed.insert(UInt8(line.midiChannel))
        }
        for channel in needed where channelSources[channel] == nil {
            _ = channelSource(channel)
        }
    }

    private func enqueue(status: UInt8, pitch: Int, velocity: UInt8) {
        guard let port = port(for: status & 0x0F) else { return }
        pendingByPort[port, default: []].append(contentsOf: [status, UInt8(clamping: pitch), velocity])
    }

    private func enqueueCC(channel: UInt8, controller: UInt8, value: UInt8) {
        guard let port = port(for: channel) else { return }
        pendingByPort[port, default: []].append(contentsOf: [0xB0 | channel, controller, value])
    }

    /// Sets MIDI channel volume (CC7). This scales the host instrument's output
    /// independently of velocity, which is the only way to go quieter when a
    /// patch has a loud velocity floor. In `.perLine` mode every published port
    /// is updated (not only channels with a current line), so a port stays in
    /// sync even while its line is temporarily absent during a preset switch.
    /// Ports are created by `reconcileChannelSources`, one per configured line's
    /// channel.
    func setMasterVolume(_ value: Double) {
        let clamped = min(1, max(0, value))
        let level = UInt8(min(127, max(0, Int((clamped * 127).rounded()))))
        queue.async { [self] in
            masterVolume = clamped
            let channels: [UInt8]
            if portMode == .single {
                channels = (0..<16).map(UInt8.init)
            } else {
                channels = Array(channelSources.keys).sorted()
            }
            for channel in channels { enqueueCC(channel: channel, controller: 7, value: level) }
            flushMessages()
        }
    }

    /// Sends every queued message, one `MIDIReceived` per destination port,
    /// chunked into ≤256-byte packets.
    private func flushMessages() {
        guard !pendingByPort.isEmpty else { return }
        let batches = pendingByPort
        pendingByPort.removeAll(keepingCapacity: true)
        for (port, bytes) in batches where !bytes.isEmpty {
            send(bytes, to: port)
        }
    }

    private func send(_ bytes: [UInt8], to port: MIDIEndpointRef) {
        let packetCount = (bytes.count + Self.maxPacketBytes - 1) / Self.maxPacketBytes
        let capacity = MemoryLayout<MIDIPacketList>.size
            + packetCount * MemoryLayout<MIDIPacket>.size
            + bytes.count
        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: capacity,
            alignment: MemoryLayout<MIDIPacketList>.alignment
        )
        defer { storage.deallocate() }
        let list = storage.assumingMemoryBound(to: MIDIPacketList.self)
        var packet = MIDIPacketListInit(list)
        var offset = 0
        bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            while offset < bytes.count {
                let chunk = min(Self.maxPacketBytes, bytes.count - offset)
                packet = MIDIPacketListAdd(list, capacity, packet, 0, chunk, base + offset)
                offset += chunk
            }
        }
        MIDIReceived(port, list)
    }
}
