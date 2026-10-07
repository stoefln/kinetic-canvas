import SwiftUI

struct SampleLineSettings: View {
    @Binding var line: SampleLine
    let number: Int
    /// Global root/scale/tension, shared by every line.
    let harmony: SampleHarmony
    /// True when another line also routes to this line's channel.
    let sharesChannel: Bool
    /// Live clip state for this line, if it has an audio destination.
    let clipState: ClipPlaybackState
    /// Live slot status for this line, if it has a Vital destination.
    let instrumentStatus: InstrumentLineStatus?
    /// Every captured Vital sound available to pick from.
    let savedSounds: [AUStateReference]
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
    @State private var expanded = false

    private var allowedOctaves: [Int] {
        let topOffset = harmony.topOctaveOffset(forKeys: harmony.resolvedKeyCount(line.keyCount))
        return (-1...9).filter {
            ($0 + topOffset + 1) * 12 + harmony.root + (harmony.scale.offsets.last ?? 0) <= 127
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                // The whole header toggles expansion, not just the disclosure arrow.
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                        Text(summary)
                            .foregroundStyle(line.isEnabled && line.visibility > 0.01 ? .primary : .secondary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Toggle("", isOn: Binding(get: { line.isEnabled }, set: setEnabled))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
                    .help(line.isEnabled ? "Disable this line" : "Enable this line")
            }

            if expanded {
                controls
                    .padding(.top, 6)
            }
        }
        .padding(9)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .opacity(line.isEnabled ? 1 : 0.55)
        .onChange(of: harmony) { _, _ in clampOctave() }
        .onChange(of: line.keyCount) { _, _ in clampOctave() }
        .onChange(of: line.midiEnabled) { _, enabled in
            if !enabled && line.isLead { setLead(false) }
        }
    }

    private var summary: String {
        var parts = ["Line \(number)"]
        if !line.isEnabled { parts.append("Off") }
        if line.destination == .loop { parts.append("Loop") }
        if line.destination == .oneShot { parts.append("One-shot") }
        if line.destination == .vital {
            parts.append("Vital")
            parts.append(line.instrument?.name ?? "No sound")
        }
        if line.destination == .loop || line.destination == .oneShot {
            parts.append(line.clip?.fileName ?? "No clip")
            parts.append(clipState.label)
        }
        if line.isLead { parts.append("Lead") }
        if line.isModulationSource { parts.append("Modulation CC \(line.modulationCC) · Ch \(line.midiChannel + 1)") }
        if line.midiEnabled {
            parts.append(sharesChannel ? "Ch \(line.midiChannel + 1) (shared)" : "Ch \(line.midiChannel + 1)")
            parts.append(SampleLine.noteName(harmony.pitches(octave: line.octave)[0]))
            if line.keyCount != 0 { parts.append("\(harmony.resolvedKeyCount(line.keyCount)) keys") }
            if line.triggerMode == .singleShot { parts.append("Single Shot") }
            if line.isMonophonic { parts.append("Mono") }
        }
        if line.visibility <= 0.01 { parts.append("Hidden") }
        if line.samplesOtherLines { parts.append("Samples lines") }
        return parts.joined(separator: " · ")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            destinationControl
            if line.destination.usesNotes {
                noteControls
                if line.destination == .vital {
                    instrumentControls
                }
            } else {
                clipControls
            }
            Divider()
            visibilityControl
            Divider()
            sourceControls
            Button("Delete line", role: .destructive, action: delete)
        }
    }

    /// Note/CC controls shared by the MIDI and hosted-Vital destinations. A
    /// hosted instrument always generates notes; MIDI has an explicit toggle.
    @ViewBuilder
    private var noteControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if line.destination == .midi {
                Toggle("Generate MIDI notes", isOn: $line.midiEnabled)
            }
            if line.midiEnabled {
                AdaptiveFlowLayout(horizontalSpacing: 10) {
                    octaveControl
                    keysControl
                    channelControl
                    triggerModeControl
                    if line.triggerMode == .rhythm {
                        rhythmControl
                    }
                }
                Toggle("Lead instrument", isOn: Binding(get: { line.isLead }, set: { setLead($0) }))
                    .help("Transposes every other line by this line's active scale degree")
                Toggle("Mono (one note)", isOn: $line.isMonophonic)
                    .help("Sound at most one note at a time. A sounding segment is held while it stays lit; otherwise the brightest lit segment wins.")
            }
            Toggle("Modulation source", isOn: Binding(get: { line.isModulationSource }, set: { setModulation($0) }))
                .help("Drive a MIDI CC from this line's lit position along A→B. Several lines can do this at once, each with its own CC; the line stops generating notes.")
            if line.isModulationSource {
                AdaptiveFlowLayout(horizontalSpacing: 10) {
                    Picker("Channel", selection: channelBinding) {
                        ForEach(0..<16, id: \.self) { channel in
                            Text("Ch \(channel + 1)").tag(channel)
                        }
                    }
                    .frame(width: 118)
                    .help("Channel the modulation CC is sent on")
                    HStack(spacing: 6) {
                        Text("CC")
                        TextField("CC", value: modulationCCBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 52)
                        Stepper("CC", value: modulationCCBinding, in: 0...127)
                            .labelsHidden()
                        Button("Test CC", action: testCC)
                            .help("Send this CC at mid value so a synth's MIDI learn can bind it")
                    }
                }
                if line.modulationCC == 7 {
                    Text("CC7 is channel volume; pick another number for a parameter.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("Notes from this line are suppressed while it is a modulation source; turn this off to resume them.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Vital slot controls: pick a saved sound, or open/capture the live one. The
    /// full editor lives in a separate window.
    private var instrumentControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Picker("Sound", selection: instrumentSelection) {
                    Text("None").tag(UUID?.none)
                    ForEach(availableSounds) { sound in
                        Text(sound.name).tag(UUID?.some(sound.id))
                    }
                }
                .labelsHidden()
                .frame(minWidth: 150, maxWidth: 240)
                Spacer(minLength: 4)
                if let message = instrumentStatus?.message {
                    Text(message).font(.caption).foregroundStyle(.red)
                } else if instrumentStatus?.loaded == true {
                    Text("Loaded").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Loading…").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Button("Open Vital", action: openInstrument)
                Button(line.instrument == nil ? "Capture sound" : "Recapture", action: captureInstrument)
                if line.instrument != nil {
                    Button("Clear", action: clearInstrument)
                }
            }
            Text("Pick a saved sound, or shape one in Vital and Capture it. Saving the Kinetic preset also recaptures every Vital line. Up to 3 Vital lines can sound at once.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Saved sounds plus the line's current one, so an older reference still
    /// shows its name even before it is captured into the catalog.
    private var availableSounds: [AUStateReference] {
        var sounds = savedSounds
        if let current = line.instrument, !sounds.contains(where: { $0.id == current.id }) {
            sounds.append(current)
        }
        return sounds
    }

    private var instrumentSelection: Binding<UUID?> {
        Binding(
            get: { line.instrument?.id },
            set: { id in
                if let id, let reference = availableSounds.first(where: { $0.id == id }) {
                    setInstrument(reference)
                } else {
                    setInstrument(nil)
                }
            }
        )
    }

    private var destinationControl: some View {
        Picker("Destination", selection: Binding(get: { line.destination }, set: setDestination)) {
            ForEach(SampleLineDestination.allCases) { destination in
                Text(destination.label).tag(destination)
            }
        }
        .frame(width: 168)
        .help(line.destination.detail)
    }

    /// Clip import and metadata for a Loop or One-shot line.
    @ViewBuilder
    private var clipControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(line.clip?.fileName ?? "No clip")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(line.clip == nil ? .secondary : .primary)
                Spacer(minLength: 4)
                Text(clipState.label)
                    .font(.caption)
                    .foregroundStyle(clipState == .missing ? Color.red : Color.secondary)
            }
            HStack(spacing: 8) {
                Button(line.clip == nil ? "Import…" : "Replace…", action: importClip)
                if line.clip != nil {
                    Button("Clear", action: clearClip)
                }
            }
            if let clip = line.clip {
                if line.destination == .loop {
                    AdaptiveFlowLayout(horizontalSpacing: 10) {
                        HStack(spacing: 6) {
                            Text("Source")
                            TextField("BPM", value: sourceBPMBinding, format: .number.precision(.fractionLength(0)))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 56)
                            Stepper("Source", value: sourceBPMBinding, in: 30...240, step: 1)
                                .labelsHidden()
                            Text("BPM")
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 6) {
                            Text("Length")
                            TextField("Beats", value: beatsBinding, format: .number.precision(.fractionLength(2)))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 56)
                            Stepper("Length", value: beatsBinding, in: 0.25...64, step: 0.25)
                                .labelsHidden()
                            Text("beats")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Start muted", isOn: Binding(get: { clip.startMuted }, set: setClipStartMuted))
                        .help("The loop stays silent until toggled on. Its playhead still starts on a bar line so it stays in phase.")
                }
                HStack(spacing: 6) {
                    Text("Level")
                    CommitSlider(value: Binding(get: { clip.level }, set: setClipLevel), range: 0...1)
                        .frame(maxWidth: 150)
                    Text("\(Int(clip.level * 100))%")
                        .monospacedDigit()
                        .frame(minWidth: 38, alignment: .trailing)
                }
                Text(line.destination == .loop
                     ? "Toggles on the next bar line and stretches to the preset BPM without changing pitch."
                     : "Fires when the line lights up; quantized to the 1/16 grid when Quantize is on.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sourceBPMBinding: Binding<Double> {
        Binding(get: { line.clip?.sourceBPM ?? 120 }, set: setClipSourceBPM)
    }

    private var beatsBinding: Binding<Double> {
        Binding(get: { line.clip?.beats ?? 4 }, set: setClipBeats)
    }

    private var sourceControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Sample other lines", isOn: $line.samplesOtherLines)
                .help("Sample the previous frame's composited line output instead of the live camera composite")
            if line.samplesOtherLines {
                HStack(spacing: 6) {
                    Text("Safe distance")
                    CommitSlider(value: $line.sampleSafeDistance, range: 0...32)
                    Text("\(Int(line.sampleSafeDistance)) px")
                        .monospacedDigit()
                        .frame(minWidth: 40, alignment: .trailing)
                }
                Text("Reads last frame's line output; a gap at least this wide keeps the line from sampling its own stream.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var triggerModeControl: some View {
        Picker("Mode", selection: $line.triggerMode) {
            ForEach(SampleTriggerMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .frame(width: 152)
        .help(line.triggerMode == .singleShot
              ? "Hold a note while the segment has pixels"
              : "Retrigger the note on each line tick")
    }

    private var channelBinding: Binding<Int> {
        Binding(
            get: { line.midiChannel },
            set: { setChannel($0) }
        )
    }

    private var modulationCCBinding: Binding<Int> {
        Binding(
            get: { line.modulationCC },
            set: { setModulationCC($0) }
        )
    }

    private var channelControl: some View {
        Picker("Channel", selection: channelBinding) {
            ForEach(0..<16, id: \.self) { channel in
                Text("Ch \(channel + 1)").tag(channel)
            }
        }
        .frame(width: 118)
    }

    private var visibilityControl: some View {
        HStack(spacing: 6) {
            Text("Visibility")
            CommitSlider(value: $line.visibility, range: 0...1)
            Text(line.visibility <= 0.01 ? "Hidden" : "\(Int(line.visibility * 100))%")
                .monospacedDigit()
                .foregroundStyle(line.visibility <= 0.01 ? .secondary : .primary)
                .frame(minWidth: 48, alignment: .trailing)
        }
    }

    /// Root and scale are global now; a line only picks its own register.
    private var octaveControl: some View {
        Picker("Octave", selection: $line.octave) {
            ForEach(allowedOctaves, id: \.self) { octave in
                Text("\(octave)").tag(octave)
            }
        }
        .frame(width: 100)
    }

    /// How many keys the line exposes: one or two for a tiny keyboard, or many
    /// more to cover several octaves. The list starts at 1 so the small sizes
    /// are one click away. 0 (untouched) follows the scale at one octave; once
    /// chosen it becomes a fixed count.
    private var keysControl: some View {
        Picker("Keys", selection: keysBinding) {
            ForEach(1...harmony.keyCapacity, id: \.self) { count in
                Text("\(count)").tag(count)
            }
        }
        .frame(width: 96)
        .help("How many keys (segments) this line exposes. 1–2 build a tiny keyboard; more keys climb into higher octaves, up to four octaves' worth.")
    }

    private var keysBinding: Binding<Int> {
        Binding(
            get: { harmony.resolvedKeyCount(line.keyCount) },
            set: { line.keyCount = $0 }
        )
    }

    private var rhythmControl: some View {
        Picker("Rhythm", selection: $line.rhythm) {
            ForEach([1, 2, 3, 4, 6, 8, 12, 16], id: \.self) { value in
                Text(rhythmLabel(value)).tag(value)
            }
        }
    }

    private func rhythmLabel(_ value: Int) -> String {
        switch value {
        case 1: "1/16"
        case 2: "1/8"
        case 4: "1/4"
        default: "\(value)/16"
        }
    }

    private func clampOctave() {
        if let last = allowedOctaves.last, line.octave > last { line.octave = last }
    }
}
