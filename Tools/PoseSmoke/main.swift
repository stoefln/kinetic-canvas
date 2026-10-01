import CoreVideo
import Foundation
import QuartzCore

var buffer: CVPixelBuffer?
let status = CVPixelBufferCreate(
    nil,
    640,
    360,
    kCVPixelFormatType_32BGRA,
    [kCVPixelBufferMetalCompatibilityKey as String: true] as CFDictionary,
    &buffer
)
guard status == kCVReturnSuccess, let buffer else {
    fatalError("Could not create pose smoke-test buffer: \(status)")
}
CVPixelBufferLockBaseAddress(buffer, [])
if let address = CVPixelBufferGetBaseAddress(buffer) {
    memset(address, 0, CVPixelBufferGetDataSize(buffer))
}
CVPixelBufferUnlockBaseAddress(buffer, [])

let detector = BodyPoseDetector()
for iteration in 1...3 {
    let started = CACurrentMediaTime()
    _ = try detector.detect(pixelBuffer: buffer, includeHands: true)
    print(String(
        format: "Body + hand pose request %d completed in %.1f ms",
        iteration,
        (CACurrentMediaTime() - started) * 1_000
    ))
}
