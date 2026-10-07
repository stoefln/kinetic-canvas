import Foundation

/// The single source of musical time shared by the Line Sampler MIDI clock and
/// the clip audio engine.
///
/// The app is fixed at 4/4 and a sixteenth-note grid (the same grid the MIDI
/// note scheduler already used). Tempo changes are committed on a bar boundary:
/// between the request and that boundary the old tempo keeps running, so every
/// reader stays in phase and no reader has to allow for a mid-bar jump.
///
/// All access is guarded by a lock because the MIDI clock and the audio engine
/// read the transport from different queues.
final class MusicalTransport: @unchecked Sendable {
    /// Sixteenth notes per 4/4 bar.
    static let stepsPerBar: Int64 = 16
    /// Sixteenths per beat.
    static let stepsPerBeat: Int64 = 4

    private let lock = NSLock()
    private var _bpm: Double
    /// Uptime of `baseStep` in the current tempo segment.
    private var epoch: Double = 0
    private var baseStep: Int64 = 0
    private var pendingBPM: Double?
    private var pendingApplyTime: Double = .infinity
    private var _started = false

    init(bpm: Double = 120) {
        _bpm = min(240, max(30, bpm))
    }

    var isStarted: Bool {
        lock.lock(); defer { lock.unlock() }
        return _started
    }

    /// Begins musical time at `time` (a bar line). Called when the session
    /// starts so bar 0 is shared by MIDI and audio.
    func start(at time: Double) {
        lock.lock(); defer { lock.unlock() }
        epoch = time
        baseStep = 0
        _started = true
        pendingBPM = nil
        pendingApplyTime = .infinity
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        _started = false
        epoch = 0
        baseStep = 0
        pendingBPM = nil
        pendingApplyTime = .infinity
    }

    var bpm: Double {
        lock.lock(); defer { lock.unlock() }
        return _bpm
    }

    /// Seconds per sixteenth note at the active tempo.
    var secondsPerStep: Double {
        lock.lock(); defer { lock.unlock() }
        return 15 / _bpm
    }

    var secondsPerBar: Double {
        lock.lock(); defer { lock.unlock() }
        return 15 / _bpm * Double(Self.stepsPerBar)
    }

    /// Sixteenth-note index that contains `time`. 0 is the first grid line.
    func stepIndex(at time: Double) -> Int64 {
        lock.lock(); defer { lock.unlock() }
        guard _started else { return 0 }
        return baseStep + Int64(floor((time - epoch) / (15 / _bpm)))
    }

    /// Wall-clock time of a sixteenth-note index.
    func stepTime(_ index: Int64) -> Double {
        lock.lock(); defer { lock.unlock() }
        return epoch + Double(index - baseStep) * (15 / _bpm)
    }

    /// The next sixteenth-note grid line strictly after `time`.
    func nextStepTime(after time: Double) -> Double {
        lock.lock(); defer { lock.unlock() }
        guard _started else { return time }
        let span = 15 / _bpm
        let index = baseStep + Int64(floor((time - epoch) / span)) + 1
        return epoch + Double(index - baseStep) * span
    }

    /// The next bar line strictly after `time`.
    func nextBarTime(after time: Double) -> Double {
        lock.lock(); defer { lock.unlock() }
        guard _started else { return time }
        let span = 15 / _bpm
        let index = max(0, baseStep + Int64(floor((time - epoch) / span)))
        let bar = (index / Self.stepsPerBar + 1) * Self.stepsPerBar
        return epoch + Double(bar - baseStep) * span
    }

    /// Musical position in beats since the transport started.
    func beats(at time: Double) -> Double {
        Double(stepIndex(at: time)) / Double(Self.stepsPerBeat)
    }

    /// Requests a tempo change. While the transport is running the change is
    /// queued for the next bar line; before it starts the value applies at once.
    func requestBPM(_ newBPM: Double, at time: Double) {
        lock.lock(); defer { lock.unlock() }
        let clamped = min(240, max(30, newBPM))
        guard _started else {
            _bpm = clamped
            return
        }
        if abs(clamped - _bpm) < 0.0001 {
            pendingBPM = nil
            pendingApplyTime = .infinity
            return
        }
        let span = 15 / _bpm
        let index = max(0, baseStep + Int64(floor((time - epoch) / span)))
        let bar = (index / Self.stepsPerBar + 1) * Self.stepsPerBar
        pendingBPM = clamped
        pendingApplyTime = epoch + Double(bar - baseStep) * span
    }

    /// Commits a queued tempo change once its bar line has arrived. Safe to call
    /// from either reader; the first caller wins. Returns true when the active
    /// tempo actually changed.
    @discardableResult
    func commitPending(at time: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let pending = pendingBPM, _started, time >= pendingApplyTime else { return false }
        // Re-base at the boundary. It is a whole bar line, so phase is continuous.
        let span = 15 / _bpm
        baseStep = Int64(((pendingApplyTime - epoch) / span).rounded())
        epoch = pendingApplyTime
        _bpm = pending
        pendingBPM = nil
        pendingApplyTime = .infinity
        return true
    }
}
