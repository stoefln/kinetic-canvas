import Combine
import Foundation

/// Where a Line Sampler line sends its trigger.
///
/// `midi` keeps the original behavior. `loop` toggles a tempo-synced audio loop
/// on/off at the next bar. `oneShot` fires a single hit when the line lights up.
enum SampleLineDestination: String, CaseIterable, Codable, Identifiable, Sendable {
    case midi
    case loop
    case oneShot
    case vital

    var id: String { rawValue }

    var label: String {
        switch self {
        case .midi: "MIDI"
        case .loop: "Loop"
        case .oneShot: "One-shot"
        case .vital: "Vital AU"
        }
    }

    var detail: String {
        switch self {
        case .midi: "Send notes or CC to a host instrument"
        case .loop: "Toggle an imported loop at the next bar"
        case .oneShot: "Fire an imported hit when the line lights up"
        case .vital: "Play this line through a hosted Vital synth in the app"
        }
    }

    /// Notes, CC, and lead/modulation rules apply to MIDI and hosted-instrument
    /// destinations but not to clips.
    var usesNotes: Bool { self == .midi || self == .vital }
}

/// A reference to a user-supplied audio file plus the musical metadata needed to
/// keep a loop in sync with the shared transport.
///
/// The bookmark is preferred when resolving so the reference survives an app
/// restart and moving the file on the same machine; `path` and `fileName` are a
/// human-readable fallback. Files are referenced in place rather than copied, so
/// moving a preset to another machine requires re-importing its audio.
struct AudioClipReference: Codable, Equatable, Sendable {
    var fileName: String
    var path: String
    var bookmark: Data?
    /// Original tempo of a loop. Ignored by one-shots.
    var sourceBPM: Double = 120
    /// Musical length of a loop in beats. Ignored by one-shots.
    var beats: Double = 4
    /// Playback level 0...1.
    var level: Double = 1
    /// When true, a loop does not sound until it is toggled on. Its playhead
    /// still starts on a bar line, so it stays in phase with the other loops.
    var startMuted = false

    init(fileName: String, path: String, bookmark: Data?,
         sourceBPM: Double = 120, beats: Double = 4,
         level: Double = 1, startMuted: Bool = false) {
        self.fileName = fileName
        self.path = path
        self.bookmark = bookmark
        self.sourceBPM = min(240, max(30, sourceBPM))
        self.beats = min(64, max(0.25, beats))
        self.level = min(1, max(0, level))
        self.startMuted = startMuted
    }

    private enum CodingKeys: String, CodingKey {
        case fileName, path, bookmark, sourceBPM, beats, level, startMuted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName) ?? "Untitled"
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        bookmark = try c.decodeIfPresent(Data.self, forKey: .bookmark)
        sourceBPM = min(240, max(30, try c.decodeIfPresent(Double.self, forKey: .sourceBPM) ?? 120))
        beats = min(64, max(0.25, try c.decodeIfPresent(Double.self, forKey: .beats) ?? 4))
        level = min(1, max(0, try c.decodeIfPresent(Double.self, forKey: .level) ?? 1))
        startMuted = try c.decodeIfPresent(Bool.self, forKey: .startMuted) ?? false
    }

    /// Resolves the referenced file, preferring the bookmark.
    func resolveURL() -> URL? {
        if let bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [],
                                  relativeTo: nil, bookmarkDataIsStale: &stale) {
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        guard !path.isEmpty else { return nil }
        let fallback = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
    }

    static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}

/// UI-facing state for one line's clip.
enum ClipPlaybackState: String, Sendable, Equatable {
    case empty
    case missing
    case ready
    case queuedStart
    case playing
    case queuedStop
    case muted

    var label: String {
        switch self {
        case .empty: "No clip"
        case .missing: "File missing"
        case .ready: "Ready"
        case .queuedStart: "Queued"
        case .playing: "Playing"
        case .queuedStop: "Stopping"
        case .muted: "Muted"
        }
    }
}

/// A rising edge on a line that uses an audio destination. Emitted by the
/// Line Sampler clock, which already computes stabilized per-line occupancy.
struct LineAudioTrigger: Sendable {
    let lineID: UUID
    let destination: SampleLineDestination
    /// One-shots wait for the next sixteenth-note grid line when true.
    let quantize: Bool
}

/// A raw MIDI event a line wants delivered to a hosted instrument instead of a
/// Core MIDI port. `status` already includes the channel.
struct LineInstrumentEvent: Sendable {
    let lineID: UUID
    let status: UInt8
    let data1: UInt8
    let data2: UInt8
}

/// A captured Vital AU sound.
///
/// The large `fullState` dictionary lives in a versioned property-list sidecar
/// on disk; a preset only carries this lightweight reference plus the component
/// description so the sound can be found and restored on another run.
struct AUStateReference: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var componentName: String
    var componentManufacturer: String
    var componentType: UInt32
    var componentSubType: UInt32
    var componentManufacturerCode: UInt32
    var formatVersion: Int

    init(id: UUID = UUID(), name: String, componentName: String, componentManufacturer: String,
         componentType: UInt32, componentSubType: UInt32, componentManufacturerCode: UInt32,
         formatVersion: Int = 1) {
        self.id = id
        self.name = name
        self.componentName = componentName
        self.componentManufacturer = componentManufacturer
        self.componentType = componentType
        self.componentSubType = componentSubType
        self.componentManufacturerCode = componentManufacturerCode
        self.formatVersion = formatVersion
    }
}

/// Whether the Vital instrument can be hosted on this machine.
enum InstrumentAvailability: Equatable, Sendable {
    case searching
    case available(name: String)
    case unavailable(message: String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .searching: "Looking for Vital…"
        case .available(let name): name
        case .unavailable(let message): message
        }
    }
}

/// Holds per-line clip state off `AppController`'s published surface so a loop
/// state change only re-renders the clip controls, not the whole panel.
@MainActor
final class ClipStateStore: ObservableObject {
    @Published var states: [UUID: ClipPlaybackState] = [:]
}

/// Per-line hosted-instrument status.
struct InstrumentLineStatus: Sendable, Equatable {
    var soundName: String?
    var loaded = false
    var message: String?
}

/// Holds the Vital host's availability and per-line status off the main
/// published surface, so a slot loading or failing does not rebuild the panel.
@MainActor
final class InstrumentStateStore: ObservableObject {
    @Published var availability: InstrumentAvailability = .searching
    @Published var statuses: [UUID: InstrumentLineStatus] = [:]
    /// Every captured Vital sound on disk, for the per-line picker.
    @Published var sounds: [AUStateReference] = []
}
