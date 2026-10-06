import SwiftUI

struct SampleLineSettings: View {
    @Binding var line: SampleLine
    let number: Int
    /// Global root/scale/tension, shared by every line.
    let harmony: SampleHarmony
    /// True when another line also routes to this line's channel.
    let sharesChannel: Bool
    let setChannel: (Int) -> Void
    let setLead: (Bool) -> Void
    let setModulation: (Bool) -> Void
    let setModulationCC: (Int) -> Void
    let testCC: () -> Void
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
            // The whole header toggles, not just the disclosure arrow.
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(summary)
                        .foregroundStyle(line.visibility > 0.01 ? .primary : .secondary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
        .onChange(of: harmony) { _, _ in clampOctave() }
        .onChange(of: line.keyCount) { _, _ in clampOctave() }
        .onChange(of: line.midiEnabled) { _, enabled in
            if !enabled && line.isLead { setLead(false) }
        }
    }

    private var summary: String {
        var parts = ["Line \(number)"]
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
            Toggle("Generate MIDI notes", isOn: $line.midiEnabled)
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
            }
            Divider()
            visibilityControl
            Divider()
            sourceControls
            Button("Delete line", role: .destructive, action: delete)
        }
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
