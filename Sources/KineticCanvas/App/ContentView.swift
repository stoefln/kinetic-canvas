import SwiftUI

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var controller: AppController
    /// Whether the global Settings panel is open. Persisted across launches so a
    /// collapsed panel stays collapsed; not part of any effect preset.
    @AppStorage("kineticcanvas.controlPanel.settingsExpanded.v1") private var settingsExpanded = false

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
        .background(WindowConfigurator(
            transparentBackground: controller.controlPanelTransparent,
            autosaveName: "KineticCanvas.ControlPanel.Frame.v1",
            floatsWhenActive: true
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

            settingsPanel

            Divider()

            effectsControls
        }
    }

    /// Collapsible panel holding the global capture and tracking settings. It
    /// matches the effect-row chrome so the control panel reads as one stack.
    private var settingsPanel: some View {
        VStack(spacing: 0) {
            Button {
                settingsExpanded.toggle()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "chevron.right")
                        .font(.system(.callout, weight: .semibold))
                        .rotationEffect(.degrees(settingsExpanded ? 90 : 0))
                        .frame(width: 14, height: 14)
                    Text("Settings")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.accentColor.opacity(0.16))
            .accessibilityLabel(settingsExpanded ? "Collapse settings" : "Expand settings")
            .help(settingsExpanded ? "Collapse settings" : "Expand settings")

            if settingsExpanded {
                Divider()
                    .overlay(Color.accentColor.opacity(0.45))

                VStack(alignment: .leading, spacing: 12) {
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

                        Stepper("Max people: \(controller.maxPeople)",
                                value: $controller.maxPeople, in: 1...8)
                            .frame(width: 170)
                            .help("How many bodies pose tracking follows at once. 1 is fastest and most stable; higher values add a skeleton, mesh, and limb emitters per person.")
                    }

                    MetricsRow(store: controller.metricsStore) { controller.resetMatting() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        }
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.accentColor.opacity(0.42), lineWidth: 1)
        }
        .font(.system(.callout, design: .rounded))
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
        let collapsed = controller.collapsedEffects.contains(effect)
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    Button {
                        controller.setEffectCollapsed(effect, collapsed: !collapsed)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(.callout, weight: .semibold))
                            .rotationEffect(.degrees(collapsed ? 0 : 90))
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(collapsed ? "Expand \(effect.label)" : "Collapse \(effect.label)")
                    .help(collapsed ? "Expand \(effect.label)" : "Collapse \(effect.label)")

                    Text(effect.label)
                        .font(.system(.headline, design: .rounded, weight: .bold))

                    Spacer(minLength: 0)

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
                }

                HStack(spacing: 9) {
                    Button {
                        controller.setEffectEnabled(effect, enabled: !controller.isEffectEnabled(effect))
                    } label: {
                        Image(systemName: controller.isEffectEnabled(effect)
                              ? "checkmark.circle.fill" : "circle")
                            .font(.system(.callout))
                            .foregroundStyle(controller.isEffectEnabled(effect)
                                             ? Color.primary : Color.secondary)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(controller.isEffectEnabled(effect)
                                        ? "Disable \(effect.label)" : "Enable \(effect.label)")
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

                    Spacer(minLength: 0)

                    Button {
                        controller.removeEffect(effect)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .help("Remove effect")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.accentColor.opacity(0.16))

            if !collapsed {
                Divider()
                    .overlay(Color.accentColor.opacity(0.45))

                effectParameters(effect)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .opacity(controller.isEffectEnabled(effect) ? 1 : 0.5)
            }
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
            VStack(alignment: .leading, spacing: 12) {
                parameterSection("Lines", systemImage: "line.diagonal") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Drag on the pad to add a line; drag an endpoint to adjust it. A → B sets note order. Lines are hidden on the output until Visibility is raised. Each line can also sample the output of the other lines instead of the camera.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        SampleLinePad(controller: controller, samplerState: controller.samplerState)
                            .frame(width: 320, height: 180)
                        HStack {
                            Text("\(controller.sampleLines.count) lines (max 16)")
                                .foregroundStyle(.secondary)
                            Button("Clear all") { controller.sampleLines.removeAll() }
                                .disabled(controller.sampleLines.isEmpty)
                        }
                        ForEach($controller.sampleLines) { lineBinding in
                            let id = lineBinding.wrappedValue.id
                            let channel = lineBinding.wrappedValue.midiChannel
                            SampleLineSettingsRow(
                                line: lineBinding,
                                number: (controller.sampleLines.firstIndex(where: { $0.id == id }) ?? 0) + 1,
                                harmony: controller.sampleHarmony,
                                sharesChannel: channel >= 0
                                    && controller.sampleLines.filter { $0.midiChannel == channel }.count > 1,
                                clipState: controller.clipState,
                                instrumentState: controller.instrumentState,
                                setEnabled: { controller.setSampleEnabled(id: id, enabled: $0) },
                                setChannel: { controller.setSampleChannel(id: id, channel: $0) },
                                setLead: { controller.setSampleLead(id: id, enabled: $0) },
                                setModulation: { controller.setSampleModulationSource(id: id, enabled: $0) },
                                setModulationCC: { controller.setSampleModulationCC(id: id, cc: $0) },
                                testCC: { controller.sendTestCC(id: id) },
                                setDestination: { controller.setSampleDestination(id: id, destination: $0) },
                                importClip: { controller.importAudioClip(id: id) },
                                clearClip: { controller.clearAudioClip(id: id) },
                                setClipSourceBPM: { controller.setClipSourceBPM(id: id, bpm: $0) },
                                setClipBeats: { controller.setClipBeats(id: id, beats: $0) },
                                setClipLevel: { controller.setClipLevel(id: id, level: $0) },
                                setClipStartMuted: { controller.setClipStartMuted(id: id, muted: $0) },
                                openInstrument: { controller.openVitalEditor(id: id) },
                                captureInstrument: { controller.captureVitalSound(id: id) },
                                clearInstrument: { controller.clearVitalSound(id: id) },
                                setInstrument: { controller.setSampleInstrument(id: id, reference: $0) }
                            ) {
                                controller.deleteSampleLine(id: id)
                            }
                        }
                        Toggle("Show additional info", isOn: $controller.sampleShowNotes)
                            .help("Show note names on each line and its number in a circle at the start (lowest key)")
                    }
                }

                Divider()

                parameterSection("Sampling", systemImage: "rectangle.split.3x1") {
                    AdaptiveFlowLayout(horizontalSpacing: 14) {
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
                        effectSlider("Thickness", value: $controller.sampleThickness, range: 1...24,
                                     display: String(format: "%.1f px", controller.sampleThickness), enabled: true)
                        effectSlider("Opacity", value: $controller.sampleOpacity, range: 0...1,
                                     display: "\(Int(controller.sampleOpacity * 100))%", enabled: true)
                        effectSlider("Fade", value: $controller.sampleFade, range: 0...4,
                                     display: String(format: "%.1f", controller.sampleFade), enabled: true)
                        effectSlider("Trigger", value: $controller.sampleTriggerThreshold, range: 0.02...1,
                                     display: "\(Int(controller.sampleTriggerThreshold * 100))%", enabled: true)
                    }
                }

                Divider()

                parameterSection("Harmony", systemImage: "music.quarternote.3") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Root Key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        AdaptiveFlowLayout(horizontalSpacing: 6) {
                            ForEach(0..<12, id: \.self) { root in
                                rootKeyButton(root)
                            }
                        }
                        AdaptiveFlowLayout(horizontalSpacing: 14) {
                            Picker("Scale", selection: $controller.sampleScale) {
                                ForEach(SampleScale.allCases) { scale in
                                    Text(scale.label).tag(scale)
                                }
                            }
                            .frame(width: 190)
                            Picker("Lead transpose", selection: $controller.sampleTransposeMode) {
                                ForEach(SampleTransposeMode.allCases) { mode in
                                    Text(mode.label).tag(mode)
                                }
                            }
                            .frame(width: 190)
                            .help(controller.sampleTransposeMode.detail)
                            Text("Each line keeps its own register and channel.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 6) {
                            Text("Consonance")
                            CommitSlider(value: $controller.sampleTension, range: 0...1)
                            Text(controller.sampleHarmony.tensionLabel)
                                .monospacedDigit()
                                .frame(minWidth: 84, alignment: .trailing)
                        }
                        Text("Limits which notes may sound together. Melodies are never restricted; a blocked segment simply stays silent.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                parameterSection("MIDI Output", systemImage: "music.note") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("Tempo")
                            TextField("BPM", value: sampleBPMBinding, format: .number.precision(.fractionLength(0)))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 64)
                            Stepper("BPM", value: sampleBPMBinding, in: 30...240, step: 1)
                                .labelsHidden()
                            Text("BPM")
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 6) {
                            Text("Volume")
                            CommitSlider(value: $controller.sampleMasterVolume, range: 0...1)
                                .frame(maxWidth: 150)
                            Text("\(Int(controller.sampleMasterVolume * 100))%")
                                .monospacedDigit()
                                .frame(minWidth: 38, alignment: .trailing)
                        }
                        .help("MIDI channel volume (CC7) sent to every channel")
                        Toggle("Quantize note onsets to 1/16 grid", isOn: $controller.sampleQuantize)
                            .help("New notes wait for the next 16th-note grid line instead of starting mid-grid")
                        Picker("MIDI ports", selection: $controller.sampleMIDIPortMode) {
                            ForEach(SampleMIDIPortMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .frame(width: 240)
                        .help(controller.sampleMIDIPortMode.detail)
                        HStack(spacing: 6) {
                            Button("Test note") { controller.sendTestNote() }
                            Text("Velocity")
                            CommitSlider(value: $controller.testNoteVelocity, range: 1...127)
                                .frame(maxWidth: 150)
                            Text("\(Int(controller.testNoteVelocity.rounded()))")
                                .monospacedDigit()
                                .frame(minWidth: 30, alignment: .trailing)
                        }
                        Text("Test note plays channel 1 at the chosen velocity to check a host's response. Root and scale are global; each line keeps its own register and channel. Channel 10 is percussion in General MIDI.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
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
            CommitSlider(value: value, range: range)
                .frame(minWidth: 70, maxWidth: 130)
            Text(display)
                .monospacedDigit()
                .frame(minWidth: 40, alignment: .trailing)
        }
        .disabled(!enabled)
    }

    /// A light labelled grouping inside an effect card. Keeps long option lists
    /// (Line Sampler especially) scannable without adding a second row header.
    private func parameterSection<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title.uppercased())
                    .tracking(1.1)
            }
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .foregroundStyle(Color.accentColor.opacity(0.85))

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rootKeyButton(_ root: Int) -> some View {
        let selected = controller.sampleRoot == root
        return Button {
            controller.sampleRoot = root
        } label: {
            Text(SampleLine.noteClasses[root])
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .frame(minWidth: 30)
                .padding(.vertical, 3)
                .background(
                    selected ? Color.accentColor.opacity(0.85) : Color.white.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
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
}

/// Observes the clip state store so a single line's loop/one-shot status badge
/// updates without rebuilding the whole control panel.
private struct SampleLineSettingsRow: View {
    @Binding var line: SampleLine
    let number: Int
    let harmony: SampleHarmony
    let sharesChannel: Bool
    @ObservedObject var clipState: ClipStateStore
    @ObservedObject var instrumentState: InstrumentStateStore
    let setEnabled: (Bool) -> Void
    let setChannel: (Int) -> Void
    let setLead: (Bool) -> Void
    let setModulation: (Bool) -> Void
    let setModulationCC: (Int) -> Void
    let testCC: () -> Void
    let setDestination: (SampleLineDestination) -> Void
    let importClip: () -> Void
    let clearClip: () -> Void
    let setClipSourceBPM: (Double) -> Void
    let setClipBeats: (Double) -> Void
    let setClipLevel: (Double) -> Void
    let setClipStartMuted: (Bool) -> Void
    let openInstrument: () -> Void
    let captureInstrument: () -> Void
    let clearInstrument: () -> Void
    let setInstrument: (AUStateReference?) -> Void
    let delete: () -> Void

    var body: some View {
        SampleLineSettings(
            line: $line,
            number: number,
            harmony: harmony,
            sharesChannel: sharesChannel,
            clipState: clipState.states[line.id] ?? .empty,
            instrumentStatus: instrumentState.statuses[line.id],
            savedSounds: instrumentState.sounds,
            setEnabled: setEnabled,
            setChannel: setChannel,
            setLead: setLead,
            setModulation: setModulation,
            setModulationCC: setModulationCC,
            testCC: testCC,
            setDestination: setDestination,
            importClip: importClip,
            clearClip: clearClip,
            setClipSourceBPM: setClipSourceBPM,
            setClipBeats: setClipBeats,
            setClipLevel: setClipLevel,
            setClipStartMuted: setClipStartMuted,
            openInstrument: openInstrument,
            captureInstrument: captureInstrument,
            clearInstrument: clearInstrument,
            setInstrument: setInstrument,
            delete: delete
        )
    }
}

/// Observes only `MetricsStore`, so its twice-per-second refresh stays local to
/// this row instead of rebuilding every effect card in the control panel.
private struct MetricsRow: View {
    @ObservedObject var store: MetricsStore
    let reset: () -> Void

    var body: some View {
        AdaptiveFlowLayout(horizontalSpacing: 20) {
            metric("Capture", store.snapshot.captureFPS, "fps")
            metric("Processed", store.snapshot.processedFPS, "fps")
            metric("Inference", store.snapshot.inferenceMS, "ms")
            metric("Render", store.snapshot.renderMS, "ms")
            metric("Latency", store.snapshot.latencyMS, "ms")
            Text("Dropped  \(store.snapshot.droppedFrames)")
                .monospacedDigit()

            Button("Reset Matting", action: reset)
                .keyboardShortcut("r", modifiers: [.command])
        }
        .font(.system(.callout, design: .rounded))
    }

    private func metric(_ name: String, _ value: Double, _ unit: String) -> some View {
        Text("\(name)  \(value, format: .number.precision(.fractionLength(1))) \(unit)")
            .monospacedDigit()
    }
}
