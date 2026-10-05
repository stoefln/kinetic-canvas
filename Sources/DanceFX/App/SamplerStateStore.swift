import Combine
import SwiftUI

/// Rolled-up note state for the sampler visuals: which segments of each line are
/// currently sounding, which scale degrees each line's harmony rules currently
/// block, and how far the lead is transposing everyone.
struct SamplerVisualState: Equatable, Sendable {
    /// One bit per key/segment, so a multi-octave line can hold more than 16.
    var activeMasks: [UUID: UInt64] = [:]
    var blockedMasks: [UUID: UInt64] = [:]
    /// The lead line's active scale degree, or 0 when it is silent.
    var leadDegree = 0
}

/// Holds the transient sampler note state off `AppController`'s published
/// surface, so a note change only re-renders the pad and projector overlay
/// instead of rebuilding the whole control panel.
@MainActor
final class SamplerStateStore: ObservableObject {
    @Published var state = SamplerVisualState()
}

enum SampleSegmentState {
    case available
    case active
    case blocked
}

extension SampleHarmony {
    /// Active wins over blocked: a note that is sounding stays active even if it
    /// has since become dissonant against a newer note. Lines that do not
    /// generate MIDI have no note state and always read as available.
    func segmentState(index: Int, line: SampleLine, by state: SamplerVisualState) -> SampleSegmentState {
        guard line.midiEnabled, index >= 0, index < 64 else { return .available }
        let bit = UInt64(1) << UInt64(index)
        if state.activeMasks[line.id].map({ $0 & bit != 0 }) ?? false { return .active }
        if (state.blockedMasks[line.id] ?? 0) & bit != 0 { return .blocked }
        return .available
    }

    /// Available, active, and blocked opacities relative to the line's own
    /// Visibility, so a faint line stays faint in every state.
    func segmentOpacity(_ state: SampleSegmentState, visibility: Double) -> Double {
        switch state {
        case .active: return visibility
        case .available: return visibility * 0.5
        case .blocked: return visibility * 0.3
        }
    }
}

extension SampleLine {
    /// The lead line is tinted dark purple, modulation sources light green, and
    /// every other line stays cyan.
    var segmentColor: Color {
        if isLead { return Color(red: 0.55, green: 0.16, blue: 0.78) }
        if isModulationSource { return Color(red: 0.55, green: 0.95, blue: 0.5) }
        return .cyan
    }
}
