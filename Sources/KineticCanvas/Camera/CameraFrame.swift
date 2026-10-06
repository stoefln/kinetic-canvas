import CoreMedia
import CoreVideo

struct CameraFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let timestamp: CMTime
    let hostTime: CFTimeInterval
}

struct CameraDescriptor: Identifiable, Hashable {
    let id: String
    let name: String
    let mirrorsOutput: Bool
}
