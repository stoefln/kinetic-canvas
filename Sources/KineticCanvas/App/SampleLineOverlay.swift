import SwiftUI

/// Drawn above the Metal view, after the source image has been sampled. Lines
/// render as one short segment per note position, tinted by their live
/// available/active/harmony-blocked state.
struct SampleLineOverlay: View {
    let lines: [SampleLine]
    let harmony: SampleHarmony
    let showNotes: Bool
    let transposeMode: SampleTransposeMode
    let visible: Bool
    @ObservedObject var state: SamplerStateStore

    var body: some View {
        Canvas { context, size in
            guard visible else { return }
            for line in lines.prefix(16) where line.visibility > 0.01 {
                draw(line, in: &context, size: size)
            }
        }
    }

    private func draw(_ line: SampleLine, in context: inout GraphicsContext, size: CGSize) {
        let a = CGPoint(x: line.ax * size.width, y: line.ay * size.height)
        let b = CGPoint(x: line.bx * size.width, y: line.by * size.height)
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length >= 2 else { return }
        let count = harmony.resolvedKeyCount(line.keyCount)
        let ux = dx / length, uy = dy / length
        let segmentLength = length / Double(count)
        let gap = min(max(segmentLength * 0.22, 2), 10)
        let inset = min(gap / 2, segmentLength * 0.4)
        for index in 0..<count {
            let start = Double(index) * segmentLength + inset
            let end = Double(index + 1) * segmentLength - inset
            guard end > start else { continue }
            let segmentState = harmony.segmentState(index: index, line: line, by: state.state)
            let opacity = harmony.segmentOpacity(segmentState, visibility: line.visibility)
            guard opacity > 0.001 else { continue }
            var path = Path()
            path.move(to: CGPoint(x: a.x + ux * start, y: a.y + uy * start))
            path.addLine(to: CGPoint(x: a.x + ux * end, y: a.y + uy * end))
            context.stroke(path, with: .color(line.segmentColor.opacity(opacity)),
                           lineWidth: segmentState == .active ? 4 : 3)
        }
        guard showNotes, segmentLength >= 36 else { return }
        let pitches = harmony.effectivePitches(octave: line.octave,
                                               keyCount: line.keyCount,
                                               leadDegree: state.state.leadDegree,
                                               mode: transposeMode,
                                               isLead: line.isLead)
        for (index, pitch) in pitches.enumerated() where index < count {
            let center = CGPoint(x: a.x + dx * (Double(index) + 0.5) / Double(count),
                                 y: a.y + dy * (Double(index) + 0.5) / Double(count) - 13)
            let label = Text(SampleLine.noteName(pitch))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(line.visibility))
            context.draw(label, at: center)
        }
    }
}
