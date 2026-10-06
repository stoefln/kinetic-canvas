import SwiftUI

/// A compact left-to-right layout that moves controls onto the next line when
/// the panel becomes narrow. Oversized children are capped to the available width.
struct AdaptiveFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 14
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let result = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        return CGSize(
            width: proposal.width ?? result.width,
            height: result.height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = arrange(subviews: subviews, width: bounds.width)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> LayoutResult {
        let finiteWidth = width.isFinite ? max(1, width) : .greatestFiniteMagnitude
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            // Measuring AppKit-backed controls first with an unspecified width and
            // then again with their reported width can trigger a recursive native
            // control layout cycle inside a ScrollView. A single finite proposal is
            // stable and still lets intrinsically sized controls remain compact.
            let size = subview.sizeThatFits(ProposedViewSize(width: finiteWidth, height: nil))
            let cappedSize = CGSize(width: min(size.width, finiteWidth), height: size.height)

            if x > 0, x + cappedSize.width > finiteWidth {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }

            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: cappedSize))
            x += cappedSize.width + horizontalSpacing
            rowHeight = max(rowHeight, cappedSize.height)
            usedWidth = max(usedWidth, max(0, x - horizontalSpacing))
        }

        return LayoutResult(
            width: width.isFinite ? min(usedWidth, finiteWidth) : usedWidth,
            height: subviews.isEmpty ? 0 : y + rowHeight,
            frames: frames
        )
    }
}

private struct LayoutResult {
    let width: CGFloat
    let height: CGFloat
    let frames: [CGRect]
}
