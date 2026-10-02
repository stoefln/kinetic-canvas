import SwiftUI

struct SampleLineSettings: View {
    @Binding var line: SampleLine
    let number: Int
    let setChannel: (Int) -> Void
    let delete: () -> Void
    @State private var expanded = false

    private var allowedOctaves: [Int] {
        (-1...9).filter { ($0 + 1) * 12 + line.root + (line.scale.offsets.last ?? 0) <= 127 }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            controls
                .padding(.top, 6)
        } label: {
            Text(summary)
                .foregroundStyle(line.visibility > 0.01 ? .primary : .secondary)
        }
        .padding(9)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .onChange(of: line.scale) { _, _ in clampOctave() }
        .onChange(of: line.root) { _, _ in clampOctave() }
    }

    private var summary: String {
        var parts = ["Line \(number)"]
        if line.midiEnabled {
            parts.append("Ch \(line.midiChannel + 1)")
            parts.append(line.scale.label)
            parts.append(SampleLine.noteName(line.pitches[0]))
            if line.triggerMode == .singleShot { parts.append("Single Shot") }
        }
        if line.visibility <= 0.01 { parts.append("Hidden") }
        return parts.joined(separator: " · ")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Generate MIDI notes", isOn: $line.midiEnabled)
            if line.midiEnabled {
                pitchControls
                HStack {
                    channelControl
                    triggerModeControl
                    if line.triggerMode == .rhythm {
                        rhythmControl
                    }
                }
            }
            Divider()
            visibilityControl
            Toggle("Show note names", isOn: $line.showNotes)
                .disabled(line.visibility <= 0.01)
            Button("Delete line", role: .destructive, action: delete)
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
            Slider(value: $line.visibility, in: 0...1)
            Text(line.visibility <= 0.01 ? "Hidden" : "\(Int(line.visibility * 100))%")
                .monospacedDigit()
                .foregroundStyle(line.visibility <= 0.01 ? .secondary : .primary)
                .frame(minWidth: 48, alignment: .trailing)
        }
    }

    private var pitchControls: some View {
        HStack {
            Picker("Scale", selection: $line.scale) {
                ForEach(SampleScale.allCases) { scale in Text(scale.label).tag(scale) }
            }
            Picker("Root", selection: $line.root) {
                ForEach(0..<12, id: \.self) { root in
                    Text(SampleLine.noteClasses[root]).tag(root)
                }
            }
            Picker("Octave", selection: $line.octave) {
                ForEach(allowedOctaves, id: \.self) { octave in
                    Text("\(octave)").tag(octave)
                }
            }
        }
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
