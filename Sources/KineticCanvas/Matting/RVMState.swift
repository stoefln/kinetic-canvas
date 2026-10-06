import CoreML

/// Explicit recurrent state for the official 720p RVM MobileNetV3 model.
///
/// Inputs are optional in the model specification. Omitting them on the first
/// frame instructs Core ML to use the model's all-zero initial states. Tensor
/// dimensions come directly from the selected fixed-resolution model.
final class RVMState {
    var r1: MLMultiArray?
    var r2: MLMultiArray?
    var r3: MLMultiArray?
    var r4: MLMultiArray?

    var isInitialized: Bool {
        r1 != nil && r2 != nil && r3 != nil && r4 != nil
    }

    func update(from features: MLFeatureProvider) throws {
        guard let r1 = features.featureValue(for: "r1o")?.multiArrayValue,
              let r2 = features.featureValue(for: "r2o")?.multiArrayValue,
              let r3 = features.featureValue(for: "r3o")?.multiArrayValue,
              let r4 = features.featureValue(for: "r4o")?.multiArrayValue else {
            throw RVMError.missingRecurrentOutput
        }
        self.r1 = r1
        self.r2 = r2
        self.r3 = r3
        self.r4 = r4
    }

    func addInputs(to dictionary: inout [String: MLFeatureValue]) {
        guard let r1, let r2, let r3, let r4 else { return }
        dictionary["r1i"] = MLFeatureValue(multiArray: r1)
        dictionary["r2i"] = MLFeatureValue(multiArray: r2)
        dictionary["r3i"] = MLFeatureValue(multiArray: r3)
        dictionary["r4i"] = MLFeatureValue(multiArray: r4)
    }

    func reset() {
        r1 = nil
        r2 = nil
        r3 = nil
        r4 = nil
    }
}
