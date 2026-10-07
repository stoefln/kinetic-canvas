import AVFoundation
import Foundation

/// Native clip player for tempo-synced loops and one-shot hits.
///
/// Loops run continuously once started and are muted with a short gain ramp, so
/// their playhead keeps advancing and a later unmute is phase-correct without
/// reprocessing the file from the start. Each loop has its own
/// `AVAudioUnitTimePitch`; `rate` follows the shared `MusicalTransport`, which
/// stretches the loop to the current tempo without changing pitch. One-shots use
/// a small round-robin pool and are played as-is.
///
/// Every public method is safe to call from any thread. Work is serialized on a
/// private control queue, and file decoding happens there too, so the real-time
/// render thread only ever runs Apple's audio units.
final class ClipAudioEngine: @unchecked Sendable {
    private let transport: MusicalTransport
    private let queue = DispatchQueue(label: "kineticcanvas.clip-audio", qos: .userInitiated)
    private let engine = AVAudioEngine()
    private let mainMixer: AVAudioMixerNode
    private let canonicalFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    private let oneShotPoolSize = 8

    private final class LoopVoice {
        let lineID: UUID
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        var buffer: AVAudioPCMBuffer?
        var sourceBPM: Double = 120
        var level: Float = 1
        var signature = ""
        var running = false
        var audible = false
        var missing = false
        var queuedToggle: (active: Bool, time: Double)?
        var fadeGeneration = 0
        init(lineID: UUID) { self.lineID = lineID }
    }

    private struct ConfigureRequest {
        let lines: [SampleLine]
        let enabled: Bool
        /// True while the app session is running. The engine must stay up for
        /// the whole session because hosted instruments share it, even when no
        /// clip is playing.
        let sessionActive: Bool
        let quantize: Bool
        let masterVolume: Double
    }

    private struct LineInfo {
        var destination: SampleLineDestination
        var hasClip: Bool
        var missing: Bool
    }

    private var loopVoices: [UUID: LoopVoice] = [:]
    private var oneShotBuffers: [UUID: AVAudioPCMBuffer] = [:]
    private var oneShotLevels: [UUID: Float] = [:]
    private var oneShotSignatures: [UUID: String] = [:]
    private var lineInfo: [UUID: LineInfo] = [:]
    private var oneShotPool: [AVAudioPlayerNode] = []
    private var nextOneShot = 0
    private var pendingOneShots: [UUID: [Double]] = [:]

    private var isRunning = false
    private var enabled = false
    private var quantize = true
    private var masterVolume: Float = 0.8
    private var timer: DispatchSourceTimer?
    private var lastRateBPM: Double = 0
    private var configurationObserver: NSObjectProtocol?

    private let requestLock = NSLock()
    private var latestRequest: ConfigureRequest?
    private var configureScheduled = false

    private var lastPublished: [UUID: ClipPlaybackState] = [:]

    /// Called on the control queue whenever any line's clip state changes.
    var onStateChange: (@Sendable ([UUID: ClipPlaybackState]) -> Void)?

    init(transport: MusicalTransport) {
        self.transport = transport
        self.mainMixer = engine.mainMixerNode
        mainMixer.outputVolume = masterVolume
        for _ in 0..<oneShotPoolSize {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: mainMixer, format: canonicalFormat)
            oneShotPool.append(player)
        }
    }

    deinit {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
    }

    // MARK: - Lifecycle

    func start(lines: [SampleLine], enabled: Bool, quantize: Bool, masterVolume: Double) {
        queue.async { [self] in
            isRunning = true
            do {
                if !engine.isRunning {
                    engine.prepare()
                    try engine.start()
                }
            } catch {
                isRunning = false
                return
            }
            mainMixer.outputVolume = Float(min(1, max(0, masterVolume)))
            self.masterVolume = mainMixer.outputVolume
            observeConfigurationChange()
            startTimer()
            lastRateBPM = transport.bpm
            applyConfigure(ConfigureRequest(lines: lines, enabled: enabled,
                                            sessionActive: true, quantize: quantize, masterVolume: masterVolume))
        }
    }

    func stop() {
        queue.async { [self] in
            isRunning = false
            enabled = false
            stopTimer()
            for voice in loopVoices.values {
                voice.player.stop()
                voice.running = false
                voice.audible = false
                voice.queuedToggle = nil
            }
            for player in oneShotPool { player.stop() }
            pendingOneShots.removeAll()
            removeConfigurationObserver()
            if engine.isRunning { engine.pause() }
            publish()
        }
    }

    /// Reconfigures the active lines. Cheap to call often: redundant calls are
    /// coalesced and files are only reloaded when a clip reference changes.
    /// `sessionActive` keeps the engine running while the app session runs, so
    /// hosted instruments stay audible even when no clip is playing.
    func configure(lines: [SampleLine], enabled: Bool, sessionActive: Bool,
                   quantize: Bool, masterVolume: Double) {
        let request = ConfigureRequest(lines: lines, enabled: enabled,
                                       sessionActive: sessionActive,
                                       quantize: quantize, masterVolume: masterVolume)
        requestLock.lock()
        latestRequest = request
        let schedule = !configureScheduled
        if schedule { configureScheduled = true }
        requestLock.unlock()
        guard schedule else { return }
        queue.async { [self] in drainConfigure() }
    }

    func setMasterVolume(_ value: Double) {
        queue.async { [self] in
            masterVolume = Float(min(1, max(0, value)))
            mainMixer.outputVolume = masterVolume
        }
    }

    /// Runs a graph edit on the engine's control queue so it serializes with
    /// start/stop and the clip voices. The instrument host attaches its AU nodes
    /// through here so one app engine owns mixing and output.
    func performGraphEdit(_ body: @escaping @Sendable (AVAudioEngine, AVAudioMixerNode) -> Void) {
        queue.async { [self] in body(engine, mainMixer) }
    }

    /// Handles a rising-edge trigger from the Line Sampler clock.
    func handle(_ trigger: LineAudioTrigger) {
        queue.async { [self] in
            guard isRunning, enabled else { return }
            let now = ProcessInfo.processInfo.systemUptime
            switch trigger.destination {
            case .loop:
                guard let voice = loopVoices[trigger.lineID], voice.buffer != nil else { return }
                let currentlyOn = voice.running && voice.audible
                let target = voice.queuedToggle.map { !$0.active } ?? !currentlyOn
                voice.queuedToggle = (target, transport.nextBarTime(after: now))
                publish()
            case .oneShot:
                guard oneShotBuffers[trigger.lineID] != nil else { return }
                let time = trigger.quantize ? transport.nextStepTime(after: now) : now
                pendingOneShots[trigger.lineID, default: []].append(time)
                publish()
            case .midi:
                break
            case .vital:
                break
            }
        }
    }

    // MARK: - Configuration

    private func drainConfigure() {
        while true {
            requestLock.lock()
            guard let request = latestRequest else {
                configureScheduled = false
                requestLock.unlock()
                return
            }
            latestRequest = nil
            requestLock.unlock()
            applyConfigure(request)
        }
    }

    private func applyConfigure(_ request: ConfigureRequest) {
        isRunning = request.sessionActive
        if isRunning, !engine.isRunning {
            engine.prepare()
            try? engine.start()
        }
        enabled = request.enabled && isRunning
        quantize = request.quantize
        masterVolume = Float(min(1, max(0, request.masterVolume)))
        mainMixer.outputVolume = masterVolume

        let loopLines = request.lines.filter { $0.destination == .loop && $0.isEnabled }
        let oneShotLines = request.lines.filter { $0.destination == .oneShot && $0.isEnabled }
        let loopIDs = Set(loopLines.map(\.id))
        let oneShotIDs = Set(oneShotLines.map(\.id))

        for id in loopVoices.keys where !loopIDs.contains(id) { removeLoopVoice(id) }
        for id in oneShotBuffers.keys where !oneShotIDs.contains(id) {
            oneShotBuffers[id] = nil
            oneShotLevels[id] = nil
            oneShotSignatures[id] = nil
        }

        var info: [UUID: LineInfo] = [:]

        for line in loopLines {
            let voice = loopVoices[line.id] ?? makeLoopVoice(line.id)
            guard let clip = line.clip else {
                stopVoice(voice)
                voice.buffer = nil
                voice.signature = ""
                voice.missing = false
                info[line.id] = LineInfo(destination: .loop, hasClip: false, missing: false)
                continue
            }
            let signature = Self.signature(for: clip)
            if voice.signature != signature {
                voice.signature = signature
                if let buffer = loadBuffer(from: clip) {
                    voice.buffer = buffer
                    voice.missing = false
                } else {
                    voice.buffer = nil
                    voice.missing = true
                    stopVoice(voice)
                }
            }
            voice.sourceBPM = clip.sourceBPM
            voice.level = Float(clip.level)
            updateRate(voice)
            if voice.audible { voice.player.volume = voice.level }

            if !enabled {
                stopVoice(voice)
            } else if !clip.startMuted, voice.buffer != nil, !voice.running, voice.queuedToggle == nil {
                // A non-muted loop sounds without a manual toggle. Start it at
                // once; user toggles still land on the next bar line.
                voice.queuedToggle = (true, ProcessInfo.processInfo.systemUptime)
            }
            info[line.id] = LineInfo(destination: .loop, hasClip: true, missing: voice.missing)
        }

        for line in oneShotLines {
            guard let clip = line.clip else {
                oneShotBuffers[line.id] = nil
                oneShotLevels[line.id] = nil
                oneShotSignatures[line.id] = nil
                info[line.id] = LineInfo(destination: .oneShot, hasClip: false, missing: false)
                continue
            }
            let signature = Self.signature(for: clip)
            if oneShotSignatures[line.id] != signature {
                oneShotSignatures[line.id] = signature
                oneShotBuffers[line.id] = loadBuffer(from: clip)
            }
            oneShotLevels[line.id] = Float(clip.level)
            info[line.id] = LineInfo(destination: .oneShot, hasClip: true,
                                     missing: oneShotBuffers[line.id] == nil)
        }

        lineInfo = info
        publish()
    }

    private func makeLoopVoice(_ id: UUID) -> LoopVoice {
        let voice = LoopVoice(lineID: id)
        engine.attach(voice.player)
        engine.attach(voice.timePitch)
        engine.connect(voice.player, to: voice.timePitch, format: canonicalFormat)
        engine.connect(voice.timePitch, to: mainMixer, format: canonicalFormat)
        voice.player.volume = 0
        loopVoices[id] = voice
        return voice
    }

    private func removeLoopVoice(_ id: UUID) {
        guard let voice = loopVoices.removeValue(forKey: id) else { return }
        voice.player.stop()
        engine.detach(voice.player)
        engine.detach(voice.timePitch)
    }

    // MARK: - Loops

    private func startLoop(_ voice: LoopVoice) {
        guard let buffer = voice.buffer else { return }
        updateRate(voice)
        if !voice.running {
            voice.player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
            voice.player.play()
            voice.running = true
        }
        voice.audible = true
        ramp(voice, to: voice.level)
    }

    private func stopLoop(_ voice: LoopVoice) {
        voice.queuedToggle = nil
        guard voice.running else { return }
        voice.audible = false
        ramp(voice, to: 0)
    }

    /// Fully stops a loop's player, dropping its phase. Used when the effect is
    /// disabled or the clip is removed, so re-enabling starts from a bar line.
    private func stopVoice(_ voice: LoopVoice) {
        voice.queuedToggle = nil
        voice.player.stop()
        voice.player.volume = 0
        voice.running = false
        voice.audible = false
    }

    private func updateRate(_ voice: LoopVoice) {
        let ratio = transport.bpm / max(30, voice.sourceBPM)
        voice.timePitch.rate = Float(min(max(ratio, 1.0 / 32.0), 32.0))
    }

    /// Gain ramp, expressed as a few scheduled steps so a toggle never clicks.
    private func ramp(_ voice: LoopVoice, to target: Float) {
        voice.fadeGeneration += 1
        let generation = voice.fadeGeneration
        let start = voice.player.volume
        let steps = 8
        let interval = 0.0025
        for step in 1...steps {
            let value = start + (target - start) * Float(step) / Float(steps)
            queue.asyncAfter(deadline: .now() + interval * Double(step)) { [weak voice] in
                guard let voice, voice.fadeGeneration == generation else { return }
                voice.player.volume = value
            }
        }
    }

    // MARK: - One-shots

    private func fireOneShot(_ lineID: UUID) {
        guard let buffer = oneShotBuffers[lineID], !oneShotPool.isEmpty else { return }
        let player = oneShotPool[nextOneShot % oneShotPool.count]
        nextOneShot = (nextOneShot + 1) % oneShotPool.count
        player.volume = oneShotLevels[lineID] ?? 1
        player.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionHandler: nil)
        player.play()
    }

    // MARK: - Clock

    private func startTimer() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + .milliseconds(5),
                        repeating: .milliseconds(5), leeway: .milliseconds(2))
        source.setEventHandler { [weak self] in self?.tick() }
        timer = source
        source.resume()
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        transport.commitPending(at: now)

        let bpm = transport.bpm
        if bpm != lastRateBPM {
            lastRateBPM = bpm
            for voice in loopVoices.values { updateRate(voice) }
        }

        var changed = false
        for voice in loopVoices.values {
            guard let queued = voice.queuedToggle, now >= queued.time else { continue }
            voice.queuedToggle = nil
            if queued.active { startLoop(voice) } else { stopLoop(voice) }
            changed = true
        }

        if !pendingOneShots.isEmpty {
            for (lineID, times) in Array(pendingOneShots) {
                let due = times.filter { $0 <= now }
                guard !due.isEmpty else { continue }
                for _ in due { fireOneShot(lineID) }
                let remaining = times.filter { $0 > now }
                if remaining.isEmpty { pendingOneShots[lineID] = nil } else { pendingOneShots[lineID] = remaining }
                changed = true
            }
        }

        if changed { publish() }
    }

    // MARK: - Device changes

    private func observeConfigurationChange() {
        guard configurationObserver == nil else { return }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.queue.async { self.restartAfterConfigurationChange() }
        }
    }

    private func removeConfigurationObserver() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
    }

    private func restartAfterConfigurationChange() {
        guard isRunning else { return }
        do {
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
        } catch {
            return
        }
        // The change clears scheduled buffers, so restart every loop that was
        // playing. This restarts loops at phase 0, a short audible reset that is
        // preferable to silence after a device swap.
        for voice in loopVoices.values where voice.running {
            guard let buffer = voice.buffer else { continue }
            voice.player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
            voice.player.volume = voice.audible ? voice.level : 0
            voice.player.play()
        }
    }

    // MARK: - Loading

    private func loadBuffer(from clip: AudioClipReference) -> AVAudioPCMBuffer? {
        guard let url = clip.resolveURL() else { return nil }
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let length = file.length
        guard length > 0, length <= AVAudioFramePosition(UInt32.max) else { return nil }
        guard let raw = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                         frameCapacity: AVAudioFrameCount(length)) else { return nil }
        do { try file.read(into: raw) } catch { return nil }
        raw.frameLength = AVAudioFrameCount(length)
        return convert(raw, to: canonicalFormat)
    }

    /// Converts any imported file to one canonical float format so every voice
    /// shares a single engine connection and no reconnection is needed later.
    private func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var error: NSError?
        var fed = false
        let input: AVAudioConverterInputBlock = { _, status in
            if fed {
                status.pointee = .endOfStream
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        converter.convert(to: output, error: &error, withInputFrom: input)
        return error == nil ? output : nil
    }

    private static func signature(for clip: AudioClipReference) -> String {
        "\(clip.path)|\(clip.fileName)|\(clip.bookmark?.hashValue ?? 0)"
    }

    // MARK: - State

    private func publish() {
        var states: [UUID: ClipPlaybackState] = [:]
        for (id, info) in lineInfo {
            guard info.hasClip else {
                states[id] = .empty
                continue
            }
            guard !info.missing else {
                states[id] = .missing
                continue
            }
            switch info.destination {
            case .loop:
                if let voice = loopVoices[id], let queued = voice.queuedToggle {
                    states[id] = queued.active ? .queuedStart : .queuedStop
                } else if let voice = loopVoices[id], voice.running {
                    states[id] = voice.audible ? .playing : .muted
                } else {
                    states[id] = .ready
                }
            case .oneShot:
                states[id] = .ready
            case .midi:
                states[id] = .empty
            case .vital:
                states[id] = .empty
            }
        }
        guard states != lastPublished else { return }
        lastPublished = states
        onStateChange?(states)
    }
}
