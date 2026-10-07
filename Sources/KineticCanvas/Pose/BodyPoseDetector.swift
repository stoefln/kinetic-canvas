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
    /// Stable identifier for this tracked person. The detector keeps it across
    /// frames so per-person state (smoothing, velocity, hand contacts) survives.
    var id: Int
    var points: [PoseJoint: PosePoint]
    var sourceAspect: Float
    var handCenters: [SIMD2<Float>]
}

final class BodyPoseDetector: @unchecked Sendable {
    private struct Track {
        var id: Int
        var points: [PoseJoint: PosePoint]
        /// Coarse body centre used to associate an observation with the same
        /// person on the next frame.
        var anchor: SIMD2<Float>
    }

    private let request = VNDetectHumanBodyPoseRequest()
    private let handRequest: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2
        return request
    }()
    private var tracks: [Track] = []
    private var nextTrackID = 1
    private let smoothing: Float = 0.45
    private let minimumConfidence: Float = 0.20
    /// How far (normalized) a body centre may travel and still count as the same
    /// person. Beyond this a fresh track starts, so a fast entrance does not
    /// smear one body's smoothing across the frame. When two bodies cross they
    /// may still swap identities; that is an acceptable, deliberate artifact.
    private let matchDistance: Float = 0.25

    private let jointMapping: [(PoseJoint, VNHumanBodyPoseObservation.JointName)] = [
        (.nose, .nose), (.leftEye, .leftEye), (.rightEye, .rightEye),
        (.leftEar, .leftEar), (.rightEar, .rightEar), (.neck, .neck), (.root, .root),
        (.leftShoulder, .leftShoulder), (.leftElbow, .leftElbow), (.leftWrist, .leftWrist),
        (.rightShoulder, .rightShoulder), (.rightElbow, .rightElbow), (.rightWrist, .rightWrist),
        (.leftHip, .leftHip), (.leftKnee, .leftKnee), (.leftAnkle, .leftAnkle),
        (.rightHip, .rightHip), (.rightKnee, .rightKnee), (.rightAnkle, .rightAnkle)
    ]

    /// Detects up to `maxPeople` bodies. Vision orders observations by prominence,
    /// so the largest bodies win when more people are in frame than requested.
    func detect(pixelBuffer: CVPixelBuffer, includeHands: Bool, maxPeople: Int) throws -> [BodyPose] {
        let maxPeople = max(1, maxPeople)
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        if includeHands { handRequest.maximumHandCount = min(8, maxPeople * 2) }
        let requests: [VNRequest] = includeHands ? [request, handRequest] : [request]
        try handler.perform(requests)

        let observations = Array((request.results ?? []).prefix(maxPeople))
        guard !observations.isEmpty else {
            tracks.removeAll(keepingCapacity: true)
            return []
        }

        // Decode raw points first so association can run over the whole frame.
        var rawPeople: [(points: [PoseJoint: PosePoint], anchor: SIMD2<Float>)] = []
        rawPeople.reserveCapacity(observations.count)
        for observation in observations {
            let recognized = try observation.recognizedPoints(.all)
            var raw: [PoseJoint: PosePoint] = [:]
            var anchorSum = SIMD2<Float>.zero
            var anchorCount: Float = 0
            for (joint, visionName) in jointMapping {
                guard let point = recognized[visionName], point.confidence >= minimumConfidence else { continue }
                let position = SIMD2(Float(point.location.x), Float(point.location.y))
                raw[joint] = PosePoint(position: position, confidence: point.confidence)
                anchorSum += position
                anchorCount += 1
            }
            guard !raw.isEmpty else { continue }
            rawPeople.append((raw, anchorSum / max(1, anchorCount)))
        }

        // Greedy nearest-anchor association: each observation claims the closest
        // unused track, so a person keeps their smoothing state and id while they
        // move normally.
        var available = Array(tracks.indices)
        var previousPointsByPerson: [[PoseJoint: PosePoint]] = []
        var nextTracks: [Track] = []
        nextTracks.reserveCapacity(rawPeople.count)
        var poses: [BodyPose] = []
        poses.reserveCapacity(rawPeople.count)
        let sourceAspect = Float(CVPixelBufferGetWidth(pixelBuffer)) / Float(CVPixelBufferGetHeight(pixelBuffer))

        for person in rawPeople {
            var matched: Int?
            var bestDistance = Float.greatestFiniteMagnitude
            for index in available {
                let distance = simd_distance(tracks[index].anchor, person.anchor)
                if distance < bestDistance {
                    bestDistance = distance
                    matched = index
                }
            }
            let id: Int
            let previous: [PoseJoint: PosePoint]
            if let matched, bestDistance <= matchDistance {
                id = tracks[matched].id
                previous = tracks[matched].points
                available.removeAll { $0 == matched }
            } else {
                id = nextTrackID
                nextTrackID += 1
                previous = [:]
            }
            previousPointsByPerson.append(previous)

            var smoothed: [PoseJoint: PosePoint] = [:]
            for (joint, point) in person.points {
                if let prior = previous[joint] {
                    smoothed[joint] = PosePoint(
                        position: prior.position + (point.position - prior.position) * smoothing,
                        confidence: point.confidence
                    )
                } else {
                    smoothed[joint] = point
                }
            }
            nextTracks.append(Track(id: id, points: smoothed, anchor: person.anchor))
            poses.append(BodyPose(id: id, points: smoothed, sourceAspect: sourceAspect, handCenters: []))
        }

        if includeHands {
            try attachHands(to: &poses, previousPointsByPerson: previousPointsByPerson)
            for index in nextTracks.indices { nextTracks[index].points = poses[index].points }
        }

        tracks = nextTracks
        return poses
    }

    /// Associates each detected hand with the nearest tracked wrist so a hand is
    /// never attributed to the wrong body, then folds its fingertips into that
    /// person's points and records the palm centre for clap detection.
    private func attachHands(
        to poses: inout [BodyPose],
        previousPointsByPerson: [[PoseJoint: PosePoint]]
    ) throws {
        let palmJoints: [VNHumanHandPoseObservation.JointName] = [.indexMCP, .middleMCP, .ringMCP, .littleMCP]
        let leftTips: [(PoseJoint, VNHumanHandPoseObservation.JointName)] = [
            (.leftThumbTip, .thumbTip), (.leftIndexTip, .indexTip),
            (.leftMiddleTip, .middleTip), (.leftRingTip, .ringTip), (.leftLittleTip, .littleTip)
        ]
        let rightTips: [(PoseJoint, VNHumanHandPoseObservation.JointName)] = [
            (.rightThumbTip, .thumbTip), (.rightIndexTip, .indexTip),
            (.rightMiddleTip, .middleTip), (.rightRingTip, .ringTip), (.rightLittleTip, .littleTip)
        ]

        for hand in handRequest.results ?? [] {
            let handPoints = try hand.recognizedPoints(.all)
            guard let handWrist = handPoints[.wrist], handWrist.confidence >= minimumConfidence else { continue }
            let wristPosition = SIMD2(Float(handWrist.location.x), Float(handWrist.location.y))

            var ownerIndex: Int?
            var ownerIsLeft = true
            var bestDistance = Float.greatestFiniteMagnitude
            for (index, pose) in poses.enumerated() {
                let leftDistance = pose.points[.leftWrist].map { simd_distance($0.position, wristPosition) }
                    ?? .greatestFiniteMagnitude
                let rightDistance = pose.points[.rightWrist].map { simd_distance($0.position, wristPosition) }
                    ?? .greatestFiniteMagnitude
                if min(leftDistance, rightDistance) < bestDistance {
                    bestDistance = min(leftDistance, rightDistance)
                    ownerIndex = index
                    ownerIsLeft = leftDistance <= rightDistance
                }
            }
            // A single body with no detected wrist still owns the hand; with
            // several bodies and no wrist match, the hand is dropped rather than
            // guessed onto the wrong person.
            let owner = ownerIndex ?? (poses.count == 1 ? 0 : nil)
            guard let owner else { continue }

            let palmPoints = palmJoints.compactMap { name -> SIMD2<Float>? in
                guard let point = handPoints[name], point.confidence >= minimumConfidence else { return nil }
                return SIMD2(Float(point.location.x), Float(point.location.y))
            }
            let center = palmPoints.count >= 2
                ? palmPoints.reduce(.zero, +) / Float(palmPoints.count)
                : wristPosition
            poses[owner].handCenters.append(center)

            let previous = previousPointsByPerson[owner]
            for (joint, visionName) in (ownerIsLeft ? leftTips : rightTips) {
                guard let point = handPoints[visionName], point.confidence >= minimumConfidence else { continue }
                let detected = SIMD2(Float(point.location.x), Float(point.location.y))
                let position = previous[joint].map {
                    $0.position + (detected - $0.position) * smoothing
                } ?? detected
                poses[owner].points[joint] = PosePoint(position: position, confidence: point.confidence)
            }
        }
    }

    func reset() {
        tracks.removeAll(keepingCapacity: true)
        nextTrackID = 1
    }
}
