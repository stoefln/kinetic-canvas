import AVFoundation
import Combine
import Foundation

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
    @Published var sampleLines: [SampleLine] = [] { didSet { syncEffects() } }
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
    @Published private(set) var selectedPresetID: UUID?
    @Published var presetName = ""
    @Published private(set) var isSavingPreset = false
    @Published private(set) var metrics = PerformanceSnapshot.zero
    @Published private(set) var statusMessage: String?
    @Published private(set) var projectorStatus = "Preparing video output…"
    @Published private(set) var projectorConnected = false
    @Published var controlPanelTransparent = false {
        didSet {
            UserDefaults.standard.set(controlPanelTransparent, forKey: Self.controlPanelTransparentKey)
        }
    }

    let renderer: MetalRenderer
    private var projectorOutput: ProjectorOutputController?
    private let camera = CameraManager()
    private var engine: MattingEngine
    private let monitor = PerformanceMonitor()
    private let inferenceQueue = DispatchQueue(label: "dancefx.inference", qos: .userInteractive)
    private let poseQueue = DispatchQueue(label: "dancefx.pose", qos: .userInitiated)
    private let poseDetector = BodyPoseDetector()
    private var inferenceInProgress = false
    private var poseInferenceInProgress = false
    private var poseFrameCounter = 0
    private var isApplyingPreset = false
    private var presetSelectionTask: Task<Void, Never>?
    private var effectSyncTask: Task<Void, Never>?
    private var pendingPresetCaptureID: UUID?
    private var metricsTimer: Timer?
    private static let presetsKey = "dancefx.effectPresets.v1"
    private static let controlPanelTransparentKey = "dancefx.controlPanel.transparent.v1"

    init() {
        renderer = MetalRenderer()
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
            Task { @MainActor in self?.statusMessage = message }
        }

        videoAssets = Self.discoverVideoAssets()
        for asset in videoAssets {
            renderer.configureVideoFill(url: asset.url, id: asset.id)
        }
        selectedVideoAssetID = defaultVideoAssetID

        let storedPresets = Self.loadStoredPresets()
        presets = storedPresets.isEmpty ? [Self.defaultPreset] : storedPresets
        if storedPresets.isEmpty { persistPresets() }
        if let first = presets.first {
            apply(first)
            selectedPresetID = first.id
            presetName = first.name
        }

        projectorOutput = ProjectorOutputController(renderer: renderer) { [weak self] message, connected in
            self?.projectorStatus = message
            self?.projectorConnected = connected
        }
    }

    func start() {
        projectorOutput?.start()
        cameras = camera.availableCameras()
        selectedCameraID = cameras.first?.id ?? ""
        guard !selectedCameraID.isEmpty else {
            statusMessage = "No camera was found. Connect a webcam or capture device."
            return
        }
        updateOutputMirroring(cameraID: selectedCameraID)

        metricsTimer?.invalidate()
        metricsTimer = .scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.metrics = self.monitor.snapshot() }
        }

        Task {
            let granted = await camera.requestAccess()
            guard granted else {
                statusMessage = "Camera access was denied. Enable it in System Settings → Privacy & Security → Camera."
                return
            }
            do {
                try camera.start(cameraID: selectedCameraID)
                statusMessage = "\(engine.displayName) active."
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func stop() {
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
            statusMessage = error.localizedDescription
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
            metrics = .zero
            renderer.clearTrailHistory()
            renderer.clearSampleHistory()
            statusMessage = "\(replacement.displayName) active."
        } catch {
            statusMessage = "Could not switch RVM quality: \(error.localizedDescription)"
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

        skeletonOpacity = .random(in: 0.1...1)
        skeletonConfidence = .random(in: 0.1...0.9)
        linesOpacity = .random(in: 0.1...1)
        linesConfidence = .random(in: 0.1...0.9)
        linesConnections = .random(in: 1...6)
        linesThickness = .random(in: 1...16)
        linesGeometryOnly = Bool.random()
        sampleLines = []
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
            sampleLines = [SampleLine(ax: 0.2, ay: 0.5, bx: 0.8, by: 0.5)]
        }
        statusMessage = "Randomized \(effectCount) effect\(effectCount == 1 ? "" : "s")."
    }

    func removeEffect(_ effect: EffectKind) {
        activeEffects.removeAll { $0 == effect }
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
        if effect == .lineSampler { renderer.clearSampleHistory() }
    }

    func addSampleLine(from a: CGPoint, to b: CGPoint) {
        guard sampleLines.count < 16, hypot(a.x - b.x, a.y - b.y) > 0.01 else { return }
        sampleLines.append(SampleLine(ax: a.x, ay: a.y, bx: b.x, by: b.y))
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
            statusMessage = "Enter a preset name first."
            return
        }
        applyEffectsToRenderer()
        var preset = currentPreset(name: trimmedName)
        if let index = presets.firstIndex(where: {
            $0.name.compare(trimmedName, options: .caseInsensitive) == .orderedSame
        }) {
            preset.id = presets[index].id
        }
        let captureID = UUID()
        pendingPresetCaptureID = captureID
        isSavingPreset = true
        statusMessage = "Capturing preview for “\(preset.name)”…"
        renderer.captureNextFrame(id: captureID) { [weak self] imageData in
            Task { @MainActor [weak self] in
                self?.finishSavingPreset(preset, captureID: captureID, imageData: imageData)
            }
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, self.pendingPresetCaptureID == captureID else { return }
            self.renderer.cancelFrameCapture(id: captureID)
            self.pendingPresetCaptureID = nil
            self.isSavingPreset = false
            self.statusMessage = "No output frame was available. Preset was not saved."
        }
    }

    private func finishSavingPreset(_ capturedPreset: EffectPreset, captureID: UUID, imageData: Data?) {
        guard pendingPresetCaptureID == captureID else { return }
        pendingPresetCaptureID = nil
        isSavingPreset = false
        guard let imageData else {
            statusMessage = "Could not capture the output frame. Preset was not saved."
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
            statusMessage = "Preset “\(preset.name)” saved."
        } catch {
            statusMessage = "Could not save preset preview: \(error.localizedDescription)"
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
        statusMessage = "Preset “\(deletedName)” deleted."
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
            clapExplosionBlendMode: blendMode(for: .clapExplosions)
        )
    }

    private func apply(_ preset: EffectPreset) {
        guard !isApplyingPreset else { return }
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
        sampleLines = preset.sampleLines ?? []
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

    private static var thumbnailDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DanceFX/Preset Thumbnails", isDirectory: true)
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
        sampleLines: [], sampleDirection: .both, sampleSpeed: 180,
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
            poseQueue.async { [weak self] in
                do {
                    renderer.updatePose(try detector.detect(pixelBuffer: frame.pixelBuffer, includeHands: detectHands))
                } catch {
                    renderer.updatePose(nil)
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
                Task { @MainActor in self?.statusMessage = "Matting failed: \(error.localizedDescription)" }
            }
            Task { @MainActor in self?.inferenceInProgress = false }
        }
    }
}
