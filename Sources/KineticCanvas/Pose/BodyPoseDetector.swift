import CoreGraphics
import CoreVideo
import Vision
import simd

enum PoseJoint: String, CaseIterable, Sendable {
    case nose, leftEye, rightEye, leftEar, rightEar, neck, root
    case leftShoulder, leftElbow, leftWrist
    case rightShoulder, rightElbow, rightWrist
    case leftHip, leftKnee, leftAnkle
    case rightHip, rightKnee, rightAnkle
    case leftThumbTip, leftIndexTip, leftMiddleTip, leftRingTip, leftLittleTip
    case rightThumbTip, rightIndexTip, rightMiddleTip, rightRingTip, rightLittleTip
}

struct PosePoint: Sendable {
    /// Vision-normalized camera coordinates with a bottom-left origin.
    var position: SIMD2<Float>
    var confidence: Float
}

struct BodyPose: Sendable {
    var points: [PoseJoint: PosePoint]
    var sourceAspect: Float
    var handCenters: [SIMD2<Float>]
}

final class BodyPoseDetector: @unchecked Sendable {
    private let request = VNDetectHumanBodyPoseRequest()
    private let handRequest: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2
        return request
    }()
    private var smoothedPoints: [PoseJoint: PosePoint] = [:]
    private let smoothing: Float = 0.45
    private let minimumConfidence: Float = 0.20

    func detect(pixelBuffer: CVPixelBuffer, includeHands: Bool) throws -> BodyPose? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        let requests: [VNRequest] = includeHands ? [request, handRequest] : [request]
        try handler.perform(requests)
        guard let observation = request.results?.first else {
            smoothedPoints.removeAll(keepingCapacity: true)
            return nil
        }

        let recognized = try observation.recognizedPoints(.all)
        let mapping: [(PoseJoint, VNHumanBodyPoseObservation.JointName)] = [
            (.nose, .nose), (.leftEye, .leftEye), (.rightEye, .rightEye),
            (.leftEar, .leftEar), (.rightEar, .rightEar), (.neck, .neck), (.root, .root),
            (.leftShoulder, .leftShoulder), (.leftElbow, .leftElbow), (.leftWrist, .leftWrist),
            (.rightShoulder, .rightShoulder), (.rightElbow, .rightElbow), (.rightWrist, .rightWrist),
            (.leftHip, .leftHip), (.leftKnee, .leftKnee), (.leftAnkle, .leftAnkle),
            (.rightHip, .rightHip), (.rightKnee, .rightKnee), (.rightAnkle, .rightAnkle)
        ]

        var next: [PoseJoint: PosePoint] = [:]
        for (joint, visionName) in mapping {
            guard let point = recognized[visionName], point.confidence >= minimumConfidence else { continue }
            let detected = SIMD2(Float(point.location.x), Float(point.location.y))
            let position: SIMD2<Float>
            if let previous = smoothedPoints[joint] {
                position = previous.position + (detected - previous.position) * smoothing
            } else {
                position = detected
            }
            next[joint] = PosePoint(position: position, confidence: point.confidence)
        }

        var handCenters: [SIMD2<Float>] = []
        if includeHands {
            for hand in handRequest.results ?? [] {
                let handPoints = try hand.recognizedPoints(.all)
                guard let handWrist = handPoints[.wrist], handWrist.confidence >= minimumConfidence else { continue }
                let wristPosition = SIMD2(Float(handWrist.location.x), Float(handWrist.location.y))
                let palmJoints: [VNHumanHandPoseObservation.JointName] = [
                    .indexMCP, .middleMCP, .ringMCP, .littleMCP
                ]
                let palmPoints = palmJoints.compactMap { name -> SIMD2<Float>? in
                    guard let point = handPoints[name], point.confidence >= minimumConfidence else { return nil }
                    return SIMD2(Float(point.location.x), Float(point.location.y))
                }
                if palmPoints.count >= 2 {
                    handCenters.append(palmPoints.reduce(.zero, +) / Float(palmPoints.count))
                } else {
                    handCenters.append(wristPosition)
                }
                let leftDistance = next[.leftWrist].map { simd_distance($0.position, wristPosition) } ?? .greatestFiniteMagnitude
                let rightDistance = next[.rightWrist].map { simd_distance($0.position, wristPosition) } ?? .greatestFiniteMagnitude
                let tipMapping: [(PoseJoint, VNHumanHandPoseObservation.JointName)]
                if leftDistance <= rightDistance {
                    tipMapping = [
                        (.leftThumbTip, .thumbTip), (.leftIndexTip, .indexTip),
                        (.leftMiddleTip, .middleTip), (.leftRingTip, .ringTip),
                        (.leftLittleTip, .littleTip)
                    ]
                } else {
                    tipMapping = [
                        (.rightThumbTip, .thumbTip), (.rightIndexTip, .indexTip),
                        (.rightMiddleTip, .middleTip), (.rightRingTip, .ringTip),
                        (.rightLittleTip, .littleTip)
                    ]
                }
                for (joint, visionName) in tipMapping {
                    guard let point = handPoints[visionName], point.confidence >= minimumConfidence else { continue }
                    let detected = SIMD2(Float(point.location.x), Float(point.location.y))
                    let position = smoothedPoints[joint].map {
                        $0.position + (detected - $0.position) * smoothing
                    } ?? detected
                    next[joint] = PosePoint(position: position, confidence: point.confidence)
                }
            }
        }
        smoothedPoints = next
        guard !next.isEmpty else { return nil }
        return BodyPose(
            points: next,
            sourceAspect: Float(CVPixelBufferGetWidth(pixelBuffer)) / Float(CVPixelBufferGetHeight(pixelBuffer)),
            handCenters: handCenters
        )
    }

    func reset() {
        smoothedPoints.removeAll(keepingCapacity: true)
    }
}
