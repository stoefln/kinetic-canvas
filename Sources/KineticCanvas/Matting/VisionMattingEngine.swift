import CoreMedia
import CoreVideo
import Vision

/// Native fallback used to validate capture, scheduling, and rendering before an
/// RVM `.mlpackage` is supplied. Vision is stateless, unlike the intended RVM engine.
final class VisionMattingEngine: MattingEngine, @unchecked Sendable {
    let displayName = "Apple Vision fallback"
    private let request: VNGeneratePersonSegmentationRequest
    private let handler = VNSequenceRequestHandler()

    init() {
        request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    func process(pixelBuffer: CVPixelBuffer, timestamp: CMTime) throws -> MattingResult {
        try handler.perform([request], on: pixelBuffer, orientation: .up)
        guard let alpha = request.results?.first?.pixelBuffer else {
            throw MattingError.noAlphaOutput
        }
        return MattingResult(source: pixelBuffer, alpha: alpha, foreground: nil, timestamp: timestamp)
    }

    func reset() {
        // Vision exposes no recurrent tensors. RVMEngine will clear r1...r4 here.
    }
}

enum MattingError: LocalizedError {
    case noAlphaOutput

    var errorDescription: String? {
        "The matting engine returned no alpha mask."
    }
}
