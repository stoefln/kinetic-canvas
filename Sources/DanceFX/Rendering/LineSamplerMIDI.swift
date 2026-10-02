import CoreMIDI
import Foundation

/// A single sixteenth-note clock. All mutable state lives on `queue`.
final class LineSamplerMIDI: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dancefx.line-sampler-midi", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    private var lines: [SampleLine] = []
    private var enabled = false
    private var bpm = 120.0
    private var bitsets: [UUID: UInt16] = [:]
    private var emptyFrames: [UUID: [Int: Int]] = [:]
    private var lastFrame: Double = 0
    private var nextStep: Double = 0
    private var stepIndex: Int64 = 0
    private var active: [UUID: [Int: Voice]] = [:]
    /// Flattened Note On/Off triples collected during one callback and sent in a
    /// single `MIDIReceived` call instead of one CoreMIDI call per note.
    private var pendingMessages: [UInt8] = []
    private static let maxPacketBytes = 256
    private struct Voice { let pitch: Int; let channel: UInt8; let offAt: Double }

    init() {
        MIDIClientCreate("DanceFX" as CFString, nil, nil, &client)
        if client != 0 { MIDISourceCreate(client, "DanceFX Line Sampler" as CFString, &source) }
    }

    deinit {
        timer?.cancel()
        // `deinit` cannot safely drain an in-flight queue; the app calls stop on shutdown.
        if source != 0 { MIDIEndpointDispose(source) }
        if client != 0 { MIDIClientDispose(client) }
    }

    func configure(lines newLines: [SampleLine], bpm newBPM: Double, enabled newEnabled: Bool) {
        queue.async { [self] in
            let old = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0) })
            let now = ProcessInfo.processInfo.systemUptime
            let oldDuration = 15 / bpm
            let clampedBPM = min(240, max(30, newBPM))
            if clampedBPM != bpm && nextStep > 0 {
                nextStep = now + (nextStep - now) * (15 / clampedBPM) / oldDuration
            }
            bpm = clampedBPM
            for (id, voices) in active {
                guard let prior = old[id], let next = newLines.first(where: { $0.id == id }),
                      newEnabled, next.midiEnabled, prior.scale == next.scale,
                      prior.root == next.root, prior.octave == next.octave,
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
            flushMessages()
        }
    }

    func updateOccupancy(_ states: [UUID: UInt16]) {
        queue.async { [self] in
            var stabilized: [UUID: UInt16] = [:]
            for (id, observed) in states {
                var value = observed
                for segment in 0..<12 {
                    let bit = UInt16(1 << segment)
                    if observed & bit != 0 {
                        emptyFrames[id, default: [:]][segment] = 0
                    } else if (bitsets[id] ?? 0) & bit != 0 {
                        let count = (emptyFrames[id]?[segment] ?? 0) + 1
                        emptyFrames[id, default: [:]][segment] = count
                        if count < 2 { value |= bit }
                    }
                }
                stabilized[id] = value
            }
            bitsets = stabilized
            lastFrame = ProcessInfo.processInfo.systemUptime
        }
    }

    func stop() {
        // `sync` bounds the wait to one cheap tick (≤5 ms) and guarantees the
        // final Note Offs are committed before the app exits, avoiding stuck notes.
        queue.sync {
            enabled = false
            stopAll()
            nextStep = 0
            stepIndex = 0
            timer?.cancel()
            timer = nil
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
            // Single-shot lines follow pixel presence continuously, not the grid.
            reconcileSingleShots(fresh: fresh)
            let duration = 15 / bpm
            if now - nextStep > duration * 2 {
                let skipped = Int64((now - nextStep) / duration)
                stepIndex += skipped
                nextStep += Double(skipped) * duration
            }
            if now >= nextStep {
                for line in lines where line.midiEnabled && line.triggerMode == .rhythm {
                    guard stepIndex % Int64(max(1, line.rhythm)) == 0 else { continue }
                    guard (0..<16).contains(line.midiChannel) else { continue }
                    let channel = UInt8(line.midiChannel)
                    let mask = fresh ? (bitsets[line.id] ?? 0) : 0
                    let gate = duration * Double(max(1, line.rhythm)) * 0.5
                    for (segment, pitch) in line.pitches.enumerated() where mask & (UInt16(1) << segment) != 0 {
                        stop(id: line.id, segment: segment)
                        enqueue(status: 0x90 | channel, pitch: pitch, velocity: 96)
                        active[line.id, default: [:]][segment] = Voice(pitch: pitch, channel: channel, offAt: now + gate)
                    }
                }
                stepIndex += 1
                nextStep += duration
            }
        }
        flushMessages()
    }

    /// Holds a note on for every single-shot segment that currently has pixels
    /// and releases it as soon as the segment empties (or the feed goes stale).
    private func reconcileSingleShots(fresh: Bool) {
        for line in lines where line.midiEnabled && line.triggerMode == .singleShot {
            guard (0..<16).contains(line.midiChannel) else {
                active[line.id]?.keys.forEach { stop(id: line.id, segment: $0) }
                continue
            }
            let channel = UInt8(line.midiChannel)
            let mask = fresh ? (bitsets[line.id] ?? 0) : 0
            if let voices = active[line.id] {
                for segment in voices.keys where mask & (UInt16(1) << segment) == 0 {
                    stop(id: line.id, segment: segment)
                }
            }
            for (segment, pitch) in line.pitches.enumerated() where mask & (UInt16(1) << segment) != 0 {
                guard active[line.id]?[segment] == nil else { continue }
                enqueue(status: 0x90 | channel, pitch: pitch, velocity: 96)
                // `.infinity` keeps the voice out of the timed gate release.
                active[line.id, default: [:]][segment] = Voice(pitch: pitch, channel: channel, offAt: .infinity)
            }
        }
    }

    private func stop(id: UUID, segment: Int) {
        guard let voice = active[id]?.removeValue(forKey: segment) else { return }
        enqueue(status: 0x80 | voice.channel, pitch: voice.pitch, velocity: 0)
        if active[id]?.isEmpty == true { active.removeValue(forKey: id) }
    }

    private func stopAll() {
        for (id, voices) in active { voices.keys.forEach { stop(id: id, segment: $0) } }
        bitsets.removeAll()
        emptyFrames.removeAll()
        lastFrame = 0
    }

    private func enqueue(status: UInt8, pitch: Int, velocity: UInt8) {
        guard source != 0 else { return }
        pendingMessages.append(status)
        pendingMessages.append(UInt8(clamping: pitch))
        pendingMessages.append(velocity)
    }

    /// Sends every queued message in a single `MIDIReceived` call, chunked into
    /// ≤256-byte packets. A busy tick with 16 chromatic lines would otherwise
    /// issue up to 192 separate CoreMIDI calls in one burst.
    private func flushMessages() {
        guard source != 0, !pendingMessages.isEmpty else {
            pendingMessages.removeAll(keepingCapacity: true)
            return
        }
        let bytes = pendingMessages
        pendingMessages.removeAll(keepingCapacity: true)
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
        MIDIReceived(source, list)
    }
}
