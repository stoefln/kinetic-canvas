import CoreML
import CoreVideo
import Foundation
import QuartzCore

guard (2...3).contains(CommandLine.arguments.count) else {
    fatalError("Usage: swift scripts/smoke-rvm.swift /path/to/model.mlmodelc [all|cpu-gpu|cpu-ne]")
}

let modelURL = URL(fileURLWithPath: CommandLine.arguments[1])
let configuration = MLModelConfiguration()
let computeName = CommandLine.arguments.count == 3 ? CommandLine.arguments[2] : "all"
switch computeName {
case "all": configuration.computeUnits = .all
case "cpu-gpu": configuration.computeUnits = .cpuAndGPU
case "cpu-ne": configuration.computeUnits = .cpuAndNeuralEngine
default: fatalError("Unknown compute-unit choice: \(computeName)")
}
let model = try MLModel(contentsOf: modelURL, configuration: configuration)
guard let imageConstraint = model.modelDescription.inputDescriptionsByName["src"]?.imageConstraint else {
    fatalError("Model has no src image constraint")
}
let inputWidth = imageConstraint.pixelsWide
let inputHeight = imageConstraint.pixelsHigh

var buffer: CVPixelBuffer?
let status = CVPixelBufferCreate(
    kCFAllocatorDefault,
    inputWidth,
    inputHeight,
    kCVPixelFormatType_32BGRA,
    nil,
    &buffer
)
guard status == kCVReturnSuccess, let buffer else {
    fatalError("Could not allocate the smoke-test pixel buffer: \(status)")
}

CVPixelBufferLockBaseAddress(buffer, [])
if let base = CVPixelBufferGetBaseAddress(buffer) {
    memset(base, 0, CVPixelBufferGetDataSize(buffer))
}
CVPixelBufferUnlockBaseAddress(buffer, [])

func predict(_ inputs: [String: MLFeatureValue]) throws -> (MLFeatureProvider, Double) {
    let provider = try MLDictionaryFeatureProvider(dictionary: inputs)
    let start = CACurrentMediaTime()
    let output = try model.prediction(from: provider)
    return (output, (CACurrentMediaTime() - start) * 1_000)
}

let (first, firstMS) = try predict(["src": MLFeatureValue(pixelBuffer: buffer)])
guard let r1 = first.featureValue(for: "r1o")?.multiArrayValue,
      let r2 = first.featureValue(for: "r2o")?.multiArrayValue,
      let r3 = first.featureValue(for: "r3o")?.multiArrayValue,
      let r4 = first.featureValue(for: "r4o")?.multiArrayValue,
      let alpha = first.featureValue(for: "pha")?.imageBufferValue,
      let foreground = first.featureValue(for: "fgr")?.imageBufferValue else {
    fatalError("RVM did not produce its required image and recurrent outputs")
}

var recurrent = (r1, r2, r3, r4)
var recurrentTimes: [Double] = []
for _ in 0..<6 {
    let (output, milliseconds) = try predict([
        "src": MLFeatureValue(pixelBuffer: buffer),
        "r1i": MLFeatureValue(multiArray: recurrent.0),
        "r2i": MLFeatureValue(multiArray: recurrent.1),
        "r3i": MLFeatureValue(multiArray: recurrent.2),
        "r4i": MLFeatureValue(multiArray: recurrent.3)
    ])
    recurrent = (
        output.featureValue(for: "r1o")!.multiArrayValue!,
        output.featureValue(for: "r2o")!.multiArrayValue!,
        output.featureValue(for: "r3o")!.multiArrayValue!,
        output.featureValue(for: "r4o")!.multiArrayValue!
    )
    recurrentTimes.append(milliseconds)
}
let warmTimes = recurrentTimes.dropFirst()
let warmAverage = warmTimes.reduce(0, +) / Double(warmTimes.count)

print("RVM smoke test passed")
print("compute units: \(computeName)")
print("alpha: \(CVPixelBufferGetWidth(alpha))×\(CVPixelBufferGetHeight(alpha))")
print("pixel formats: fgr=\(CVPixelBufferGetPixelFormatType(foreground)), pha=\(CVPixelBufferGetPixelFormatType(alpha))")
print("r1: \(r1.shape), r2: \(r2.shape), r3: \(r3.shape), r4: \(r4.shape)")
print(String(format: "cold inference: %.1f ms; warm recurrent average: %.1f ms", firstMS, warmAverage))
