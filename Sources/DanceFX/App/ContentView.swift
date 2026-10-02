import SwiftUI

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var controller: AppController

    var body: some View {
        ScrollView(.vertical) {
            controls
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(14)
        }
        .background {
            if !controller.controlPanelTransparent {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .background(ControlPanelWindowConfigurator(
            transparentBackground: controller.controlPanelTransparent
        ))
        .preferredColorScheme(.dark)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            AdaptiveFlowLayout(horizontalSpacing: 12) {
                Image(systemName: controller.projectorConnected ? "display.and.arrow.down" : "rectangle.inset.filled")
                    .foregroundStyle(controller.projectorConnected ? .green : .blue)
                Text(controller.projectorStatus)
                    .fontWeight(.medium)

                if let message = controller.statusMessage {
                    Divider()
                        .frame(height: 18)
                    Text(message)
                        .foregroundStyle(.secondary)
                }

                Button("Refresh Displays") { controller.refreshProjectorOutput() }
            }
            .font(.system(.callout, design: .rounded))

            Divider()

            AdaptiveFlowLayout(horizontalSpacing: 16) {
                Picker("Camera", selection: Binding(
                    get: { controller.selectedCameraID },
                    set: { controller.selectCamera(id: $0) }
                )) {
                    ForEach(controller.cameras) { camera in
                        Text(camera.name).tag(camera.id)
                    }
                }
                .frame(width: 250)

                Picker("Mode", selection: $controller.mode) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                Picker("Background", selection: $controller.background) {
                    ForEach(BackgroundChoice.allCases) { background in
                        Text(background.label).tag(background)
                    }
                }
                .frame(width: 160)

                Picker("RVM", selection: Binding(
                    get: { controller.rvmProfile },
                    set: { controller.selectRVMProfile($0) }
                )) {
                    ForEach(RVMProfile.allCases) { profile in
                        Text(profile.label).tag(profile)
                    }
                }
                .frame(width: 180)
            }

            AdaptiveFlowLayout(horizontalSpacing: 20) {
                metric("Capture", controller.metrics.captureFPS, "fps")
                metric("Processed", controller.metrics.processedFPS, "fps")
                metric("Inference", controller.metrics.inferenceMS, "ms")
                metric("Render", controller.metrics.renderMS, "ms")
                metric("Latency", controller.metrics.latencyMS, "ms")
                Text("Dropped  \(controller.metrics.droppedFrames)")
                    .monospacedDigit()

                Button("Reset Matting") { controller.resetMatting() }
                    .keyboardShortcut("r", modifiers: [.command])
            }
            .font(.system(.callout, design: .rounded))

            Divider()

            effectsControls
        }
    }

    private var effectsControls: some View {
        VStack(spacing: 10) {
            AdaptiveFlowLayout(horizontalSpacing: 14) {
                Picker("Preset", selection: Binding(
                    get: { controller.selectedPresetID },
                    set: { if let id = $0 { controller.selectPreset(id: id) } }
                )) {
                    ForEach(controller.presets) { preset in
                        Text(preset.name).tag(Optional(preset.id))
                    }
                }
                .frame(width: 190)

                TextField("Preset name", text: $controller.presetName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)

                Button("Save Preset") { controller.savePreset() }
                    .disabled(controller.isSavingPreset)
                Button {
                    openWindow(id: "preset-library")
                } label: {
                    Label("Library", systemImage: "square.grid.2x2")
                }
                Button("Delete") { controller.deleteSelectedPreset() }
                    .disabled(controller.presets.count <= 1)

                Button("Randomize") { controller.randomizeEffects() }

                Menu("Add Effect") {
                    ForEach(EffectKind.allCases) { effect in
                        Button(effect.label) { controller.addEffect(effect) }
                            .disabled(controller.activeEffects.contains(effect))
                    }
                }
            }

            AdaptiveFlowLayout(horizontalSpacing: 6, verticalSpacing: 4) {
                Text("INPUT")
                Image(systemName: "arrow.down")
                Text("OUTPUT")
                Text("Effects lower in the list process the output of effects above them.")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            // The stack is small (one row per effect). Keeping rows alive avoids
            // repeatedly constructing AppKit-backed sliders while scrolling.
            VStack(spacing: 8) {
                ForEach(controller.activeEffects) { effect in
                    effectRow(effect)
                }
            }
        }
        .font(.system(.callout, design: .rounded))
    }

    private func effectRow(_ effect: EffectKind) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Text(effect.label)
                    .font(.system(.headline, design: .rounded, weight: .bold))

                Spacer()

                Toggle("Enabled", isOn: Binding(
                    get: { controller.isEffectEnabled(effect) },
                    set: { controller.setEffectEnabled(effect, enabled: $0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .accessibilityLabel("Enable \(effect.label)")
                .help("Enable or disable \(effect.label)")

                Picker("Blend", selection: Binding(
                    get: { controller.blendMode(for: effect) },
                    set: { controller.setBlendMode($0, for: effect) }
                )) {
                    ForEach(OverlayBlendMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 145)
                .accessibilityLabel("Blend mode for \(effect.label)")
                .help("Blend mode for \(effect.label)")

                Button {
                    controller.moveEffect(effect, by: -1)
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.plain)
                .disabled(controller.activeEffects.first == effect)
                .help("Move earlier")

                Button {
                    controller.moveEffect(effect, by: 1)
                } label: {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.plain)
                .disabled(controller.activeEffects.last == effect)
                .help("Move later")

                Button {
                    controller.removeEffect(effect)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .help("Remove effect")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.accentColor.opacity(0.16))

            Divider()
                .overlay(Color.accentColor.opacity(0.45))

            effectParameters(effect)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .opacity(controller.isEffectEnabled(effect) ? 1 : 0.5)
        }
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.accentColor.opacity(0.42), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func effectParameters(_ effect: EffectKind) -> some View {
        switch effect {
        case .gradientOverlay:
            AdaptiveFlowLayout(horizontalSpacing: 14) {
                Picker("Style", selection: $controller.gradientStyle) {
                    ForEach(GradientStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .frame(width: 150)
                effectSlider("Opacity", value: $controller.gradientOpacity, range: 0...1,
                             display: "\(Int(controller.gradientOpacity * 100))%", enabled: true)
                effectSlider("Angle", value: $controller.gradientAngleDegrees, range: -180...180,
                             display: "\(Int(controller.gradientAngleDegrees))°", enabled: true)
            }

        case .historicalTrail:
            VStack(spacing: 8) {
                AdaptiveFlowLayout(horizontalSpacing: 14) {
                    Stepper("\(controller.cloneCount) samples", value: $controller.cloneCount, in: 1...16)
                        .frame(width: 135)
                    effectSlider("Rotation", value: $controller.cloneRotationDegrees, range: -15...15,
                                 display: String(format: "%.1f°", controller.cloneRotationDegrees), enabled: true)
                    effectSlider("Scale", value: $controller.cloneScalePercent, range: -8...8,
                                 display: String(format: "%.1f%%", controller.cloneScalePercent), enabled: true)
                    effectSlider("X", value: $controller.cloneTranslationXPercent, range: -5...5,
                                 display: String(format: "%.1f%%", controller.cloneTranslationXPercent), enabled: true)
                    effectSlider("Y", value: $controller.cloneTranslationYPercent, range: -5...5,
                                 display: String(format: "%.1f%%", controller.cloneTranslationYPercent), enabled: true)
                }
                AdaptiveFlowLayout(horizontalSpacing: 14) {
                    effectSlider("Opacity", value: $controller.cloneOpacity, range: 0...1,
                                 display: "\(Int(controller.cloneOpacity * 100))%", enabled: true)
                    effectSlider("Decay", value: $controller.cloneDecay, range: 0.35...1,
                                 display: String(format: "%.2f", controller.cloneDecay), enabled: true)
                    effectSlider("Lifetime", value: $controller.trailLifetime, range: 0.5...6,
                                 display: String(format: "%.1f s", controller.trailLifetime), enabled: true)
                }
            }

        case .liquidDistortion:
            AdaptiveFlowLayout(horizontalSpacing: 14) {
                effectSlider("Strength", value: $controller.liquidStrength, range: 0...8,
                             display: String(format: "%.1f%%", controller.liquidStrength), enabled: true)
                effectSlider("Scale", value: $controller.liquidScale, range: 1...12,
                             display: String(format: "%.1f", controller.liquidScale), enabled: true)
                effectSlider("Speed", value: $controller.liquidSpeed, range: 0...3,
                             display: String(format: "%.1fx", controller.liquidSpeed), enabled: true)
            }

        case .liveVideoFill, .flowers:
            AdaptiveFlowLayout(horizontalSpacing: 14) {
                Picker("Video", selection: $controller.selectedVideoAssetID) {
                    ForEach(controller.videoAssets) { asset in
                        Text(asset.name).tag(asset.id)
                    }
                }
                .frame(width: 190)
                .disabled(controller.videoAssets.isEmpty)
                Text("Trail timing follows FX order")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                effectSlider("Opacity", value: $controller.videoOpacity, range: 0...1,
                             display: "\(Int(controller.videoOpacity * 100))%", enabled: true)
                effectSlider("Zoom", value: $controller.videoScale, range: 0.5...3,
                             display: String(format: "%.1fx", controller.videoScale), enabled: true)
                effectSlider("Speed", value: $controller.videoPlaybackRate, range: 0.25...2,
                             display: String(format: "%.2fx", controller.videoPlaybackRate), enabled: true)
            }

        case .clapExplosions:
            AdaptiveFlowLayout(horizontalSpacing: 14) {
                Text("Plays a clip at each hand contact")
                    .foregroundStyle(.secondary)
                effectSlider("Size", value: $controller.clapExplosionSize, range: 0.15...1.5,
                             display: String(format: "%.2fx", controller.clapExplosionSize), enabled: true)
                effectSlider("Opacity", value: $controller.clapExplosionOpacity, range: 0...1,
                             display: "\(Int(controller.clapExplosionOpacity * 100))%", enabled: true)
            }

        case .skeleton:
            AdaptiveFlowLayout(horizontalSpacing: 14) {
                Text("White body-pose lines")
                    .foregroundStyle(.secondary)
                effectSlider("Opacity", value: $controller.skeletonOpacity, range: 0.1...1,
                             display: "\(Int(controller.skeletonOpacity * 100))%", enabled: true)
                effectSlider("Confidence", value: $controller.skeletonConfidence, range: 0.1...0.9,
                             display: String(format: "%.2f", controller.skeletonConfidence), enabled: true)
            }

        case .lines:
            AdaptiveFlowLayout(horizontalSpacing: 14) {
                Text("Geometric mesh between pose points")
                    .foregroundStyle(.secondary)
                Toggle("Geometry only", isOn: $controller.linesGeometryOnly)
                    .toggleStyle(.switch)
                Stepper("\(controller.linesConnections) links / point",
                        value: $controller.linesConnections, in: 1...6)
                    .frame(width: 150)
                effectSlider("Thickness", value: $controller.linesThickness, range: 1...16,
                             display: String(format: "%.1f px", controller.linesThickness), enabled: true)
                effectSlider("Opacity", value: $controller.linesOpacity, range: 0.1...1,
                             display: "\(Int(controller.linesOpacity * 100))%", enabled: true)
                effectSlider("Confidence", value: $controller.linesConfidence, range: 0.1...0.9,
                             display: String(format: "%.2f", controller.linesConfidence), enabled: true)
            }

        case .lineSampler:
            VStack(alignment: .leading, spacing: 10) {
                Text("Drag on the black pad to add a line. New lines copy the previous line’s settings and get their own MIDI channel. Drag an endpoint to adjust it. A → B defines note order.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SampleLinePad(controller: controller)
                    .frame(width: 320, height: 180)
                HStack {
                    Text("\(controller.sampleLines.count) lines (max 16)")
                        .foregroundStyle(.secondary)
                    Button("Clear all") { controller.sampleLines.removeAll() }
                        .disabled(controller.sampleLines.isEmpty)
                }
                HStack {
                    Text("BPM")
                    TextField("BPM", value: sampleBPMBinding, format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                    Stepper("BPM", value: sampleBPMBinding, in: 30...240, step: 1)
                        .labelsHidden()
                }
                Text("MIDI channels stay with their lines. Channel 10 is General MIDI percussion.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach($controller.sampleLines) { lineBinding in
                    let id = lineBinding.wrappedValue.id
                    SampleLineSettings(
                        line: lineBinding,
                        number: (controller.sampleLines.firstIndex(where: { $0.id == id }) ?? 0) + 1
                    ) {
                        controller.deleteSampleLine(id: id)
                    }
                }
                Picker("Direction", selection: $controller.sampleDirection) {
                    ForEach(SampleDirection.allCases) { direction in
                        Text(direction.label).tag(direction)
                    }
                }
                effectSlider("Speed", value: $controller.sampleSpeed, range: 20...600,
                             display: "\(Int(controller.sampleSpeed)) px/s", enabled: true)
                HStack(spacing: 6) {
                    Text("Samples")
                    TextField("Count", value: sampleCountBinding, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 58)
                    Stepper("Samples", value: sampleCountBinding, in: 1...512)
                        .labelsHidden()
                }
                effectSlider("Sampling thickness", value: $controller.sampleThickness, range: 1...24,
                             display: String(format: "%.1f px", controller.sampleThickness), enabled: true)
                effectSlider("Opacity", value: $controller.sampleOpacity, range: 0...1,
                             display: "\(Int(controller.sampleOpacity * 100))%", enabled: true)
                effectSlider("Fade", value: $controller.sampleFade, range: 0...4,
                             display: String(format: "%.1f", controller.sampleFade), enabled: true)
            }

        case .particles:
            VStack(spacing: 8) {
                AdaptiveFlowLayout(horizontalSpacing: 14) {
                    Picker("Spawn", selection: $controller.particleSpawnSource) {
                        ForEach(ParticleSpawnSource.allCases) { source in
                            Text(source.label).tag(source)
                        }
                    }
                    .frame(width: 180)
                    Text(controller.particleSpawnSource == .limbs
                         ? "Wrists, ankles & head"
                         : "Random silhouette edges")
                        .foregroundStyle(.secondary)
                    effectSlider("Rate", value: $controller.particleRate, range: 5...160,
                                 display: "\(Int(controller.particleRate))/s", enabled: true)
                    effectSlider("Lifetime", value: $controller.particleLifetime, range: 0.2...10,
                                 display: String(format: "%.1f s", controller.particleLifetime), enabled: true)
                    effectSlider("Size", value: $controller.particleSizeScale, range: 0...16,
                                 display: String(format: "%.1fx", controller.particleSizeScale), enabled: true)
                }
                AdaptiveFlowLayout(horizontalSpacing: 14) {
                    Picker("Color", selection: $controller.particleColorSource) {
                        ForEach(ParticleColorSource.allCases) { source in
                            Text(source.label).tag(source)
                        }
                    }
                    .frame(width: 210)
                    effectSlider("Motion size", value: $controller.particleMotionSize, range: 0...5,
                                 display: String(format: "%.1fx", controller.particleMotionSize),
                                 enabled: controller.particleSpawnSource == .limbs)
                    effectSlider("Speed", value: $controller.particleSpeed, range: 0...3,
                                 display: String(format: "%.1fx", controller.particleSpeed), enabled: true)
                    effectSlider("Spread", value: $controller.particleSpreadDegrees, range: 0...180,
                                 display: "\(Int(controller.particleSpreadDegrees))°", enabled: true)
                    effectSlider("Momentum", value: $controller.particleMomentum, range: 0...1.5,
                                 display: String(format: "%.2fx", controller.particleMomentum),
                                 enabled: controller.particleSpawnSource == .limbs)
                    effectSlider("Confidence", value: $controller.skeletonConfidence, range: 0.1...0.9,
                                 display: String(format: "%.2f", controller.skeletonConfidence),
                                 enabled: controller.particleSpawnSource == .limbs)
                }
                if controller.particleSpawnSource == .shapeBorder {
                    AdaptiveFlowLayout(horizontalSpacing: 14) {
                        Text("All segmented silhouettes")
                            .foregroundStyle(.secondary)
                        effectSlider("Border threshold", value: $controller.particleBorderThreshold, range: 0.1...0.9,
                                     display: String(format: "%.2f", controller.particleBorderThreshold), enabled: true)
                    }
                }
                AdaptiveFlowLayout(horizontalSpacing: 14) {
                    Picker("Shape", selection: $controller.particleShape) {
                        ForEach(ParticleShape.allCases) { shape in
                            Text(shape.label).tag(shape)
                        }
                    }
                    .frame(width: 150)
                    effectSlider("Gravity", value: $controller.particleGravity, range: -0.3...0.5,
                                 display: String(format: "%+.2f", controller.particleGravity), enabled: true)
                    effectSlider("Drag", value: $controller.particleDrag, range: 0...4,
                                 display: String(format: "%.1f", controller.particleDrag), enabled: true)
                    effectSlider("End size", value: $controller.particleEndSize, range: 0...2,
                                 display: String(format: "%.2fx", controller.particleEndSize), enabled: true)
                }
            }
        }
    }

    private func effectSlider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        display: String,
        enabled: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Text(label)
            Slider(value: value, in: range)
                .frame(minWidth: 70, maxWidth: 130)
            Text(display)
                .monospacedDigit()
                .frame(minWidth: 40, alignment: .trailing)
        }
        .disabled(!enabled)
    }

    private var sampleCountBinding: Binding<Int> {
        Binding(
            get: { controller.sampleCount },
            set: { controller.sampleCount = min(512, max(1, $0)) }
        )
    }

    private var sampleBPMBinding: Binding<Double> {
        Binding(
            get: { controller.sampleBPM },
            set: { controller.sampleBPM = $0.isFinite ? min(240, max(30, $0)) : 120 }
        )
    }

    private func metric(_ name: String, _ value: Double, _ unit: String) -> some View {
        Text("\(name)  \(value, format: .number.precision(.fractionLength(1))) \(unit)")
            .monospacedDigit()
    }
}
