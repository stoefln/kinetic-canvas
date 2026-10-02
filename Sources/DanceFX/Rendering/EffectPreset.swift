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
    /// Zero-based MIDI channel on the DanceFX virtual source; independent of row order.
    var midiChannel = -1
    var midiEnabled = false
    var scale: SampleScale = .chromatic
    var root = 0
    var octave = 4
    var rhythm = 2
    var visibility = 1.0
    var showNotes = false

    init(ax: Double, ay: Double, bx: Double, by: Double, midiChannel: Int = -1,
         copying settings: SampleLine? = nil) {
        self.ax = ax; self.ay = ay; self.bx = bx; self.by = by
        self.midiChannel = midiChannel
        if let settings {
            midiEnabled = settings.midiEnabled
            scale = settings.scale
            root = settings.root
            octave = settings.octave
            rhythm = settings.rhythm
            visibility = settings.visibility
            showNotes = settings.showNotes
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, ax, ay, bx, by, midiChannel, midiEnabled, scale, root, octave, rhythm, visibility, showNotes
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
        scale = try c.decodeIfPresent(SampleScale.self, forKey: .scale) ?? .chromatic
        root = min(11, max(0, try c.decodeIfPresent(Int.self, forKey: .root) ?? 0))
        octave = min(9, max(-1, try c.decodeIfPresent(Int.self, forKey: .octave) ?? 4))
        while (octave + 1) * 12 + root + (scale.offsets.last ?? 0) > 127 { octave -= 1 }
        rhythm = min(16, max(1, try c.decodeIfPresent(Int.self, forKey: .rhythm) ?? 2))
        visibility = min(1, max(0, try c.decodeIfPresent(Double.self, forKey: .visibility) ?? 1))
        showNotes = try c.decodeIfPresent(Bool.self, forKey: .showNotes) ?? false
    }

    var pitches: [Int] {
        let base = (octave + 1) * 12 + root
        return scale.offsets.map { min(127, max(0, base + $0)) }
    }

    func sameGeometry(as other: SampleLine) -> Bool {
        ax == other.ax && ay == other.ay && bx == other.bx && by == other.by
    }

    /// Assign missing/duplicate legacy routes while preserving every valid unique route.
    static func withStableChannels(_ input: [SampleLine]) -> [SampleLine] {
        var lines = Array(input.prefix(16))
        var used = Set<Int>()
        for index in lines.indices {
            let channel = lines[index].midiChannel
            if (0..<16).contains(channel), !used.contains(channel) {
                used.insert(channel)
            } else {
                lines[index].midiChannel = -1
            }
        }
        for index in lines.indices where lines[index].midiChannel == -1 {
            guard let free = (0..<16).first(where: { !used.contains($0) }) else { break }
            lines[index].midiChannel = free
            used.insert(free)
        }
        return lines
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

enum SampleDirection: String, CaseIterable, Codable, Identifiable {
    case both, left, right
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
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
}
