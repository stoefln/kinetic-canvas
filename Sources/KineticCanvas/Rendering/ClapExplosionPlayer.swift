import AVFoundation
import CoreVideo

/// Frame positions in Assets/explosions-2min.m4v (30 frames per second).
/// Consecutive claps use consecutive entries and wrap back to the first.
struct ExplosionSegment {
    let startFrame: Int
    let durationFrames: Int

    var startSeconds: Double { Double(startFrame) / 30 }
    var durationSeconds: Double { Double(durationFrames) / 30 }

    static let clips: [ExplosionSegment] = [
        .init(startFrame: 248, durationFrames: 240),
        .init(startFrame: 500, durationFrames: 240),
        .init(startFrame: 1002, durationFrames: 240),
        .init(startFrame: 1255, durationFrames: 240),
        .init(startFrame: 1505, durationFrames: 240)
    ]
}

final class ClapExplosionPlayer {
    let position: SIMD2<Float>
    let duration: Double
    private let player: AVPlayer
    private let output: AVPlayerItemVideoOutput
    private let lock = NSLock()
    private var startTime: CFTimeInterval?
    private var stopped = false
    var startedAt: CFTimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        return startTime
    }
    private var lastFrame: CVPixelBuffer?

    init(url: URL, segment: ExplosionSegment, position: SIMD2<Float>) {
        self.position = position
        duration = segment.durationSeconds
        output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ])
        let item = AVPlayerItem(url: url)
        item.add(output)
        player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .pause
        player.seek(
            to: CMTime(seconds: segment.startSeconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        startTime = CACurrentMediaTime()
        player.play()
    }

    func pixelBuffer(hostTime: CFTimeInterval) -> CVPixelBuffer? {
        guard startedAt != nil else { return nil }
        let itemTime = output.itemTime(forHostTime: hostTime)
        if output.hasNewPixelBuffer(forItemTime: itemTime),
           let frame = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
            lastFrame = frame
        }
        return lastFrame
    }

    func stop() {
        lock.lock()
        stopped = true
        player.pause()
        lock.unlock()
    }
}
