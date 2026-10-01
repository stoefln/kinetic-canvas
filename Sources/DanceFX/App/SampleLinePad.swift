import SwiftUI

struct SampleLinePad: View {
    @ObservedObject var controller: AppController
    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?
    @State private var endpointID: UUID?
    @State private var movingStart = false

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                for (index, line) in controller.sampleLines.enumerated() {
                    let a = CGPoint(x: line.ax * size.width, y: line.ay * size.height)
                    let b = CGPoint(x: line.bx * size.width, y: line.by * size.height)
                    drawLine(a, b, label: "\(index + 1)", context: &context)
                }
                if let dragStart, let dragEnd, endpointID == nil {
                    drawLine(dragStart, dragEnd, label: "", context: &context)
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

    private func drawLine(_ a: CGPoint, _ b: CGPoint, label: String, context: inout GraphicsContext) {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        context.stroke(path, with: .color(.cyan), lineWidth: 2)
        for point in [a, b] {
            context.fill(Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)),
                         with: .color(.white))
        }
        context.draw(Text(label.isEmpty ? "A" : "\(label) A").font(.caption).foregroundColor(.white),
                     at: CGPoint(x: a.x + 16, y: a.y - 10))
        context.draw(Text("B").font(.caption).foregroundColor(.white),
                     at: CGPoint(x: b.x + 12, y: b.y - 10))
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
