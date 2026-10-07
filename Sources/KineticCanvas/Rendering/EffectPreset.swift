import Foundation

enum EffectKind: String, CaseIterable, Codable, Identifiable {
    case gradientOverlay
    case historicalTrail
    case liquidDistortion
    case liveVideoFill
    case flowers
    case skeleton
    case lines
    case lineSampler
    case particles
    case clapExplosions

    // Flowers remains decodable so presets saved by the previous build migrate
    // cleanly, but new effect menus expose only the generic Video Fill effect.
    static var allCases: [EffectKind] {
        [.gradientOverlay, .historicalTrail, .liquidDistortion, .liveVideoFill, .skeleton, .lines, .lineSampler, .particles, .clapExplosions]
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gradientOverlay: "Gradient Overlay"
        case .historicalTrail: "Historical Trail"
        case .liquidDistortion: "Liquid Distortion"
        case .liveVideoFill, .flowers: "Video Fill"
        case .skeleton: "Skeleton"
        case .lines: "Lines"
        case .lineSampler: "Line Sampler"
        case .particles: "Particles"
        case .clapExplosions: "Clap Explosions"
        }
    }

    var isVideoFill: Bool {
        self == .liveVideoFill || self == .flowers
    }
}

struct SampleLine: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var ax: Double
    var ay: Double
    var bx: Double
    var by: Double
    /// Zero-based MIDI channel on the Kinetic Canvas virtual source; independent of row order.
    var midiChannel = -1
    var midiEnabled = false
    /// When on, the line sounds at most one note at a time. The held segment is
    /// preferred while it stays lit; otherwise the brightest lit segment wins.
    var isMonophonic = false
    /// The lead line transposes every other line by its active scale degree.
    /// Only one line can be lead; the controller enforces uniqueness.
    var isLead = false
    /// The modulation-source line turns the brightness-weighted position of its
    /// lit pixels along A→B into a MIDI CC (for example a synth's filter
    /// cutoff). Several lines can be modulation sources at once, each driving
    /// its own `modulationCC` on its own `midiChannel`. A modulation line does
    /// not generate notes.
    var isModulationSource = false
    /// CC number a modulation-source line sends. 74 is the common
    /// filter-cutoff convention; the receiving synth binds it with MIDI learn.
    var modulationCC = 74
    // Root and scale are global now (`SampleHarmony`). These fields are kept
    // only so presets saved by earlier builds still decode; they are ignored.
    var scale: SampleScale = .chromatic
    var root = 0
    var octave = 4
    /// Number of keys this line exposes. 0 means "follow the global scale"
    /// (one full scale of keys); 1 or 2 build a tiny keyboard, and larger values
    /// climb into higher octaves up to four octaves' worth of keys.
    var keyCount = 0
    var rhythm = 2
    var triggerMode: SampleTriggerMode = .rhythm
    /// Visual opacity of the line on the output. 0 = hidden by default; the
    /// editing pad still draws a faint guide so the line stays draggable.
    var visibility = 0.0
    var showNotes = false
    /// When enabled, the line samples the previous frame's composited sampler
    /// output (the base image plus every other line) instead of the frozen
    /// pre-sampler composite. Order-independent, and a "safe distance" gap in
    /// the line's own output keeps it from sampling itself.
    var samplesOtherLines = false
    /// Extra gap, in pixels, left around a line that samples other lines so its
    /// own stream never overlaps its capture band. The renderer enlarges this
    /// automatically to cover the newest strip and sampling thickness.
    var sampleSafeDistance = 8.0
    /// Where this line sends its trigger: a host instrument (MIDI), a
    /// tempo-synced loop, or a one-shot hit. MIDI keeps the original behavior.
    var destination: SampleLineDestination = .midi
    /// Imported audio for a loop or one-shot destination. Ignored by MIDI.
    var clip: AudioClipReference? = nil
    /// Captured Vital AU sound for a `.vital` line. Ignored by other destinations.
    var instrument: AUStateReference? = nil
    /// Master switch for this line. When off, the line produces no notes, CC, or
    /// clip triggers and shows dimmed, but stays in the list and editable.
    var isEnabled = true

    /// A line needs the renderer's occupancy pass when it produces notes, drives
    /// a modulation CC, or triggers audio.
    var needsOccupancy: Bool {
        isEnabled && (midiEnabled || isModulationSource || destination != .midi)
    }

    init(ax: Double, ay: Double, bx: Double, by: Double, midiChannel: Int = -1,
         copying settings: SampleLine? = nil) {
        self.ax = ax; self.ay = ay; self.bx = bx; self.by = by
        self.midiChannel = midiChannel
        if let settings {
            midiEnabled = settings.midiEnabled
            isMonophonic = settings.isMonophonic
            modulationCC = settings.modulationCC
            scale = settings.scale
            root = settings.root
            octave = settings.octave
            keyCount = settings.keyCount
            rhythm = settings.rhythm
            triggerMode = settings.triggerMode
            visibility = settings.visibility
            showNotes = settings.showNotes
            samplesOtherLines = settings.samplesOtherLines
            sampleSafeDistance = settings.sampleSafeDistance
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, ax, ay, bx, by, midiChannel, midiEnabled, isMonophonic, isLead,
             isModulationSource, modulationCC,
             scale, root, octave, keyCount,
             rhythm, triggerMode, visibility, showNotes, samplesOtherLines, sampleSafeDistance,
             destination, clip, instrument, isEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        ax = try c.decode(Double.self, forKey: .ax)
        ay = try c.decode(Double.self, forKey: .ay)
        bx = try c.decode(Double.self, forKey: .bx)
        by = try c.decode(Double.self, forKey: .by)
        midiChannel = try c.decodeIfPresent(Int.self, forKey: .midiChannel) ?? -1
        midiEnabled = try c.decodeIfPresent(Bool.self, forKey: .midiEnabled) ?? false
        isMonophonic = try c.decodeIfPresent(Bool.self, forKey: .isMonophonic) ?? false
        isLead = try c.decodeIfPresent(Bool.self, forKey: .isLead) ?? false
        isModulationSource = try c.decodeIfPresent(Bool.self, forKey: .isModulationSource) ?? false
        modulationCC = min(127, max(0, try c.decodeIfPresent(Int.self, forKey: .modulationCC) ?? 74))
        scale = try c.decodeIfPresent(SampleScale.self, forKey: .scale) ?? .chromatic
        root = min(11, max(0, try c.decodeIfPresent(Int.self, forKey: .root) ?? 0))
        octave = min(9, max(-1, try c.decodeIfPresent(Int.self, forKey: .octave) ?? 4))
        keyCount = max(0, try c.decodeIfPresent(Int.self, forKey: .keyCount) ?? 0)
        // Keep the top key inside MIDI's range: the highest key sits a whole
        // number of octaves above the base octave.
        let perOctave = max(1, scale.offsets.count)
        let resolvedKeys = keyCount >= 1 ? min(keyCount, perOctave * 4) : perOctave
        let topOffset = (resolvedKeys - 1) / perOctave
        while (octave + topOffset + 1) * 12 + root + (scale.offsets.last ?? 0) > 127 { octave -= 1 }
        rhythm = min(16, max(1, try c.decodeIfPresent(Int.self, forKey: .rhythm) ?? 2))
        triggerMode = try c.decodeIfPresent(SampleTriggerMode.self, forKey: .triggerMode) ?? .rhythm
        visibility = min(1, max(0, try c.decodeIfPresent(Double.self, forKey: .visibility) ?? 0))
        showNotes = try c.decodeIfPresent(Bool.self, forKey: .showNotes) ?? false
        samplesOtherLines = try c.decodeIfPresent(Bool.self, forKey: .samplesOtherLines) ?? false
        sampleSafeDistance = min(64, max(0, try c.decodeIfPresent(Double.self, forKey: .sampleSafeDistance) ?? 8))
        destination = try c.decodeIfPresent(SampleLineDestination.self, forKey: .destination) ?? .midi
        clip = try c.decodeIfPresent(AudioClipReference.self, forKey: .clip)
        instrument = try c.decodeIfPresent(AUStateReference.self, forKey: .instrument)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    func sameGeometry(as other: SampleLine) -> Bool {
        ax == other.ax && ay == other.ay && bx == other.bx && by == other.by
    }

    /// Resolves missing/invalid routes (legacy lines decode to -1) and enforces
    /// a single lead. Explicit channels are preserved exactly, including several
    /// lines sharing one channel: sharing lets multiple lines drive the same
    /// host instrument, which is intentional. Only lines without a valid route
    /// are assigned, and each is spread onto the least-used channel so older
    /// presets open with the routes spread out rather than piled on channel 1.
    static func withStableChannels(_ input: [SampleLine]) -> [SampleLine] {
        var lines = Array(input.prefix(16))
        var usage: [Int: Int] = [:]
        for line in lines where (0..<16).contains(line.midiChannel) {
            usage[line.midiChannel, default: 0] += 1
        }
        for index in lines.indices where !(0..<16).contains(lines[index].midiChannel) {
            let channel = (0..<16).min { a, b in
                let ua = usage[a] ?? 0
                let ub = usage[b] ?? 0
                return ua == ub ? a < b : ua < ub
            } ?? 0
            lines[index].midiChannel = channel
            usage[channel, default: 0] += 1
        }
        // Only one line can be the lead; keep the first and clear the rest.
        var leadSeen = false
        for index in lines.indices {
            if lines[index].isLead {
                if leadSeen { lines[index].isLead = false } else { leadSeen = true }
            }
        }

        return lines
    }

    /// Assigns `id` to `channel` without disturbing other lines. Several lines may
    /// share a channel, so no swap or uniqueness repair happens here; the same
    /// pitch held by two lines on one channel is handled by the MIDI layer, which
    /// only releases it once the last holder lets go.
    static func assigningChannel(_ channel: Int, to id: UUID, in lines: [SampleLine]) -> [SampleLine] {
        guard (0..<16).contains(channel),
              let index = lines.firstIndex(where: { $0.id == id }),
              lines[index].midiChannel != channel else { return lines }
        var updated = lines
        updated[index].midiChannel = channel
        return updated
    }

    /// Returns `lines` with `id`'s modulation role set. Enabling also clears the
    /// lead role. Note settings (`midiEnabled`, octave, keys, rhythm, …) are
    /// intentionally preserved: the MIDI layer suppresses notes while a line is a
    /// modulation source, so toggling the role back off restores it unchanged
    /// instead of leaving `midiEnabled` stuck off.
    static func settingModulation(_ enabled: Bool, for id: UUID, in lines: [SampleLine]) -> [SampleLine] {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return lines }
        var updated = lines
        updated[index].isModulationSource = enabled
        if enabled { updated[index].isLead = false }
        return updated
    }

    static let noteClasses = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    static func noteName(_ pitch: Int) -> String {
        "\(noteClasses[pitch % 12])\(pitch / 12 - 1)"
    }
}

enum SampleScale: String, CaseIterable, Codable, Identifiable {
    case chromatic, major, naturalMinor, majorPentatonic, minorPentatonic, blues
    var id: String { rawValue }
    var label: String {
        switch self {
        case .chromatic: "Chromatic"
        case .major: "Major"
        case .naturalMinor: "Natural Minor"
        case .majorPentatonic: "Major Pentatonic"
        case .minorPentatonic: "Minor Pentatonic"
        case .blues: "Blues"
        }
    }
    var offsets: [Int] {
        switch self {
        case .chromatic: Array(0..<12)
        case .major: [0, 2, 4, 5, 7, 9, 11]
        case .naturalMinor: [0, 2, 3, 5, 7, 8, 10]
        case .majorPentatonic: [0, 2, 4, 7, 9]
        case .minorPentatonic: [0, 3, 5, 7, 10]
        case .blues: [0, 3, 5, 6, 7, 10]
        }
    }
}

/// How dissonant an interval is, ordered from most to least consonant.
enum IntervalTension: Int, Codable, Sendable {
    case consonant = 0
    case moderate = 1
    case tense = 2
}

/// How Line Sampler notes reach a host. Some DAWs will only let one track claim
/// a given MIDI input, so a shared port cannot drive several instruments.
enum SampleMIDIPortMode: String, CaseIterable, Codable, Identifiable, Sendable {
    /// One virtual port; the host routes lines by MIDI channel.
    case single
    /// One virtual port per line, so each host track picks its own device.
    case perLine

    var id: String { rawValue }
    var label: String { self == .single ? "Single port (channels)" : "Port per line" }
    var detail: String {
        self == .single
            ? "One Kinetic Canvas device; route by MIDI channel in the host"
            : "One Kinetic Canvas device per line; assign a different track input to each"
    }
}

/// How the lead line moves the other lines.
enum SampleTransposeMode: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Shift by scale steps, staying in the selected scale.
    case diatonic
    /// Shift by the exact semitone interval, parallel motion.
    case chromatic

    var id: String { rawValue }
    var label: String { self == .diatonic ? "Diatonic" : "Chromatic" }
    var detail: String {
        self == .diatonic ? "Scale steps — stays in key" : "Exact semitones — parallel motion"
    }
}

/// Global root/scale/tension shared by every Line Sampler line. Each line keeps
/// only its own register (octave), MIDI channel, rhythm, and visual settings.
struct SampleHarmony: Codable, Equatable, Sendable {
    var root = 0
    var scale: SampleScale = .chromatic
    /// 0 = only strongly consonant simultaneous intervals; 1 = everything allowed.
    var tension = 0.5

    /// Classifies the interval between two pitches, measured from the lower to
    /// the higher note and reduced to one octave. This keeps a perfect fourth
    /// (5) distinct from its inversion, the perfect fifth (7), matching the
    /// consonance table instead of folding them together.
    static func intervalTension(_ semitones: Int) -> IntervalTension {
        switch abs(semitones) % 12 {
        case 0, 3, 4, 7, 8, 9: return .consonant
        case 2, 5, 10: return .moderate
        default: return .tense  // 1, 6, 11
        }
    }

    /// Three equal slider zones: consonant, consonant + moderate, then all.
    var maximumAllowed: IntervalTension {
        tension < 1.0 / 3.0 ? .consonant : (tension < 2.0 / 3.0 ? .moderate : .tense)
    }

    var tensionLabel: String {
        switch maximumAllowed {
        case .consonant: "Consonant"
        case .moderate: "Balanced"
        case .tense: "Tension"
        }
    }

    /// A candidate is allowed only when every currently sounding note forms an
    /// interval at or below the tension threshold. Interval 0 is always allowed.
    func allows(_ candidate: Int, against activePitches: [Int]) -> Bool {
        let limit = maximumAllowed.rawValue
        for pitch in activePitches where Self.intervalTension(candidate - pitch).rawValue > limit {
            return false
        }
        return true
    }

    func pitches(octave: Int) -> [Int] {
        let base = (octave + 1) * 12 + root
        return scale.offsets.map { min(127, max(0, base + $0)) }
    }

    func basePitch(degree: Int, octave: Int) -> Int {
        let count = scale.offsets.count
        guard count > 0 else { return min(127, max(0, (octave + 1) * 12 + root)) }
        let d = min(max(degree, 0), count - 1)
        return min(127, max(0, (octave + 1) * 12 + root + scale.offsets[d]))
    }

    /// Pitch for a scale degree after the lead transposition. The lead itself
    /// and an inactive lead (`leadDegree == 0`) play the plain scale pitch.
    /// Diatonic shifts by scale steps and may cross octaves; chromatic shifts
    /// by exactly the lead degree's semitone offset.
    func effectivePitch(degree: Int, octave: Int, leadDegree: Int,
                        mode: SampleTransposeMode, isLead: Bool) -> Int {
        let count = scale.offsets.count
        guard !isLead, count > 0, leadDegree > 0, leadDegree < count else {
            return basePitch(degree: degree, octave: octave)
        }
        switch mode {
        case .chromatic:
            return min(127, max(0, basePitch(degree: degree, octave: octave) + scale.offsets[leadDegree]))
        case .diatonic:
            let d = min(max(degree, 0), count - 1) + leadDegree
            let pitch = (octave + 1) * 12 + root + (d / count) * 12 + scale.offsets[d % count]
            return min(127, max(0, pitch))
        }
    }

    /// Keys in a single octave: one per scale degree.
    var keysPerOctave: Int { max(1, scale.offsets.count) }

    /// Most keys a line may have: four octaves' worth. Bounded so the occupancy
    /// bitmask and GPU buffer stay fixed.
    var keyCapacity: Int { keysPerOctave * 4 }

    /// Resolves a line's requested key count. 0 means "follow the scale" (one
    /// full octave); anything else is clamped to 1...keyCapacity. This is what
    /// lets a line be a tiny one- or two-key keyboard or a multi-octave one.
    func resolvedKeyCount(_ requested: Int) -> Int {
        requested >= 1 ? min(requested, keyCapacity) : keysPerOctave
    }

    /// Highest octave offset touched by the first `count` keys (0-based), used to
    /// keep the top key inside MIDI's 0...127 range.
    func topOctaveOffset(forKeys count: Int) -> Int {
        max(0, (max(1, count) - 1) / keysPerOctave)
    }

    /// One pitch per key, running low to high. Keys wrap into the next octave
    /// once they pass the top scale degree, so a bigger key count keeps climbing
    /// instead of repeating the single register.
    func effectivePitches(octave: Int, keyCount: Int, leadDegree: Int,
                          mode: SampleTransposeMode, isLead: Bool) -> [Int] {
        let per = keysPerOctave
        let count = resolvedKeyCount(keyCount)
        return (0..<count).map { key in
            effectivePitch(degree: key % per, octave: octave + key / per,
                           leadDegree: leadDegree, mode: mode, isLead: isLead)
        }
    }

}

enum SampleDirection: String, CaseIterable, Codable, Identifiable {
    case both, left, right
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// How a line's occupied segments become notes.
enum SampleTriggerMode: String, CaseIterable, Codable, Identifiable {
    /// Retrigger the segment's note on every line tick (1/16 grid × rhythm).
    case rhythm
    /// Hold one note for as long as the segment keeps pixels.
    case singleShot

    var id: String { rawValue }
    var label: String {
        switch self {
        case .rhythm: "Rhythm"
        case .singleShot: "Single Shot"
        }
    }
}

struct VideoAsset: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
}

enum VideoFillTiming: String, CaseIterable, Codable, Identifiable {
    case live
    case historical

    var id: String { rawValue }
    var label: String { self == .live ? "Live" : "Historical" }
}

enum ParticleShape: UInt32, CaseIterable, Codable, Identifiable {
    case disc
    case ring
    case square
    case diamond
    case spark

    var id: UInt32 { rawValue }

    var label: String {
        switch self {
        case .disc: "Disc"
        case .ring: "Ring"
        case .square: "Square"
        case .diamond: "Diamond"
        case .spark: "Spark"
        }
    }
}

enum ParticleSpawnSource: String, CaseIterable, Codable, Identifiable {
    case limbs
    case shapeBorder

    var id: String { rawValue }
    var label: String { self == .limbs ? "Limbs" : "Shape Border" }
}

enum ParticleColorSource: String, CaseIterable, Codable, Identifiable {
    // Keep this raw value so presets saved with the earlier mode still load.
    case liveBelow
    case atSpawn

    var id: String { rawValue }
    var label: String {
        switch self {
        case .liveBelow: "White"
        case .atSpawn: "Color at spawn"
        }
    }
}

enum OverlayBlendMode: UInt32, CaseIterable, Codable, Identifiable {
    case normal
    case add
    case screen
    case lighten
    case multiply
    case subtract

    var id: UInt32 { rawValue }

    var label: String {
        switch self {
        case .normal: "Normal"
        case .add: "Add"
        case .screen: "Screen"
        case .lighten: "Lighten"
        case .multiply: "Multiply"
        case .subtract: "Subtract"
        }
    }
}

struct EffectPreset: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var effects: [EffectKind]
    // Missing in older presets, where every listed effect was enabled.
    var disabledEffects: Set<EffectKind>? = nil
    var effectBlendModes: [EffectKind: OverlayBlendMode]? = nil
    var thumbnailFileName: String? = nil

    var gradientStyle: GradientStyle
    var gradientOpacity: Double
    var gradientAngleDegrees: Double

    var cloneCount: Int
    var cloneRotationDegrees: Double
    var cloneScalePercent: Double
    var cloneTranslationXPercent: Double
    var cloneTranslationYPercent: Double
    var cloneOpacity: Double
    var cloneDecay: Double
    var trailSnapshotInterval: Double
    var trailLifetime: Double
    var trailBlendMode: TrailBlendMode

    var liquidStrength: Double
    var liquidScale: Double
    var liquidSpeed: Double

    // Optional so presets saved by older builds remain loadable.
    var videoOpacity: Double?
    var videoPlaybackRate: Double?
    var videoScale: Double?
    var videoFillTiming: VideoFillTiming?
    var videoAssetID: String?

    var skeletonOpacity: Double?
    var skeletonConfidence: Double?
    var linesOpacity: Double?
    var linesConfidence: Double?
    var linesConnections: Int?
    var linesGeometryOnly: Bool?
    var linesThickness: Double?
    var linesBlendMode: OverlayBlendMode?
    var sampleLines: [SampleLine]?
    var sampleHarmony: SampleHarmony? = nil
    var sampleTriggerThreshold: Double? = nil
    var sampleShowNotes: Bool? = nil
    var sampleQuantize: Bool? = nil
    var sampleMasterVolume: Double? = nil
    var sampleTransposeMode: SampleTransposeMode? = nil
    var sampleMIDIPortMode: SampleMIDIPortMode? = nil
    var sampleBPM: Double? = nil
    var sampleDirection: SampleDirection?
    var sampleSpeed: Double?
    var sampleCount: Int?
    // Legacy seconds-based value retained so older presets and app builds can
    // still exchange Line Sampler settings.
    var sampleLifetime: Double?
    var sampleThickness: Double?
    var sampleOpacity: Double?
    var sampleFade: Double?
    var sampleBlendMode: OverlayBlendMode?
    var particleRate: Double?
    var particleLifetime: Double?
    var particleSize: Double?
    var particleSizeScale: Double?
    var particleColorSource: ParticleColorSource?
    var particleMotionSize: Double?
    var particleSpeed: Double?
    var particleSpreadDegrees: Double?
    var particleGravity: Double?
    var particleDrag: Double?
    var particleEndSize: Double?
    var particleShape: ParticleShape?
    var particleMomentum: Double?
    var particleSpawnSource: ParticleSpawnSource?
    var particleBorderThreshold: Double?
    var clapExplosionSize: Double?
    var clapExplosionOpacity: Double?
    var clapExplosionBlendMode: OverlayBlendMode?
    /// How many bodies pose tracking follows at once. Global rather than
    /// per-effect; optional so presets saved before it existed still load.
    var maxPeople: Int? = nil
    /// Effects whose parameter panel is collapsed in the stack. Purely a view
    /// state, but stored with the preset so a saved look reopens compactly.
    /// Optional so presets saved before it existed still load.
    var collapsedEffects: Set<EffectKind>? = nil
}

extension EffectPreset {
    /// Destinations used by lines that produce audio (loops, one-shots, or a
    /// hosted instrument), in first-seen order. Empty for a MIDI-only preset.
    var audioDestinations: [SampleLineDestination] {
        var seen = Set<SampleLineDestination>()
        var result: [SampleLineDestination] = []
        for line in sampleLines ?? [] where line.destination != .midi {
            if seen.insert(line.destination).inserted { result.append(line.destination) }
        }
        return result
    }

    /// True when the preset routes any line to audio rather than a MIDI port.
    var hasAudioConfiguration: Bool { !audioDestinations.isEmpty }
}
