import AVFoundation
import CoreVideo

final class VideoFillPlayer: @unchecked Sendable {
    private let player: AVPlayer
    private let output: AVPlayerItemVideoOutput
    private var endObserver: NSObjectProtocol?
    private let lock = NSLock()
    private var lastFrame: CVPixelBuffer?
    private var active = false
    private var playbackRate: Float = 1

    init(url: URL) {
        output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ])
        let item = AVPlayerItem(url: url)
        item.add(output)
        player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.player.seek(to: .zero)
            if self.active {
                self.player.playImmediately(atRate: max(0.05, self.playbackRate))
            }
        }
    }

    deinit {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    func setActive(_ active: Bool, rate: Float) {
        let rate = max(0.05, rate)
        let activeChanged = self.active != active
        let rateChanged = abs(playbackRate - rate) > 0.0001
        self.active = active
        playbackRate = rate
        if active {
            if activeChanged {
                player.playImmediately(atRate: rate)
            } else if rateChanged {
                player.rate = rate
            }
        } else if activeChanged {
            player.pause()
        }
    }

    func setRate(_ rate: Float) {
        let rate = max(0.05, rate)
        guard abs(playbackRate - rate) > 0.0001 else { return }
        playbackRate = rate
        if active { player.rate = rate }
    }

    func currentPixelBuffer(hostTime: CFTimeInterval) -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        let itemTime = output.itemTime(forHostTime: hostTime)
        if output.hasNewPixelBuffer(forItemTime: itemTime),
           let frame = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
            lastFrame = frame
            return frame
        }
        return lastFrame
    }
}
