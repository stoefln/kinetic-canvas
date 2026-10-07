import AppKit
import AVFoundation
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppController: ObservableObject {
    @Published private(set) var cameras: [CameraDescriptor] = []
    @Published private(set) var selectedCameraID = ""
    @Published var mode: DisplayMode = .composite {
        didSet { renderer.displayMode = mode }
    }
    @Published var background: BackgroundChoice = .black {
        didSet { renderer.background = background }
    }
    @Published private(set) var rvmProfile: RVMProfile = .fast360p
    @Published var activeEffects: [EffectKind] = [.gradientOverlay, .historicalTrail] { didSet { syncEffects() } }
    @Published private(set) var disabledEffects: Set<EffectKind> = [] { didSet { syncEffects() } }
    /// Effects whose parameter panel is collapsed in the stack. View-only state,
    /// so it does not touch the renderer; it is saved with the preset.
    @Published var collapsedEffects: Set<EffectKind> = []
    @Published private(set) var effectBlendModes: [EffectKind: OverlayBlendMode] = [:] { didSet { syncEffects() } }
    @Published var gradientStyle: GradientStyle = .neon { didSet { syncEffects() } }
    @Published var gradientOpacity = 0.72 { didSet { syncEffects() } }
    @Published var gradientAngleDegrees = 83.0 { didSet { syncEffects() } }
    @Published var cloneCount = 15 { didSet { syncEffects() } }
    @Published var cloneRotationDegrees = 3.0 { didSet { syncEffects() } }
    @Published var cloneScalePercent = -1.5 { didSet { syncEffects() } }
    @Published var cloneTranslationXPercent = 1.5 { didSet { syncEffects() } }
    @Published var cloneTranslationYPercent = 0.4 { didSet { syncEffects() } }
    @Published var cloneOpacity = 0.50 { didSet { syncEffects() } }
    @Published var cloneDecay = 0.96 { didSet { syncEffects() } }
    @Published var trailLifetime = 3.0 { didSet { syncEffects() } }
    @Published var liquidStrength = 2.5 { didSet { syncEffects() } }
    @Published var liquidScale = 5.0 { didSet { syncEffects() } }
    @Published var liquidSpeed = 1.0 { didSet { syncEffects() } }
    @Published var videoOpacity = 1.0 { didSet { syncEffects() } }
    @Published var videoPlaybackRate = 1.0 { didSet { syncEffects() } }
    @Published var videoScale = 1.0 { didSet { syncEffects() } }
    @Published private(set) var videoAssets: [VideoAsset] = []
    @Published var selectedVideoAssetID = "" {
        didSet {
            guard !isApplyingPreset else { return }
            syncEffects()
            renderer.clearTrailHistory()
        }
    }
    @Published var videoFillTiming: VideoFillTiming = .live {
        didSet {
            guard !isApplyingPreset else { return }
            syncEffects()
            renderer.clearTrailHistory()
        }
    }
    @Published var skeletonOpacity = 1.0 { didSet { syncEffects() } }
    @Published var skeletonConfidence = 0.35 { didSet { syncEffects() } }
    @Published var linesOpacity = 0.65 { didSet { syncEffects() } }
    @Published var linesConfidence = 0.35 { didSet { syncEffects() } }
    @Published var linesConnections = 3 { didSet { syncEffects() } }
    @Published var linesThickness = 2.0 { didSet { syncEffects() } }
    @Published var linesGeometryOnly = true {
        didSet {
            guard !isApplyingPreset else { return }
            syncEffects()
            renderer.clearTrailHistory()
        }
    }
    /// How many bodies Vision tracks at once. One is the fastest and most stable;
    /// higher values add a skeleton, mesh, and limb emitters per person. Global
    /// because it shapes the shared pose detection every pose-driven effect reads.
    @Published var maxPeople = 1
    @Published var sampleLines: [SampleLine] = [] {
        didSet {
            if !isApplyingPreset {
                lineMIDI.configure(lines: sampleLines, harmony: sampleHarmony, bpm: sampleBPM, threshold: sampleTriggerThreshold, quantize: sampleQuantize, transposeMode: sampleTransposeMode, portMode: sampleMIDIPortMode,
                                   enabled: isSessionRunning && isEffectEnabled(.lineSampler))
            }
            syncEffects()
        }
    }
    /// Global harmony shared by every line. Root and Scale are no longer per line.
    @Published var sampleRoot = 0 {
        didSet {
            guard !isApplyingPreset else { return }
            clampSampleOctaves()
            syncEffects()
        }
    }
    @Published var sampleScale: SampleScale = .chromatic {
        didSet {
            guard !isApplyingPreset else { return }
            clampSampleOctaves()
            syncEffects()
        }
    }
    @Published var sampleTension = 0.5 { didSet { syncEffects() } }
    /// Global minimum lit fraction for a line segment to trigger a note.
    @Published var sampleTriggerThreshold = 0.2 { didSet { syncEffects() } }
    /// Global note-name labels on the line segments.
    @Published var sampleShowNotes = false
    /// Global onset quantization: new notes wait for the next 16th-note grid line.
    @Published var sampleQuantize = true { didSet { syncEffects() } }
    @Published var testNoteVelocity = 100.0
    /// Global MIDI channel volume (CC7) applied to every channel, and the clip
    /// engine's master level.
    @Published var sampleMasterVolume = 0.8 {
        didSet {
            lineMIDI.setMasterVolume(sampleMasterVolume)
            clipAudio.setMasterVolume(sampleMasterVolume)
        }
    }
    /// How the lead line transposes the other lines.
    @Published var sampleTransposeMode: SampleTransposeMode = .diatonic { didSet { syncEffects() } }
    /// Single shared MIDI port, or one virtual port per line. Port per line is
    /// the default because many hosts bind an input to a single track.
    @Published var sampleMIDIPortMode: SampleMIDIPortMode = .perLine { didSet { syncEffects() } }
    var sampleHarmony: SampleHarmony {
        SampleHarmony(root: sampleRoot, scale: sampleScale, tension: sampleTension)
    }
    @Published var sampleBPM = 120.0 {
        didSet {
            transport.requestBPM(sampleBPM, at: ProcessInfo.processInfo.systemUptime)
            syncEffects()
        }
    }
    @Published var sampleDirection: SampleDirection = .both { didSet { syncEffects() } }
    @Published var sampleSpeed = 180.0 { didSet { syncEffects() } }
    @Published var sampleCount = 180 { didSet { syncEffects() } }
    @Published var sampleThickness = 3.0 { didSet { syncEffects() } }
    @Published var sampleOpacity = 0.8 { didSet { syncEffects() } }
    @Published var sampleFade = 1.0 { didSet { syncEffects() } }
    @Published var particleRate = 60.0 { didSet { syncEffects() } }
    @Published var particleLifetime = 1.2 { didSet { syncEffects() } }
    @Published var particleSizeScale = 1.0 { didSet { syncEffects() } }
    @Published var particleColorSource: ParticleColorSource = .liveBelow { didSet { syncEffects() } }
    @Published var particleMotionSize = 2.5 { didSet { syncEffects() } }
    @Published var particleSpeed = 1.0 { didSet { syncEffects() } }
    @Published var particleSpreadDegrees = 30.0 { didSet { syncEffects() } }
    @Published var particleGravity = 0.08 { didSet { syncEffects() } }
    @Published var particleDrag = 0.0 { didSet { syncEffects() } }
    @Published var particleEndSize = 0.55 { didSet { syncEffects() } }
    @Published var particleShape: ParticleShape = .disc { didSet { syncEffects() } }
    @Published var particleMomentum = 0.65 { didSet { syncEffects() } }
    @Published var particleSpawnSource: ParticleSpawnSource = .limbs { didSet { syncEffects() } }
    @Published var particleBorderThreshold = 0.5 { didSet { syncEffects() } }
    @Published var clapExplosionSize = 0.5 { didSet { syncEffects() } }
    @Published var clapExplosionOpacity = 1.0 { didSet { syncEffects() } }
    @Published private(set) var presets: [EffectPreset] = []
    @Published private(set) var selectedPresetID: UUID? {
        didSet { persistSelectedPresetID() }
    }
    @Published var presetName = ""
    @Published private(set) var isSavingPreset = false
    /// Kept off `AppController`'s `@Published` surface so metrics updates do not
    /// re-render the whole control panel. See `MetricsStore`.
    let metricsStore = MetricsStore()
    /// Same idea for per-segment note state driving the sampler visuals.
    let samplerState = SamplerStateStore()
    @Published private(set) var statusMessage: String?
    @Published private(set) var projectorStatus = "Preparing video output…"
    @Published private(set) var projectorConnected = false
    @Published var controlPanelTransparent = false {
        didSet {
            UserDefaults.standard.set(controlPanelTransparent, forKey: Self.controlPanelTransparentKey)
        }
    }

    let renderer: MetalRenderer
    /// Single musical clock shared by the MIDI grid and the clip audio engine.
    let transport = MusicalTransport()
    private let lineMIDI: LineSamplerMIDI
    /// Native clip player for tempo-synced loops and one-shot hits.
    let clipAudio: ClipAudioEngine
    /// Per-line clip state, kept off the published surface so a loop state
    /// change does not rebuild the whole control panel.
    let clipState: ClipStateStore
    /// Vital-only AU instrument host, sharing the clip engine's audio graph.
    let instrumentHost: InstrumentHost
    /// Vital availability and per-line slot status, kept off the published surface.
    let instrumentState = InstrumentStateStore()
    private var projectorOutput: ProjectorOutputController?
    private let camera = CameraManager()
    private var engine: MattingEngine
    private let monitor = PerformanceMonitor()
    private let inferenceQueue = DispatchQueue(label: "kineticcanvas.inference", qos: .userInteractive)
    private let poseQueue = DispatchQueue(label: "kineticcanvas.pose", qos: .userInitiated)
    private let poseDetector = BodyPoseDetector()
    private var inferenceInProgress = false
    private var poseInferenceInProgress = false
    private var poseFrameCounter = 0
    private var isApplyingPreset = false
    private var isSessionRunning = false
    private var presetSelectionTask: Task<Void, Never>?
    private var effectSyncTask: Task<Void, Never>?
    private var pendingPresetCaptureID: UUID?
    /// Vital editor windows, kept alive by line id so reopening focuses them.
    private var vitalWindows: [UUID: NSWindow] = [:]
    private var metricsTimer: Timer?
    private static let presetsKey = "kineticcanvas.effectPresets.v1"
    private static let selectedPresetKey = "kineticcanvas.selectedPresetID.v1"
    private static let controlPanelTransparentKey = "kineticcanvas.controlPanel.transparent.v1"

    init() {
        Self.migrateLegacyStateIfNeeded()
        renderer = MetalRenderer()
        let midi = LineSamplerMIDI(transport: transport)
        lineMIDI = midi
        let audio = ClipAudioEngine(transport: transport)
        clipAudio = audio
        let stateStore = ClipStateStore()
        clipState = stateStore
        // A rising edge on a loop or one-shot line toggles or fires its clip.
        midi.onAudioTrigger = { trigger in audio.handle(trigger) }
        audio.onStateChange = { [weak stateStore] states in
            Task { @MainActor in stateStore?.states = states }
        }
        // The Vital host attaches its AU nodes to the same engine so one app
        // engine owns mixing and output.
        let host = InstrumentHost { body in audio.performGraphEdit(body) }
        instrumentHost = host
        let instrumentStore = instrumentState
        midi.onInstrumentEvent = { event in host.handle(event) }
        host.onStatusChange = { [weak instrumentStore] statuses in
            Task { @MainActor in instrumentStore?.statuses = statuses }
        }
        instrumentStore.availability = host.availability
        instrumentStore.sounds = AUStateStore.catalog()
        renderer.lineMIDI = midi
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak midi] _ in
            midi?.stop()
        }
        controlPanelTransparent = UserDefaults.standard.bool(forKey: Self.controlPanelTransparentKey)
        do {
            engine = try RVMEngine.bundled(profile: .fast360p, computeUnits: .all)
        } catch {
            print("RVM unavailable; using Vision fallback: \(error.localizedDescription)")
            engine = VisionMattingEngine()
        }
        camera.onFrame = { [weak self] frame in
            Task { @MainActor in self?.accept(frame: frame) }
        }
        camera.onError = { [weak self] message in
            Task { @MainActor in self?.setStatusMessage(message) }
        }

        videoAssets = Self.discoverVideoAssets()
        for asset in videoAssets {
            renderer.configureVideoFill(url: asset.url, id: asset.id)
        }
        selectedVideoAssetID = defaultVideoAssetID

        let storedPresets = Self.loadStoredPresets()
        presets = storedPresets.isEmpty ? [Self.defaultPreset] : storedPresets
        if storedPresets.isEmpty { persistPresets() }
        // Restore the last selected preset, falling back to the first if it was
        // deleted or the stored id is stale.
        let storedSelection = UserDefaults.standard.string(forKey: Self.selectedPresetKey)
            .flatMap(UUID.init(uuidString:))
        if let initial = presets.first(where: { $0.id == storedSelection }) ?? presets.first {
            apply(initial)
            selectedPresetID = initial.id
            presetName = initial.name
            persistSelectedPresetID()
        }

        projectorOutput = ProjectorOutputController(renderer: renderer, controller: self) { [weak self] message, connected in
            self?.projectorStatus = message
            self?.projectorConnected = connected
        }
        lineMIDI.onStateChange = { [weak self] state in
            Task { @MainActor [weak self] in self?.samplerState.state = state }
        }
    }

    func start() {
        isSessionRunning = true
        transport.start(at: ProcessInfo.processInfo.systemUptime)
        lineMIDI.configure(lines: sampleLines, harmony: sampleHarmony, bpm: sampleBPM, threshold: sampleTriggerThreshold, quantize: sampleQuantize, transposeMode: sampleTransposeMode, portMode: sampleMIDIPortMode,
                           enabled: isEffectEnabled(.lineSampler))
        lineMIDI.setMasterVolume(sampleMasterVolume)
        clipAudio.start(lines: sampleLines, enabled: isEffectEnabled(.lineSampler),
                        quantize: sampleQuantize, masterVolume: sampleMasterVolume)
        instrumentHost.configure(lines: sampleLines, enabled: isEffectEnabled(.lineSampler))
        projectorOutput?.start()
        cameras = camera.availableCameras()
        selectedCameraID = cameras.first?.id ?? ""
        guard !selectedCameraID.isEmpty else {
            setStatusMessage("No camera was found. Connect a webcam or capture device.")
            return
        }
        updateOutputMirroring(cameraID: selectedCameraID)

        metricsTimer?.invalidate()
        metricsTimer = .scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.metricsStore.snapshot = self.monitor.snapshot() }
        }

        Task {
            let granted = await camera.requestAccess()
            guard granted else {
                setStatusMessage("Camera access was denied. Enable it in System Settings → Privacy & Security → Camera.")
                return
            }
            do {
                try camera.start(cameraID: selectedCameraID)
                setStatusMessage("\(engine.displayName) active.")
            } catch {
                setStatusMessage(error.localizedDescription)
            }
        }
    }

    func stop() {
        isSessionRunning = false
        lineMIDI.stop()
        clipAudio.stop()
        instrumentHost.stop()
        transport.reset()
        projectorOutput?.stop()
        metricsTimer?.invalidate()
        metricsTimer = nil
        camera.stop()
        engine.reset()
        renderer.clearTrailHistory()
        renderer.clearSampleHistory()
        renderer.clearPose()
        poseQueue.async { [poseDetector] in poseDetector.reset() }
    }

    func refreshProjectorOutput() {
        projectorOutput?.refresh()
    }

    func selectCamera(id: String) {
        guard id != selectedCameraID else { return }
        selectedCameraID = id
        engine.reset()
        renderer.clearTrailHistory()
        renderer.clearSampleHistory()
        renderer.clearPose()
        poseQueue.async { [poseDetector] in poseDetector.reset() }
        do {
            try camera.switchCamera(cameraID: id)
            updateOutputMirroring(cameraID: id)
        } catch {
            setStatusMessage(error.localizedDescription)
        }
    }

    private func updateOutputMirroring(cameraID: String) {
        renderer.mirrorOutput = cameras.first(where: { $0.id == cameraID })?.mirrorsOutput ?? false
    }

    func resetMatting() {
        engine.reset()
        renderer.clearTrailHistory()
        renderer.clearSampleHistory()
        renderer.clearPose()
        poseQueue.async { [poseDetector] in poseDetector.reset() }
    }

    func selectRVMProfile(_ profile: RVMProfile) {
        guard profile != rvmProfile else { return }
        do {
            let replacement = try RVMEngine.bundled(profile: profile, computeUnits: .all)
            engine.reset()
            engine = replacement
            rvmProfile = profile
            monitor.reset()
            metricsStore.snapshot = .zero
            renderer.clearTrailHistory()
            renderer.clearSampleHistory()
            setStatusMessage("\(replacement.displayName) active.")
        } catch {
            setStatusMessage("Could not switch RVM quality: \(error.localizedDescription)")
        }
    }

    func addEffect(_ effect: EffectKind) {
        guard !activeEffects.contains(effect) else { return }
        if effect.isVideoFill,
           let existingIndex = activeEffects.firstIndex(where: \.isVideoFill) {
            disabledEffects.remove(activeEffects[existingIndex])
            effectBlendModes.removeValue(forKey: activeEffects[existingIndex])
            activeEffects[existingIndex] = effect
            renderer.clearTrailHistory()
            return
        }
        if effect == .lines,
           let trailIndex = activeEffects.firstIndex(of: .historicalTrail) {
            // Generated geometry is most useful as input to an existing trail.
            activeEffects.insert(effect, at: trailIndex)
        } else {
            activeEffects.append(effect)
        }
        disabledEffects.remove(effect)
        if effect == .lines { renderer.clearTrailHistory() }
        if effect.isVideoFill { renderer.clearTrailHistory() }
    }

    func randomizeEffects() {
        guard !isApplyingPreset else { return }
        isApplyingPreset = true
        defer {
            isApplyingPreset = false
            syncEffects()
            renderer.clearTrailHistory()
            renderer.clearSampleHistory()
        }
        // Clear first so stateful effects such as trails and particles cannot carry
        // output from the previous stack into the randomized result.
        activeEffects = []
        disabledEffects = []
        effectBlendModes = [:]
        // A randomized stack opens fully expanded so its new controls are visible.
        collapsedEffects = []

        gradientStyle = GradientStyle.allCases.randomElement() ?? .neon
        gradientOpacity = .random(in: 0...1)
        gradientAngleDegrees = .random(in: -180...180)

        cloneCount = .random(in: 1...16)
        cloneRotationDegrees = .random(in: -15...15)
        cloneScalePercent = .random(in: -8...8)
        cloneTranslationXPercent = .random(in: -5...5)
        cloneTranslationYPercent = .random(in: -5...5)
        cloneOpacity = .random(in: 0...1)
        cloneDecay = .random(in: 0.35...1)
        trailLifetime = .random(in: 0.5...6)

        liquidStrength = .random(in: 0...8)
        liquidScale = .random(in: 1...12)
        liquidSpeed = .random(in: 0...3)

        if let asset = videoAssets.randomElement() {
            selectedVideoAssetID = asset.id
        }
        videoOpacity = .random(in: 0...1)
        videoPlaybackRate = .random(in: 0.25...2)
        videoScale = .random(in: 0.5...3)
        videoFillTiming = VideoFillTiming.allCases.randomElement() ?? .live

        maxPeople = Int.random(in: 1...4)
        skeletonOpacity = .random(in: 0.1...1)
        skeletonConfidence = .random(in: 0.1...0.9)
        linesOpacity = .random(in: 0.1...1)
        linesConfidence = .random(in: 0.1...0.9)
        linesConnections = .random(in: 1...6)
        linesThickness = .random(in: 1...16)
        linesGeometryOnly = Bool.random()
        sampleLines = []
        sampleRoot = Int.random(in: 0..<12)
        sampleScale = SampleScale.allCases.randomElement() ?? .chromatic
        sampleTension = .random(in: 0...1)
        sampleTriggerThreshold = .random(in: 0.05...0.6)
        sampleShowNotes = Bool.random()
        sampleQuantize = Bool.random()
        sampleMasterVolume = .random(in: 0.4...1)
        sampleTransposeMode = SampleTransposeMode.allCases.randomElement() ?? .diatonic
        sampleDirection = SampleDirection.allCases.randomElement() ?? .both
        sampleSpeed = .random(in: 20...600)
        sampleCount = .random(in: 12...512)
        sampleThickness = .random(in: 1...24)
        sampleOpacity = .random(in: 0...1)
        sampleFade = .random(in: 0...4)

        particleRate = .random(in: 5...160)
        particleLifetime = .random(in: 0.2...10)
        particleSizeScale = .random(in: 0...16)
        particleColorSource = ParticleColorSource.allCases.randomElement() ?? .liveBelow
        particleMotionSize = .random(in: 0...5)
        particleSpeed = .random(in: 0...3)
        particleSpreadDegrees = .random(in: 0...180)
        particleGravity = .random(in: -0.3...0.5)
        particleDrag = .random(in: 0...4)
        particleEndSize = .random(in: 0...2)
        particleShape = ParticleShape.allCases.randomElement() ?? .disc
        particleMomentum = .random(in: 0...1.5)
        particleSpawnSource = ParticleSpawnSource.allCases.randomElement() ?? .limbs
        particleBorderThreshold = .random(in: 0.1...0.9)

        let availableEffects = EffectKind.allCases.filter {
            !$0.isVideoFill || !videoAssets.isEmpty
        }
        let effectCount = Int.random(in: 1...availableEffects.count)
        activeEffects = Array(availableEffects.shuffled().prefix(effectCount))
        effectBlendModes = Dictionary(uniqueKeysWithValues: activeEffects.map {
            ($0, OverlayBlendMode.allCases.randomElement() ?? .normal)
        })
        if activeEffects.contains(.lineSampler) {
            var line = SampleLine(ax: 0.2, ay: 0.5, bx: 0.8, by: 0.5, midiChannel: 0)
            // A randomized look should actually show its sampler line.
            line.visibility = .random(in: 0.5...1)
            sampleLines = [line]
        }
        setStatusMessage("Randomized \(effectCount) effect\(effectCount == 1 ? "" : "s").")
    }

    /// Collapses or expands one effect's parameter panel in the stack.
    func setEffectCollapsed(_ effect: EffectKind, collapsed: Bool) {
        if collapsed {
            collapsedEffects.insert(effect)
        } else {
            collapsedEffects.remove(effect)
        }
    }

    func removeEffect(_ effect: EffectKind) {
        activeEffects.removeAll { $0 == effect }
        collapsedEffects.remove(effect)
        if effect == .lineSampler {
            // Stop notes and hosted instruments, but leave the shared audio
            // engine running; the reconfigure below stops any playing clips.
            lineMIDI.stop()
            instrumentHost.stop()
        }
        disabledEffects.remove(effect)
        effectBlendModes.removeValue(forKey: effect)
        if effect == .lines { renderer.clearTrailHistory() }
        if effect.isVideoFill { renderer.clearTrailHistory() }
    }

    func isEffectEnabled(_ effect: EffectKind) -> Bool {
        activeEffects.contains(effect) && !disabledEffects.contains(effect)
    }

    func blendMode(for effect: EffectKind) -> OverlayBlendMode {
        effectBlendModes[effect] ?? (effect == .clapExplosions ? .screen : .normal)
    }

    func setBlendMode(_ mode: OverlayBlendMode, for effect: EffectKind) {
        guard activeEffects.contains(effect) else { return }
        effectBlendModes[effect] = mode
        if effect == .historicalTrail || effect == .lines || effect.isVideoFill {
            renderer.clearTrailHistory()
        }
    }

    func setEffectEnabled(_ effect: EffectKind, enabled: Bool) {
        guard activeEffects.contains(effect), isEffectEnabled(effect) != enabled else { return }
        if enabled {
            disabledEffects.remove(effect)
        } else {
            disabledEffects.insert(effect)
        }
        if effect == .historicalTrail || effect == .lines || effect.isVideoFill {
            renderer.clearTrailHistory()
        }
        if effect == .lineSampler {
            lineMIDI.configure(lines: sampleLines, harmony: sampleHarmony, bpm: sampleBPM, threshold: sampleTriggerThreshold, quantize: sampleQuantize, transposeMode: sampleTransposeMode, portMode: sampleMIDIPortMode,
                               enabled: isSessionRunning && enabled)
            renderer.clearSampleHistory()
        }
    }

    func addSampleLine(from a: CGPoint, to b: CGPoint) {
        guard sampleLines.count < 16, hypot(a.x - b.x, a.y - b.y) > 0.01 else { return }
        let used = Set(sampleLines.map(\.midiChannel))
        guard let channel = (0..<16).first(where: { !used.contains($0) }) else { return }
        sampleLines.append(SampleLine(ax: a.x, ay: a.y, bx: b.x, by: b.y,
                                      midiChannel: channel, copying: sampleLines.last))
    }

    func moveSampleEndpoint(id: UUID, isStart: Bool, to point: CGPoint) {
        guard let index = sampleLines.firstIndex(where: { $0.id == id }) else { return }
        if isStart {
            sampleLines[index].ax = point.x
            sampleLines[index].ay = point.y
        } else {
            sampleLines[index].bx = point.x
            sampleLines[index].by = point.y
        }
    }

    func deleteSampleLine(id: UUID) {
        sampleLines.removeAll { $0.id == id }
    }

    /// Assigns a line's MIDI channel. Channels may be shared: several lines can
    /// send to the same channel (and thus the same host instrument/track). The
    /// MIDI layer keeps a shared pitch sounding until its last line releases it.
    func setSampleChannel(id: UUID, channel: Int) {
        let updated = SampleLine.assigningChannel(channel, to: id, in: sampleLines)
        guard updated != sampleLines else { return }
        sampleLines = updated
    }

    /// Master on/off for one line. A disabled line stops sending notes, CC, and
    /// clip triggers; re-enabling restarts its clips on the next bar.
    func setSampleEnabled(id: UUID, enabled: Bool) {
        guard let index = sampleLines.firstIndex(where: { $0.id == id }),
              sampleLines[index].isEnabled != enabled else { return }
        sampleLines[index].isEnabled = enabled
    }

    /// Switches a line between a MIDI instrument, an audio clip, and a hosted
    /// Vital synth. A hosted instrument drives the same note pipeline as MIDI, so
    /// note generation is forced on for it; clip destinations clear the MIDI
    /// roles so the row cannot show a stale Lead/Modulation state.
    func setSampleDestination(id: UUID, destination: SampleLineDestination) {
        guard let index = sampleLines.firstIndex(where: { $0.id == id }),
              sampleLines[index].destination != destination else { return }
        sampleLines[index].destination = destination
        switch destination {
        case .midi:
            break
        case .vital:
            sampleLines[index].midiEnabled = true
        case .loop, .oneShot:
            sampleLines[index].midiEnabled = false
            sampleLines[index].isLead = false
            sampleLines[index].isModulationSource = false
        }
    }

    // MARK: - Hosted Vital instrument

    /// Opens the hosted Vital editor in a separate window for a line's slot.
    func openVitalEditor(id: UUID) {
        if let window = vitalWindows[id] {
            window.makeKeyAndOrderFront(nil)
            return
        }
        Task { @MainActor in
            guard let viewController = await instrumentHost.requestEditor(forLine: id) else {
                setStatusMessage("Vital is still loading. Try again in a moment.")
                return
            }
            let window = NSWindow(contentViewController: viewController)
            window.title = "Vital"
            window.setContentSize(NSSize(width: 960, height: 640))
            window.isReleasedWhenClosed = false
            window.center()
            window.makeKeyAndOrderFront(nil)
            vitalWindows[id] = window
        }
    }

    /// Captures the live sound from a line's Vital slot into a sidecar and stores
    /// the reference on the line so the preset can restore it.
    func captureVitalSound(id: UUID) {
        guard let line = sampleLines.first(where: { $0.id == id }) else { return }
        let name = promptForSoundName(suggested: line.instrument?.name ?? "Vital Sound")
        Task { @MainActor in
            guard let reference = await instrumentHost.captureState(forLine: id, name: name,
                                                                    replacing: line.instrument) else {
                setStatusMessage("Could not capture the Vital sound. Make sure Vital is loaded and try again.")
                return
            }
            if let index = sampleLines.firstIndex(where: { $0.id == id }) {
                sampleLines[index].instrument = reference
            }
            refreshVitalSounds()
            setStatusMessage("Captured “\(reference.name)”.")
        }
    }

    /// Assigns a previously captured sound (or nil) to a line. The slot reloads
    /// it on the next reconfigure.
    func setSampleInstrument(id: UUID, reference: AUStateReference?) {
        guard let index = sampleLines.firstIndex(where: { $0.id == id }) else { return }
        sampleLines[index].instrument = reference
    }

    private func refreshVitalSounds() {
        instrumentState.sounds = AUStateStore.catalog()
    }

    func clearVitalSound(id: UUID) {
        guard let index = sampleLines.firstIndex(where: { $0.id == id }) else { return }
        sampleLines[index].instrument = nil
    }

    private func promptForSoundName(suggested: String) -> String {
        let alert = NSAlert()
        alert.messageText = "Name this Vital sound"
        alert.informativeText = "The captured state is saved with this name."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = suggested
        alert.accessoryView = field
        alert.addButton(withTitle: "Capture")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return suggested }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? suggested : name
    }

    /// Imports an audio file for a loop or one-shot line. The file is referenced
    /// in place (bookmark + path), not copied, so presets stay small; moving the
    /// preset to another machine requires re-importing its audio.
    func importAudioClip(id: UUID) {
        guard let index = sampleLines.firstIndex(where: { $0.id == id }) else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a WAV or AIFF loop or one-shot"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        sampleLines[index].clip = AudioClipReference(fileName: url.lastPathComponent,
                                                     path: url.path,
                                                     bookmark: AudioClipReference.bookmark(for: url))
    }

    func clearAudioClip(id: UUID) {
        guard let index = sampleLines.firstIndex(where: { $0.id == id }) else { return }
        sampleLines[index].clip = nil
    }

    func setClipSourceBPM(id: UUID, bpm: Double) {
        guard let index = sampleLines.firstIndex(where: { $0.id == id }),
              sampleLines[index].clip != nil else { return }
        sampleLines[index].clip?.sourceBPM = min(240, max(30, bpm))
    }

    func setClipBeats(id: UUID, beats: Double) {
        guard let index = sampleLines.firstIndex(where: { $0.id == id }),
              sampleLines[index].clip != nil else { return }
        sampleLines[index].clip?.beats = min(64, max(0.25, beats))
    }

    func setClipLevel(id: UUID, level: Double) {
        guard let index = sampleLines.firstIndex(where: { $0.id == id }),
              sampleLines[index].clip != nil else { return }
        sampleLines[index].clip?.level = min(1, max(0, level))
    }

    func setClipStartMuted(id: UUID, muted: Bool) {
        guard let index = sampleLines.firstIndex(where: { $0.id == id }),
              sampleLines[index].clip != nil else { return }
        sampleLines[index].clip?.startMuted = muted
    }

    /// Keeps every line's register inside MIDI's 0...127 range after the global
    /// root or scale changes.
    private func clampSampleOctaves() {
        let harmony = sampleHarmony
        let lastOffset = harmony.scale.offsets.last ?? 0
        var updated = sampleLines
        for index in updated.indices {
            // The top key sits a whole number of octaves above the base octave.
            let keys = harmony.resolvedKeyCount(updated[index].keyCount)
            let topOffset = harmony.topOctaveOffset(forKeys: keys)
            while updated[index].octave > -1,
                  (updated[index].octave + topOffset + 1) * 12 + harmony.root + lastOffset > 127 {
                updated[index].octave -= 1
            }
        }
        if updated != sampleLines { sampleLines = updated }
    }

    /// Sends one note on channel 1 at `testNoteVelocity` so a MIDI host's
    /// velocity response can be checked independently of pixel detection.
    func sendTestNote() {
        let pitch = sampleHarmony.pitches(octave: 4).first ?? 60
        let velocity = UInt8(min(127, max(1, Int(testNoteVelocity.rounded()))))
        lineMIDI.sendTestNote(pitch: pitch, velocity: velocity)
    }

    /// Marks one line as the lead, clearing any other. A lead that cannot sound
    /// is pointless, so enabling also turns its MIDI on.
    func setSampleLead(id: UUID, enabled: Bool) {
        guard let index = sampleLines.firstIndex(where: { $0.id == id }) else { return }
        var updated = sampleLines
        if enabled {
            for i in updated.indices {
                updated[i].isLead = updated[i].id == id
                // A modulation line is excluded from notes, so it cannot also be
                // the lead; making one the lead releases its modulation role.
                if updated[i].id == id { updated[i].isModulationSource = false }
            }
            updated[index].midiEnabled = true
        } else {
            updated[index].isLead = false
        }
        guard updated != sampleLines else { return }
        sampleLines = updated
    }

    /// Toggles one line's modulation role. Several lines can be modulation
    /// sources at once, each driving its own `modulationCC` on its own channel.
    ///
    /// The line's note settings (octave, keys, rhythm, channel, …) are left
    /// untouched; the MIDI layer already suppresses notes while the line is a
    /// modulation source, so turning the role back off restores it exactly as it
    /// was rather than leaving `midiEnabled` stuck off.
    func setSampleModulationSource(id: UUID, enabled: Bool) {
        let updated = SampleLine.settingModulation(enabled, for: id, in: sampleLines)
        guard updated != sampleLines else { return }
        sampleLines = updated
    }

    /// Sets a modulation line's CC number.
    func setSampleModulationCC(id: UUID, cc: Int) {
        guard let index = sampleLines.firstIndex(where: { $0.id == id }) else { return }
        let clamped = min(127, max(0, cc))
        guard sampleLines[index].modulationCC != clamped else { return }
        sampleLines[index].modulationCC = clamped
    }

    /// Sends one line's modulation CC at mid value so a host synth's MIDI learn
    /// can bind it without waiting for a lit line.
    func sendTestCC(id: UUID) {
        guard let line = sampleLines.first(where: { $0.id == id && $0.isModulationSource }) else { return }
        lineMIDI.sendTestModulation(channel: line.midiChannel, controller: line.modulationCC)
    }

    func moveEffect(_ effect: EffectKind, by offset: Int) {
        guard let source = activeEffects.firstIndex(of: effect) else { return }
        let destination = source + offset
        guard activeEffects.indices.contains(destination) else { return }
        activeEffects.swapAt(source, destination)
    }

    func selectPreset(id: UUID) {
        guard presets.contains(where: { $0.id == id }) else { return }
        selectedPresetID = id
        presetSelectionTask?.cancel()
        presetSelectionTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled,
                  let self,
                  let preset = self.presets.first(where: { $0.id == id }) else { return }
            self.apply(preset)
            self.presetName = preset.name
        }
    }

    func savePreset() {
        guard !isSavingPreset else { return }
        let trimmedName = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            setStatusMessage("Enter a preset name first.")
            return
        }
        // Lock immediately so a second click cannot start a concurrent save while
        // the Vital recapture below is awaiting.
        isSavingPreset = true
        // Recapture the live Vital sounds first so the saved preset reflects what
        // is actually loaded rather than a stale capture.
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.recaptureVitalSounds()
            self.continueSavingPreset(name: trimmedName)
        }
    }

    /// Refreshes every Vital line's captured sound from its live slot. A line
    /// whose slot is not loaded (Vital unavailable or still loading) keeps its
    /// existing reference.
    private func recaptureVitalSounds() async {
        for (index, line) in sampleLines.enumerated() where line.destination == .vital {
            let name = line.instrument?.name ?? "Line \(index + 1) Vital"
            guard let reference = await instrumentHost.captureState(forLine: line.id, name: name,
                                                                    replacing: line.instrument) else {
                continue
            }
            if let current = sampleLines.firstIndex(where: { $0.id == line.id }) {
                sampleLines[current].instrument = reference
            }
        }
        refreshVitalSounds()
    }

    private func continueSavingPreset(name: String) {
        applyEffectsToRenderer()
        var preset = currentPreset(name: name)
        if let index = presets.firstIndex(where: {
            $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }) {
            preset.id = presets[index].id
        }
        let captureID = UUID()
        pendingPresetCaptureID = captureID
        isSavingPreset = true
        setStatusMessage("Capturing preview for “\(preset.name)”…")
        renderer.captureNextFrame(id: captureID) { [weak self] image in
            Task { @MainActor [weak self] in
                self?.finishSavingPreset(preset, captureID: captureID, image: image)
            }
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, self.pendingPresetCaptureID == captureID else { return }
            self.renderer.cancelFrameCapture(id: captureID)
            self.pendingPresetCaptureID = nil
            self.isSavingPreset = false
            self.setStatusMessage("No output frame was available. Preset was not saved.")
        }
    }

    /// Composites the SwiftUI sampler overlay onto a captured frame, then
    /// encodes JPEG. The overlay is a layer above the Metal view rather than
    /// part of the drawable, so it has to be drawn here or it never reaches the
    /// saved preview.
    private func thumbnailJPEG(from image: CGImage) -> Data? {
        let size = CGSize(width: image.width, height: image.height)
        let overlay = SampleLineOverlay(
            lines: sampleLines,
            harmony: sampleHarmony,
            showNotes: sampleShowNotes,
            transposeMode: sampleTransposeMode,
            visible: isEffectEnabled(.lineSampler),
            state: samplerState
        )
        .frame(width: size.width, height: size.height)

        let imageRenderer = ImageRenderer(content: overlay)
        imageRenderer.scale = 1
        imageRenderer.isOpaque = false

        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(origin: .zero, size: size))
        if let overlayImage = imageRenderer.cgImage {
            context.draw(overlayImage, in: CGRect(origin: .zero, size: size))
        }
        guard let composited = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: composited).representation(
            using: .jpeg, properties: [.compressionFactor: 0.82]
        )
    }

    private func finishSavingPreset(_ capturedPreset: EffectPreset, captureID: UUID, image: CGImage?) {
        guard pendingPresetCaptureID == captureID else { return }
        pendingPresetCaptureID = nil
        isSavingPreset = false
        guard let image, let imageData = thumbnailJPEG(from: image) else {
            setStatusMessage("Could not capture the output frame. Preset was not saved.")
            return
        }
        do {
            try FileManager.default.createDirectory(at: Self.thumbnailDirectory,
                                                    withIntermediateDirectories: true)
            let fileName = "\(UUID().uuidString).jpg"
            try imageData.write(to: Self.thumbnailDirectory.appendingPathComponent(fileName), options: .atomic)
            var preset = capturedPreset
            preset.thumbnailFileName = fileName
            if let index = presets.firstIndex(where: { $0.id == preset.id }) {
                let oldFileName = presets[index].thumbnailFileName
                presets[index] = preset
                if let oldFileName {
                    try? FileManager.default.removeItem(at: Self.thumbnailDirectory.appendingPathComponent(oldFileName))
                }
            } else {
                presets.append(preset)
            }
            selectedPresetID = preset.id
            presetName = preset.name
            persistPresets()
            setStatusMessage("Preset “\(preset.name)” saved.")
        } catch {
            setStatusMessage("Could not save preset preview: \(error.localizedDescription)")
        }
    }

    func deleteSelectedPreset() {
        guard presets.count > 1,
              let selectedPresetID,
              let index = presets.firstIndex(where: { $0.id == selectedPresetID }) else { return }
        let deletedName = presets[index].name
        let deletedPreset = presets.remove(at: index)
        if let fileName = deletedPreset.thumbnailFileName {
            try? FileManager.default.removeItem(at: Self.thumbnailDirectory.appendingPathComponent(fileName))
        }
        persistPresets()
        let replacement = presets[min(index, presets.count - 1)]
        apply(replacement)
        self.selectedPresetID = replacement.id
        presetName = replacement.name
        renderer.clearTrailHistory()
        setStatusMessage("Preset “\(deletedName)” deleted.")
    }

    /// Publishes a status message only when it actually changes. `@Published`
    /// fires on every assignment, so repeated identical messages (for example
    /// AVFoundation's per-frame "dropped a late camera frame") would otherwise
    /// rebuild the whole control panel once per dropped frame.
    private func setStatusMessage(_ message: String?) {
        guard statusMessage != message else { return }
        statusMessage = message
    }

    private func syncEffects() {
        guard !isApplyingPreset else { return }
        // SwiftUI sliders can publish far faster than the preview refreshes. Coalesce
        // those changes into one renderer update per display-sized interval instead
        // of making the main actor rewrite the complete effect state for every event.
        guard effectSyncTask == nil else { return }
        effectSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(33))
            guard let self else { return }
            self.effectSyncTask = nil
            guard !Task.isCancelled, !self.isApplyingPreset else { return }
            self.applyEffectsToRenderer()
        }
    }

    private func applyEffectsToRenderer() {
        let enabledEffects = activeEffects.filter { !disabledEffects.contains($0) }
        let gradientEnabled = enabledEffects.contains(.gradientOverlay)
        let clonesEnabled = enabledEffects.contains(.historicalTrail)
        renderer.gradientEnabled = gradientEnabled
        renderer.gradientStyle = gradientStyle
        renderer.gradientOpacity = Float(gradientOpacity)
        renderer.gradientAngleDegrees = Float(gradientAngleDegrees)
        renderer.clonesEnabled = clonesEnabled
        renderer.cloneCount = cloneCount
        renderer.cloneRotationDegrees = Float(cloneRotationDegrees)
        renderer.cloneScaleStep = Float(cloneScalePercent / 100)
        renderer.cloneTranslation = SIMD2(
            Float(cloneTranslationXPercent / 100),
            Float(cloneTranslationYPercent / 100)
        )
        renderer.cloneOpacity = Float(cloneOpacity)
        renderer.cloneDecay = Float(cloneDecay)
        renderer.trailLifetime = trailLifetime
        renderer.trailBlendMode = blendMode(for: .historicalTrail)
        renderer.liquidEnabled = enabledEffects.contains(.liquidDistortion)
        renderer.liquidBlendMode = blendMode(for: .liquidDistortion)
        renderer.liquidStrength = Float(liquidStrength / 100)
        renderer.liquidScale = Float(liquidScale)
        renderer.liquidSpeed = Float(liquidSpeed)
        renderer.videoFillSource = selectedVideoAssetID
        renderer.videoBlendMode = blendMode(for: .liveVideoFill)
        renderer.gradientBlendMode = blendMode(for: .gradientOverlay)
        renderer.videoFillEnabled = enabledEffects.contains(where: \.isVideoFill)
            && !selectedVideoAssetID.isEmpty
        renderer.videoFillOpacity = Float(videoOpacity)
        renderer.videoFillScale = Float(videoScale)
        renderer.videoPlaybackRate = Float(videoPlaybackRate)
        renderer.videoFillTiming = videoFillTiming
        renderer.skeletonEnabled = enabledEffects.contains(.skeleton)
        renderer.skeletonBlendMode = blendMode(for: .skeleton)
        renderer.skeletonOpacity = Float(skeletonOpacity)
        renderer.skeletonConfidence = Float(skeletonConfidence)
        renderer.linesEnabled = enabledEffects.contains(.lines)
        renderer.linesOpacity = Float(linesOpacity)
        renderer.linesConfidence = Float(linesConfidence)
        renderer.linesConnections = linesConnections
        renderer.linesThickness = Float(linesThickness)
        renderer.linesBlendMode = blendMode(for: .lines)
        renderer.linesGeometryOnly = linesGeometryOnly
        renderer.sampleLines = sampleLines
        renderer.sampleHarmony = sampleHarmony
        lineMIDI.configure(lines: sampleLines, harmony: sampleHarmony, bpm: sampleBPM, threshold: sampleTriggerThreshold, quantize: sampleQuantize, transposeMode: sampleTransposeMode, portMode: sampleMIDIPortMode,
                           enabled: isSessionRunning && enabledEffects.contains(.lineSampler))
        clipAudio.configure(lines: sampleLines,
                            enabled: isSessionRunning && enabledEffects.contains(.lineSampler),
                            sessionActive: isSessionRunning,
                            quantize: sampleQuantize, masterVolume: sampleMasterVolume)
        instrumentHost.configure(lines: sampleLines,
                                 enabled: isSessionRunning && enabledEffects.contains(.lineSampler))
        renderer.sampleDirection = sampleDirection
        renderer.sampleSpeed = Float(sampleSpeed)
        renderer.sampleCount = sampleCount
        renderer.sampleThickness = Float(sampleThickness)
        renderer.sampleOpacity = Float(sampleOpacity)
        renderer.sampleFade = Float(sampleFade)
        renderer.sampleBlendMode = blendMode(for: .lineSampler)
        renderer.lineSamplerEnabled = enabledEffects.contains(.lineSampler)
        renderer.particlesEnabled = enabledEffects.contains(.particles)
        renderer.particleBlendMode = blendMode(for: .particles)
        renderer.particleRate = Float(particleRate)
        renderer.particleLifetime = Float(particleLifetime)
        renderer.particleSizeScale = Float(particleSizeScale)
        renderer.particleColorSource = particleColorSource
        renderer.particleMotionSize = Float(particleMotionSize)
        renderer.particleSpeed = Float(particleSpeed)
        renderer.particleSpreadDegrees = Float(particleSpreadDegrees)
        renderer.particleGravity = Float(particleGravity)
        renderer.particleDrag = Float(particleDrag)
        renderer.particleEndSize = Float(particleEndSize)
        renderer.particleShape = particleShape
        renderer.particleMomentum = Float(particleMomentum)
        renderer.particleSpawnSource = particleSpawnSource
        renderer.particleBorderThreshold = Float(particleBorderThreshold)
        renderer.clapExplosionsEnabled = enabledEffects.contains(.clapExplosions)
        renderer.clapExplosionSize = Float(clapExplosionSize)
        renderer.clapExplosionOpacity = Float(clapExplosionOpacity)
        renderer.clapExplosionBlendMode = blendMode(for: .clapExplosions)
        renderer.effectOrder = enabledEffects
        if !clonesEnabled { renderer.clearTrailHistory() }
    }

    private func currentPreset(name: String) -> EffectPreset {
        EffectPreset(
            id: UUID(), name: name, effects: activeEffects,
            disabledEffects: disabledEffects,
            effectBlendModes: effectBlendModes,
            gradientStyle: gradientStyle,
            gradientOpacity: gradientOpacity,
            gradientAngleDegrees: gradientAngleDegrees,
            cloneCount: cloneCount,
            cloneRotationDegrees: cloneRotationDegrees,
            cloneScalePercent: cloneScalePercent,
            cloneTranslationXPercent: cloneTranslationXPercent,
            cloneTranslationYPercent: cloneTranslationYPercent,
            cloneOpacity: cloneOpacity,
            cloneDecay: cloneDecay,
            trailSnapshotInterval: 0.05,
            trailLifetime: trailLifetime,
            trailBlendMode: TrailBlendMode(rawValue: Int(blendMode(for: .historicalTrail).rawValue)) ?? .normal,
            liquidStrength: liquidStrength,
            liquidScale: liquidScale,
            liquidSpeed: liquidSpeed,
            videoOpacity: videoOpacity,
            videoPlaybackRate: videoPlaybackRate,
            videoScale: videoScale,
            videoFillTiming: videoFillTiming,
            videoAssetID: selectedVideoAssetID,
            skeletonOpacity: skeletonOpacity,
            skeletonConfidence: skeletonConfidence,
            linesOpacity: linesOpacity,
            linesConfidence: linesConfidence,
            linesConnections: linesConnections,
            linesGeometryOnly: linesGeometryOnly,
            linesThickness: linesThickness,
            linesBlendMode: blendMode(for: .lines),
            sampleLines: sampleLines,
            sampleHarmony: sampleHarmony,
            sampleTriggerThreshold: sampleTriggerThreshold,
            sampleShowNotes: sampleShowNotes,
            sampleQuantize: sampleQuantize,
            sampleMasterVolume: sampleMasterVolume,
            sampleTransposeMode: sampleTransposeMode,
            sampleMIDIPortMode: sampleMIDIPortMode,
            sampleBPM: sampleBPM,
            sampleDirection: sampleDirection,
            sampleSpeed: sampleSpeed,
            sampleCount: sampleCount,
            sampleLifetime: Double(sampleCount) / 60,
            sampleThickness: sampleThickness,
            sampleOpacity: sampleOpacity,
            sampleFade: sampleFade,
            sampleBlendMode: blendMode(for: .lineSampler),
            particleRate: particleRate,
            particleLifetime: particleLifetime,
            particleSize: particleSizeScale * 6,
            particleSizeScale: particleSizeScale,
            particleColorSource: particleColorSource,
            particleMotionSize: particleMotionSize,
            particleSpeed: particleSpeed,
            particleSpreadDegrees: particleSpreadDegrees,
            particleGravity: particleGravity,
            particleDrag: particleDrag,
            particleEndSize: particleEndSize,
            particleShape: particleShape,
            particleMomentum: particleMomentum,
            particleSpawnSource: particleSpawnSource,
            particleBorderThreshold: particleBorderThreshold,
            clapExplosionSize: clapExplosionSize,
            clapExplosionOpacity: clapExplosionOpacity,
            clapExplosionBlendMode: blendMode(for: .clapExplosions),
            maxPeople: maxPeople,
            collapsedEffects: collapsedEffects
        )
    }

    private func apply(_ preset: EffectPreset) {
        guard !isApplyingPreset else { return }
        // Stop the MIDI note clock, but leave the shared audio engine running:
        // hosted Vital instruments live in it and it must survive a preset
        // switch. The reconfigure below releases the old preset's clips/slots.
        lineMIDI.stop()
        isApplyingPreset = true
        defer {
            isApplyingPreset = false
            syncEffects()
            renderer.clearTrailHistory()
            renderer.clearSampleHistory()
        }
        let usedLegacyFlowersEffect = preset.effects.contains(.flowers)
        let requestedVideoID = usedLegacyFlowersEffect
            ? videoAssets.first(where: { $0.name == "Flowers" })?.id
            : preset.videoAssetID
        selectedVideoAssetID = videoAssets.contains(where: { $0.id == requestedVideoID })
            ? (requestedVideoID ?? defaultVideoAssetID)
            : defaultVideoAssetID
        activeEffects = preset.effects.reduce(into: []) { effects, effect in
            let normalized: EffectKind = effect == .flowers ? .liveVideoFill : effect
            if !effects.contains(normalized) { effects.append(normalized) }
        }
        disabledEffects = Set((preset.disabledEffects ?? []).map {
            $0 == .flowers ? .liveVideoFill : $0
        }).intersection(activeEffects)
        collapsedEffects = Set((preset.collapsedEffects ?? []).map {
            $0 == .flowers ? .liveVideoFill : $0
        }).intersection(activeEffects)
        if let savedModes = preset.effectBlendModes {
            effectBlendModes = savedModes.reduce(into: [:]) { modes, entry in
                let effect = entry.key == .flowers ? .liveVideoFill : entry.key
                if activeEffects.contains(effect) { modes[effect] = entry.value }
            }
        } else {
            effectBlendModes = [
                .historicalTrail: OverlayBlendMode(rawValue: UInt32(preset.trailBlendMode.rawValue)) ?? .normal,
                .lines: preset.linesBlendMode ?? .normal,
                .lineSampler: preset.sampleBlendMode ?? .normal,
                .clapExplosions: preset.clapExplosionBlendMode ?? .screen
            ]
        }
        gradientStyle = preset.gradientStyle
        gradientOpacity = preset.gradientOpacity
        gradientAngleDegrees = preset.gradientAngleDegrees
        cloneCount = preset.cloneCount
        cloneRotationDegrees = preset.cloneRotationDegrees
        cloneScalePercent = preset.cloneScalePercent
        cloneTranslationXPercent = preset.cloneTranslationXPercent
        cloneTranslationYPercent = preset.cloneTranslationYPercent
        cloneOpacity = preset.cloneOpacity
        cloneDecay = preset.cloneDecay
        trailLifetime = preset.trailLifetime
        liquidStrength = preset.liquidStrength
        liquidScale = preset.liquidScale
        liquidSpeed = preset.liquidSpeed
        videoOpacity = preset.videoOpacity ?? 1.0
        videoPlaybackRate = preset.videoPlaybackRate ?? 1.0
        videoScale = preset.videoScale ?? 1.0
        videoFillTiming = preset.videoFillTiming ?? .live
        skeletonOpacity = preset.skeletonOpacity ?? 1.0
        skeletonConfidence = preset.skeletonConfidence ?? 0.35
        linesOpacity = preset.linesOpacity ?? 0.65
        linesConfidence = preset.linesConfidence ?? 0.35
        linesConnections = preset.linesConnections ?? 3
        linesGeometryOnly = preset.linesGeometryOnly ?? true
        linesThickness = preset.linesThickness ?? 2.0
        // Older presets stored root/scale per line. They reset to the global
        // defaults (C / Chromatic) rather than guessing from the first line.
        let savedHarmony = preset.sampleHarmony ?? SampleHarmony()
        sampleRoot = min(11, max(0, savedHarmony.root))
        sampleScale = savedHarmony.scale
        sampleTension = min(1, max(0, savedHarmony.tension))
        sampleTriggerThreshold = min(1, max(0.01, preset.sampleTriggerThreshold ?? 0.2))
        // Older presets kept note labels per line; promote them to the global flag.
        sampleShowNotes = preset.sampleShowNotes
            ?? (preset.sampleLines?.contains(where: \.showNotes) ?? false)
        sampleQuantize = preset.sampleQuantize ?? true
        sampleMasterVolume = min(1, max(0, preset.sampleMasterVolume ?? 0.8))
        sampleTransposeMode = preset.sampleTransposeMode ?? .diatonic
        sampleMIDIPortMode = preset.sampleMIDIPortMode ?? .perLine
        sampleLines = SampleLine.withStableChannels(preset.sampleLines ?? [])
        clampSampleOctaves()
        let savedBPM = preset.sampleBPM ?? 120
        sampleBPM = savedBPM.isFinite ? min(240, max(30, savedBPM)) : 120
        sampleDirection = preset.sampleDirection ?? .both
        sampleSpeed = preset.sampleSpeed ?? 180
        sampleCount = min(512, max(1, preset.sampleCount
            ?? Int(((preset.sampleLifetime ?? 3) * 60).rounded())))
        sampleThickness = preset.sampleThickness ?? 3
        sampleOpacity = preset.sampleOpacity ?? 0.8
        sampleFade = preset.sampleFade ?? 1
        particleRate = preset.particleRate ?? 60.0
        particleLifetime = preset.particleLifetime ?? 1.2
        particleSizeScale = min(16, max(0, preset.particleSizeScale ?? (preset.particleSize ?? 6.0) / 6))
        particleColorSource = preset.particleColorSource ?? .liveBelow
        particleMotionSize = preset.particleMotionSize ?? 2.5
        particleSpeed = preset.particleSpeed ?? 1.0
        particleSpreadDegrees = preset.particleSpreadDegrees ?? 30.0
        particleGravity = preset.particleGravity ?? 0.08
        particleDrag = preset.particleDrag ?? 0.0
        particleEndSize = preset.particleEndSize ?? 0.55
        particleShape = preset.particleShape ?? .disc
        particleMomentum = preset.particleMomentum ?? 0.65
        particleSpawnSource = preset.particleSpawnSource ?? .limbs
        particleBorderThreshold = preset.particleBorderThreshold ?? 0.5
        clapExplosionSize = preset.clapExplosionSize ?? 0.5
        clapExplosionOpacity = preset.clapExplosionOpacity ?? 1.0
        maxPeople = min(8, max(1, preset.maxPeople ?? 1))
    }

    private var defaultVideoAssetID: String {
        videoAssets.first(where: { $0.id.caseInsensitiveCompare("explosions-2min.m4v") == .orderedSame })?.id
            ?? videoAssets.first?.id
            ?? ""
    }

    private static func discoverVideoAssets() -> [VideoAsset] {
        guard let resourceURL = Bundle.main.resourceURL,
              let urls = try? FileManager.default.contentsOfDirectory(
                at: resourceURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else { return [] }
        let supportedExtensions = Set(["m4v", "mov", "mp4"])
        return urls.compactMap { url -> VideoAsset? in
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            let filename = url.lastPathComponent
            let words = url.deletingPathExtension().lastPathComponent
                .split(whereSeparator: { $0 == "-" || $0 == "_" })
                .filter { $0.lowercased() != "2min" }
                .map { $0.capitalized }
            return VideoAsset(id: filename, name: words.joined(separator: " "), url: url)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func persistPresets() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: Self.presetsKey)
    }

    private func persistSelectedPresetID() {
        if let selectedPresetID {
            UserDefaults.standard.set(selectedPresetID.uuidString, forKey: Self.selectedPresetKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.selectedPresetKey)
        }
    }

    /// Bundle identifier used before the app was renamed, and the key names used
    /// before that. Kept only so the first launch of the final build can adopt
    /// the old saved state.
    private static let legacyBundleIdentifier = "local.dancefx.prototype"
    private static let legacyMigrationKey = "kineticcanvas.migratedLegacy.v3"
    private static let legacyKeyRenames: [String: String] = [
        "dancefx.effectPresets.v1": presetsKey,
        "dancefx.selectedPresetID.v1": selectedPresetKey,
        "dancefx.controlPanel.transparent.v1": controlPanelTransparentKey
    ]

    /// One-time adoption of pre-rename state. Presets, the selected preset, and
    /// window settings may live under the old key names in the current domain
    /// (an earlier intermediate build) or in the old bundle-identifier domain
    /// (a direct upgrade). Saved thumbnails live in the old Application Support
    /// folder. All move on the first launch of the final build. The camera
    /// permission cannot be migrated (macOS ties TCC grants to the identifier),
    /// so it is re-prompted once.
    private static func migrateLegacyStateIfNeeded() {
        migrateLegacyDefaults()
        migrateLegacyThumbnails()
    }

    private static func migrateLegacyDefaults() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: legacyMigrationKey) else { return }
        // Current domain first (intermediate build), then the old bundle domain.
        var sources = [defaults.dictionaryRepresentation()]
        if let legacy = UserDefaults(suiteName: legacyBundleIdentifier) {
            sources.append(legacy.dictionaryRepresentation())
        }
        func legacyValue(for key: String) -> Any? {
            for source in sources where source[key] != nil { return source[key] }
            return nil
        }

        // Presets and settings adopt their new key names.
        for (oldKey, newKey) in legacyKeyRenames where defaults.object(forKey: newKey) == nil {
            if let value = legacyValue(for: oldKey) { defaults.set(value, forKey: newKey) }
        }
        // Window frames: rename every `NSWindow Frame` key that still carries the
        // old app name, which covers the SwiftUI main window plus the control
        // panel and library autosave names.
        var frameRenames: [(old: String, new: String)] = []
        for source in sources {
            for key in source.keys where key.hasPrefix("NSWindow Frame ") && key.contains("DanceFX") {
                frameRenames.append((key, key.replacingOccurrences(of: "DanceFX", with: "KineticCanvas")))
            }
        }
        for rename in frameRenames where defaults.object(forKey: rename.new) == nil {
            if let value = legacyValue(for: rename.old) { defaults.set(value, forKey: rename.new) }
        }
        // Drop the superseded keys from the current domain.
        for (oldKey, _) in legacyKeyRenames { defaults.removeObject(forKey: oldKey) }
        for rename in frameRenames { defaults.removeObject(forKey: rename.old) }
        // Sweep any other legacy-named key (for example an earlier migration
        // marker) so nothing branded with the old name survives.
        for key in defaults.dictionaryRepresentation().keys where key.contains("DanceFX") {
            defaults.removeObject(forKey: key)
        }

        defaults.set(true, forKey: legacyMigrationKey)
    }

    private static func migrateLegacyThumbnails() {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let old = base.appendingPathComponent("DanceFX/Preset Thumbnails", isDirectory: true)
        let new = base.appendingPathComponent("Kinetic Canvas/Preset Thumbnails", isDirectory: true)
        guard manager.fileExists(atPath: old.path), !manager.fileExists(atPath: new.path) else { return }
        try? manager.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? manager.moveItem(at: old, to: new)
    }

    private static var thumbnailDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kinetic Canvas/Preset Thumbnails", isDirectory: true)
    }

    func thumbnailURL(for preset: EffectPreset) -> URL? {
        preset.thumbnailFileName.map { Self.thumbnailDirectory.appendingPathComponent($0) }
    }

    private static func loadStoredPresets() -> [EffectPreset] {
        guard let data = UserDefaults.standard.data(forKey: presetsKey),
              let presets = try? JSONDecoder().decode([EffectPreset].self, from: data) else { return [] }
        return presets
    }

    private static let defaultPreset = EffectPreset(
        id: UUID(), name: "Default", effects: [.gradientOverlay, .historicalTrail],
        gradientStyle: .neon, gradientOpacity: 0.72, gradientAngleDegrees: 83,
        cloneCount: 15, cloneRotationDegrees: 3, cloneScalePercent: -1.5,
        cloneTranslationXPercent: 1.5, cloneTranslationYPercent: 0.4,
        cloneOpacity: 0.50, cloneDecay: 0.96, trailSnapshotInterval: 0.05,
        trailLifetime: 3.0, trailBlendMode: .normal,
        liquidStrength: 2.5, liquidScale: 5.0, liquidSpeed: 1.0,
        videoOpacity: 1.0, videoPlaybackRate: 1.0, videoScale: 1.0,
        videoFillTiming: .live, videoAssetID: "explosions-2min.m4v",
        skeletonOpacity: 1.0, skeletonConfidence: 0.35,
        linesOpacity: 0.65, linesConfidence: 0.35, linesConnections: 3,
        linesGeometryOnly: true,
        linesThickness: 2.0, linesBlendMode: .normal,
        sampleLines: [], sampleHarmony: SampleHarmony(),
        sampleTriggerThreshold: 0.2, sampleShowNotes: false, sampleQuantize: true,
        sampleMasterVolume: 0.8, sampleTransposeMode: .diatonic,
        sampleMIDIPortMode: .perLine,
        sampleDirection: .both, sampleSpeed: 180,
        sampleCount: 180, sampleLifetime: 3, sampleThickness: 3, sampleOpacity: 0.8,
        sampleFade: 1, sampleBlendMode: .normal,
        particleRate: 60.0, particleLifetime: 1.2, particleSize: 6.0,
        particleSizeScale: 1.0, particleColorSource: .liveBelow,
        particleMotionSize: 2.5, particleSpeed: 1.0, particleSpreadDegrees: 30.0,
        particleGravity: 0.08, particleDrag: 0.0, particleEndSize: 0.55,
        particleShape: .disc, particleMomentum: 0.65,
        particleSpawnSource: .limbs, particleBorderThreshold: 0.5,
        clapExplosionSize: 0.5, clapExplosionOpacity: 1.0,
        clapExplosionBlendMode: .screen
    )

    private func accept(frame: CameraFrame) {
        monitor.recordCapture()
        poseFrameCounter &+= 1
        let limbParticlesEnabled = isEffectEnabled(.particles) && particleSpawnSource == .limbs
        let poseEffectsEnabled = isEffectEnabled(.skeleton)
            || isEffectEnabled(.lines)
            || limbParticlesEnabled
            || isEffectEnabled(.clapExplosions)
        let detectHands = limbParticlesEnabled || isEffectEnabled(.clapExplosions)
        if poseEffectsEnabled, !poseInferenceInProgress, poseFrameCounter.isMultiple(of: 2) {
            poseInferenceInProgress = true
            let detector = poseDetector
            let renderer = renderer
            let maxPeople = maxPeople
            poseQueue.async { [weak self] in
                do {
                    renderer.updatePose(try detector.detect(pixelBuffer: frame.pixelBuffer,
                                                            includeHands: detectHands,
                                                            maxPeople: maxPeople))
                } catch {
                    renderer.updatePose([])
                }
                Task { @MainActor in self?.poseInferenceInProgress = false }
            }
        }
        guard !inferenceInProgress else {
            monitor.recordDroppedFrame()
            return
        }

        inferenceInProgress = true
        let engine = self.engine
        let monitor = self.monitor
        let renderer = self.renderer

        inferenceQueue.async { [weak self] in
            let started = CACurrentMediaTime()
            do {
                let result = try engine.process(pixelBuffer: frame.pixelBuffer, timestamp: frame.timestamp)
                let inferenceMS = (CACurrentMediaTime() - started) * 1_000
                monitor.recordProcessed(inferenceMS: inferenceMS)
                renderer.submit(result: result) { renderMS in
                    monitor.recordRendered(renderMS: renderMS, captureHostTime: frame.hostTime)
                }
            } catch {
                Task { @MainActor in self?.setStatusMessage("Matting failed: \(error.localizedDescription)") }
            }
            Task { @MainActor in self?.inferenceInProgress = false }
        }
    }
}
