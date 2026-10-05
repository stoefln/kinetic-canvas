import SwiftUI

struct SampleLinePad: View {
    @ObservedObject var controller: AppController
    @ObservedObject var samplerState: SamplerStateStore
    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?
    @State private var endpointID: UUID?
    @State private var movingStart = false
    @State private var selectedID: UUID?

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                for (index, line) in controller.sampleLines.enumerated() {
                    let a = CGPoint(x: line.ax * size.width, y: line.ay * size.height)
                    let b = CGPoint(x: line.bx * size.width, y: line.by * size.height)
                    drawLine(a, b, line: line, label: "\(index + 1)", selected: selectedID == line.id, context: &context)
                }
                if let dragStart, let dragEnd, endpointID == nil {
                    drawDraft(dragStart, dragEnd, context: &context)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let point = clamped(value.location, size: geometry.size)
                    if dragStart == nil {
                        dragStart = clamped(value.startLocation, size: geometry.size)
                        if let hit = nearestEndpoint(to: value.startLocation, size: geometry.size) {
                            endpointID = hit.id
                            movingStart = hit.isStart
                            selectedID = hit.id
                        }
                    }
                    dragEnd = point
                    if let endpointID {
                        controller.moveSampleEndpoint(
                            id: endpointID, isStart: movingStart,
                            to: normalized(point, size: geometry.size)
                        )
                    }
                }
                .onEnded { value in
                    if endpointID == nil, let dragStart {
                        controller.addSampleLine(
                            from: normalized(dragStart, size: geometry.size),
                            to: normalized(clamped(value.location, size: geometry.size), size: geometry.size)
                        )
                    }
                    dragStart = nil
                    dragEnd = nil
                    endpointID = nil
                })
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .overlay(Rectangle().stroke(.gray.opacity(0.7), lineWidth: 1))
    }

    private func drawLine(_ a: CGPoint, _ b: CGPoint, line: SampleLine, label: String,
                          selected: Bool, context: inout GraphicsContext) {
        let visible = line.visibility > 0.01
        let harmony = controller.sampleHarmony
        if !visible {
            // Hidden lines still need an editable presence on the pad; the
            // projector overlay obeys visibility strictly and draws nothing.
            var path = Path()
            path.move(to: a)
            path.addLine(to: b)
            context.stroke(path, with: .color(.gray.opacity(selected ? 0.8 : 0.5)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        } else {
            drawSegments(a, b, line: line, harmony: harmony, width: 3, context: &context)
        }

        for point in [a, b] {
            context.fill(Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)),
                         with: .color(.white.opacity(selected ? 1 : max(0.35, line.visibility))))
        }
        if visible || selected {
            context.draw(Text("\(label) A").font(.caption).foregroundColor(.white),
                         at: CGPoint(x: a.x + 16, y: a.y - 10))
            context.draw(Text("B").font(.caption).foregroundColor(.white),
                         at: CGPoint(x: b.x + 12, y: b.y - 10))
        }
    }

    /// One short segment per note position, colored by its live state.
    private func drawSegments(_ a: CGPoint, _ b: CGPoint, line: SampleLine,
                              harmony: SampleHarmony, width: CGFloat,
                              context: inout GraphicsContext) {
        let count = harmony.resolvedKeyCount(line.keyCount)
        let dx = b.x - a.x, dy = b.y - a.y
        let length = max(1, hypot(dx, dy))
        let ux = dx / length, uy = dy / length
        let segmentLength = length / Double(count)
        let gap = min(max(segmentLength * 0.22, 2), 8)
        let inset = min(gap / 2, segmentLength * 0.4)
        for index in 0..<count {
            let start = Double(index) * segmentLength + inset
            let end = Double(index + 1) * segmentLength - inset
            guard end > start else { continue }
            let segmentState = harmony.segmentState(index: index, line: line, by: samplerState.state)
            let opacity = harmony.segmentOpacity(segmentState, visibility: line.visibility)
            guard opacity > 0.001 else { continue }
            var path = Path()
            path.move(to: CGPoint(x: a.x + ux * start, y: a.y + uy * start))
            path.addLine(to: CGPoint(x: a.x + ux * end, y: a.y + uy * end))
            let lineWidth = segmentState == .active ? width + 1 : width
            context.stroke(path, with: .color(line.segmentColor.opacity(opacity)), lineWidth: lineWidth)
        }
        guard controller.sampleShowNotes, segmentLength >= 33 else { return }
        let pitches = harmony.effectivePitches(octave: line.octave,
                                               keyCount: line.keyCount,
                                               leadDegree: samplerState.state.leadDegree,
                                               mode: controller.sampleTransposeMode,
                                               isLead: line.isLead)
        for (index, pitch) in pitches.enumerated() where index < count {
            let center = CGPoint(x: a.x + dx * (Double(index) + 0.5) / Double(count),
                                 y: a.y + dy * (Double(index) + 0.5) / Double(count) - 11)
            context.draw(Text(SampleLine.noteName(pitch))
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(line.visibility)), at: center)
        }
    }

    private func drawDraft(_ a: CGPoint, _ b: CGPoint, context: inout GraphicsContext) {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        context.stroke(path, with: .color(.cyan), lineWidth: 2)
    }

    private func nearestEndpoint(to point: CGPoint, size: CGSize) -> (id: UUID, isStart: Bool)? {
        for line in controller.sampleLines.reversed() {
            let a = CGPoint(x: line.ax * size.width, y: line.ay * size.height)
            let b = CGPoint(x: line.bx * size.width, y: line.by * size.height)
            if hypot(point.x - a.x, point.y - a.y) < 15 { return (line.id, true) }
            if hypot(point.x - b.x, point.y - b.y) < 15 { return (line.id, false) }
        }
        return nil
    }

    private func clamped(_ point: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), size.width), y: min(max(point.y, 0), size.height))
    }

    private func normalized(_ point: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: point.x / max(size.width, 1), y: point.y / max(size.height, 1))
    }
}
