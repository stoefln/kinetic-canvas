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
