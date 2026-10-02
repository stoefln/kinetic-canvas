import SwiftUI

/// Drawn above the Metal view, after the source image has been sampled.
struct SampleLineOverlay: View {
    let lines: [SampleLine]
    let visible: Bool

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
        let color = Color.cyan.opacity(line.visibility)
        var axis = Path()
        axis.move(to: a)
        axis.addLine(to: b)
        context.stroke(axis, with: .color(color), lineWidth: 2)
        let count = line.scale.offsets.count
        for boundary in 1..<count {
            let t = Double(boundary) / Double(count)
            let center = CGPoint(x: a.x + dx * t, y: a.y + dy * t)
            let nx = dy / length * 7, ny = -dx / length * 7
            var separator = Path()
            separator.move(to: CGPoint(x: center.x - nx, y: center.y - ny))
            separator.addLine(to: CGPoint(x: center.x + nx, y: center.y + ny))
            context.stroke(separator, with: .color(color), lineWidth: 2)
        }
        guard line.showNotes, length / Double(count) >= 36 else { return }
        for (index, pitch) in line.pitches.enumerated() {
            let t = (Double(index) + 0.5) / Double(count)
            let center = CGPoint(x: a.x + dx * t, y: a.y + dy * t - 13)
            let label = Text(SampleLine.noteName(pitch))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(line.visibility))
            context.draw(label, at: center)
        }
    }
}
