import SwiftUI

/// A slider that holds its value locally while the user drags and writes to the
/// binding only when the drag ends. A plain `Slider` bound to an `@Published`
/// property publishes an update per pointer event, which re-renders the whole
/// control panel and re-runs the effect pipeline; committing on release keeps
/// dragging smooth, since the app does not need to live-update every frame.
///
/// Keyboard and click-on-track adjustments do not report a drag phase, so those
/// apply immediately.
struct CommitSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    @State private var draft: Double?
    @State private var isEditing = false

    var body: some View {
        Slider(value: binding, in: range, onEditingChanged: editingChanged)
    }

    private var binding: Binding<Double> {
        Binding(
            get: { draft ?? value },
            set: { newValue in
                let clamped = min(range.upperBound, max(range.lowerBound, newValue))
                if isEditing {
                    draft = clamped
                } else {
                    draft = nil
                    value = clamped
                }
            }
        )
    }

    private func editingChanged(_ editing: Bool) {
        isEditing = editing
        if !editing, let draft {
            value = draft
            self.draft = nil
        }
    }
}
