import CoreVideo
import Foundation
import QuartzCore

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: video-fill-smoke <movie>")
}

let player = VideoFillPlayer(url: URL(fileURLWithPath: CommandLine.arguments[1]))
player.setActive(true, rate: 1)
let deadline = CACurrentMediaTime() + 5
var decodedFrame: CVPixelBuffer?
while CACurrentMediaTime() < deadline, decodedFrame == nil {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    decodedFrame = player.currentPixelBuffer(hostTime: CACurrentMediaTime())
}

guard let decodedFrame else {
    fatalError("No video frame was decoded within five seconds.")
}
print("Decoded video frame: \(CVPixelBufferGetWidth(decodedFrame))×\(CVPixelBufferGetHeight(decodedFrame))")
