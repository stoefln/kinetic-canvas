import CoreMedia
import CoreVideo

struct MattingResult: @unchecked Sendable {
    let source: CVPixelBuffer
    let alpha: CVPixelBuffer
    let foreground: CVPixelBuffer?
    let timestamp: CMTime
}

protocol MattingEngine: AnyObject, Sendable {
    var displayName: String { get }
    func process(pixelBuffer: CVPixelBuffer, timestamp: CMTime) throws -> MattingResult
    func reset()
}
