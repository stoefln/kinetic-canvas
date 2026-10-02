import SwiftUI

struct SampleLineSettings: View {
    @Binding var line: SampleLine
    let number: Int
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
            Text("Line \(number) · MIDI Ch \(line.midiChannel + 1) · \(line.scale.label) · \(SampleLine.noteName(line.pitches[0]))")
        }
        .onChange(of: line.scale) { _, _ in clampOctave() }
        .onChange(of: line.root) { _, _ in clampOctave() }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Generate MIDI notes", isOn: $line.midiEnabled)
            pitchControls
            rhythmControl
            HStack {
                Text("Visibility \(Int(line.visibility * 100))%")
                Slider(value: $line.visibility, in: 0...1)
            }
            Toggle("Show notes", isOn: $line.showNotes)
            Button("Delete line", role: .destructive, action: delete)
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
