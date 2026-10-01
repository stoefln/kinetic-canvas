import CoreImage
import CoreML
import CoreMedia
import CoreVideo
import Foundation

final class RVMEngine: MattingEngine, @unchecked Sendable {
    let displayName: String

    private let model: MLModel
    private let state = RVMState()
    private let resizeContext = CIContext(options: [.cacheIntermediates: false])
    private let resizePool: CVPixelBufferPool
    private let inputWidth: Int
    private let inputHeight: Int

    static func bundled(profile: RVMProfile, computeUnits: MLComputeUnits = .all) throws -> RVMEngine {
        guard let url = Bundle.main.url(forResource: profile.modelResourceName, withExtension: "mlmodelc") else {
            throw RVMError.modelNotFound(profile.modelResourceName)
        }
        return try RVMEngine(modelURL: url, profile: profile, computeUnits: computeUnits)
    }

    init(modelURL: URL, profile: RVMProfile, computeUnits: MLComputeUnits) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        let loadedModel = try MLModel(contentsOf: modelURL, configuration: configuration)
        try Self.validate(model: loadedModel)
        guard let constraint = loadedModel.modelDescription.inputDescriptionsByName["src"]?.imageConstraint else {
            throw RVMError.incompatibleSignature
        }
        inputWidth = constraint.pixelsWide
        inputHeight = constraint.pixelsHigh
        resizePool = try Self.makeResizePool(width: inputWidth, height: inputHeight)
        model = loadedModel
        displayName = "RVM \(profile.label) FP16 (\(computeUnits.label))"
        print("DanceFX matting engine: \(displayName)")
        print("RVM input: \(inputWidth)×\(inputHeight)")
    }

    func process(pixelBuffer: CVPixelBuffer, timestamp: CMTime) throws -> MattingResult {
        let modelInput = try resizedForModelIfNeeded(pixelBuffer)

        var inputs = ["src": MLFeatureValue(pixelBuffer: modelInput)]
        state.addInputs(to: &inputs)
        let provider = try MLDictionaryFeatureProvider(dictionary: inputs)
        let output = try autoreleasepool { try model.prediction(from: provider) }

        guard let foreground = output.featureValue(for: "fgr")?.imageBufferValue,
              let alpha = output.featureValue(for: "pha")?.imageBufferValue else {
            throw RVMError.missingImageOutput
        }
        try state.update(from: output)

        return MattingResult(
            source: pixelBuffer,
            alpha: alpha,
            foreground: foreground,
            timestamp: timestamp
        )
    }

    func reset() {
        state.reset()
    }

    private static func validate(model: MLModel) throws {
        let description = model.modelDescription
        let requiredInputs = Set(["src", "r1i", "r2i", "r3i", "r4i"])
        let requiredOutputs = Set(["fgr", "pha", "r1o", "r2o", "r3o", "r4o"])
        guard requiredInputs.isSubset(of: Set(description.inputDescriptionsByName.keys)),
              requiredOutputs.isSubset(of: Set(description.outputDescriptionsByName.keys)) else {
            throw RVMError.incompatibleSignature
        }
    }

    private static func makeResizePool(width: Int, height: Int) throws -> CVPixelBufferPool {
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        guard status == kCVReturnSuccess, let pool else {
            throw RVMError.cannotCreateResizePool(status)
        }
        return pool
    }

    private func resizedForModelIfNeeded(_ source: CVPixelBuffer) throws -> CVPixelBuffer {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        guard width != inputWidth || height != inputHeight else { return source }

        var destination: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, resizePool, &destination)
        guard status == kCVReturnSuccess, let destination else {
            throw RVMError.cannotAllocateResizeBuffer(status)
        }

        let image = CIImage(cvPixelBuffer: source)
        let scaleX = Double(inputWidth) / image.extent.width
        let scaleY = Double(inputHeight) / image.extent.height
        let resized = image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        resizeContext.render(
            resized,
            to: destination,
            bounds: CGRect(x: 0, y: 0, width: inputWidth, height: inputHeight),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return destination
    }
}

enum RVMError: LocalizedError {
    case modelNotFound(String)
    case incompatibleSignature
    case missingImageOutput
    case missingRecurrentOutput
    case cannotCreateResizePool(CVReturn)
    case cannotAllocateResizeBuffer(CVReturn)

    var errorDescription: String? {
        switch self {
        case let .modelNotFound(name):
            "The compiled RVM model \(name) is not bundled in the app. Run scripts/build-app.sh."
        case .incompatibleSignature:
            "The bundled RVM model does not have the expected official input/output signature."
        case .missingImageOutput:
            "RVM returned no foreground or alpha image."
        case .missingRecurrentOutput:
            "RVM returned incomplete recurrent state."
        case let .cannotCreateResizePool(status):
            "Could not create the RVM resize pool (Core Video error \(status))."
        case let .cannotAllocateResizeBuffer(status):
            "Could not allocate an RVM resize buffer (Core Video error \(status))."
        }
    }
}

enum RVMProfile: Int, CaseIterable, Identifiable {
    case fast360p
    case quality720p

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .fast360p: "Fast 360p"
        case .quality720p: "Quality 720p"
        }
    }

    var modelResourceName: String {
        switch self {
        case .fast360p: "rvm_mobilenetv3_640x360_s0.5_fp16"
        case .quality720p: "rvm_mobilenetv3_1280x720_s0.375_fp16"
        }
    }
}

private extension MLComputeUnits {
    var label: String {
        switch self {
        case .cpuOnly: "CPU"
        case .cpuAndGPU: "CPU+GPU"
        case .all: "All"
        case .cpuAndNeuralEngine: "CPU+Neural Engine"
        @unknown default: "Unknown"
        }
    }
}
