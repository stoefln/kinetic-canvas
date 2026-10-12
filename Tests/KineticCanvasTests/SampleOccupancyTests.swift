import Foundation
import XCTest
@testable import KineticCanvas

final class SampleOccupancyTests: XCTestCase {
    func testThresholdGatesOccupancy() {
        XCTAssertFalse(LineSamplerMIDI.isOccupied(level: 0, threshold: 0.2))
        XCTAssertFalse(LineSamplerMIDI.isOccupied(level: 50, threshold: 0.2))  // 0.196
        XCTAssertTrue(LineSamplerMIDI.isOccupied(level: 51, threshold: 0.2))   // 0.200
        XCTAssertTrue(LineSamplerMIDI.isOccupied(level: 255, threshold: 0.2))

        // A higher threshold demands more lit pixels.
        XCTAssertFalse(LineSamplerMIDI.isOccupied(level: 128, threshold: 0.6))
        XCTAssertTrue(LineSamplerMIDI.isOccupied(level: 200, threshold: 0.6))
        XCTAssertTrue(LineSamplerMIDI.isOccupied(level: 3, threshold: 0.01))   // 0.012
    }

    func testVelocityTracksBrightness() {
        XCTAssertEqual(LineSamplerMIDI.velocity(forLevel: 0), 16)
        XCTAssertEqual(LineSamplerMIDI.velocity(forLevel: 255), 127)
        XCTAssertEqual(LineSamplerMIDI.velocity(forLevel: 128), 71)
        // Monotonic, and never zero so a sounding note is always audible.
        var previous = LineSamplerMIDI.velocity(forLevel: 0)
        for level in stride(from: 0, through: 255, by: 5) {
            let velocity = LineSamplerMIDI.velocity(forLevel: UInt8(level))
            XCTAssertGreaterThanOrEqual(velocity, previous)
            XCTAssertGreaterThanOrEqual(velocity, 1)
            previous = velocity
        }
    }

    func testModulationValueFollowsLitPosition() throws {
        // Nothing above the trigger threshold holds the parameter steady.
        XCTAssertNil(LineSamplerMIDI.modulationValue(levels: [UInt8](repeating: 0, count: 64), threshold: 0.2))
        XCTAssertNil(LineSamplerMIDI.modulationValue(levels: [UInt8](repeating: 40, count: 64), threshold: 0.2))

        var start = [UInt8](repeating: 0, count: 64)
        start[0] = 255
        var end = [UInt8](repeating: 0, count: 64)
        end[63] = 255
        XCTAssertEqual(try XCTUnwrap(LineSamplerMIDI.modulationValue(levels: start, threshold: 0.2)), 0)
        XCTAssertEqual(try XCTUnwrap(LineSamplerMIDI.modulationValue(levels: end, threshold: 0.2)), 127)
        // A uniformly lit line reads its center.
        XCTAssertEqual(try XCTUnwrap(LineSamplerMIDI.modulationValue(
            levels: [UInt8](repeating: 255, count: 64), threshold: 0.2)), 64)
    }

    func testControlSegmentMapsValueToScale() {
        XCTAssertEqual(LineSamplerMIDI.controlSegment(forValue: 0), 0)
        XCTAssertEqual(LineSamplerMIDI.controlSegment(forValue: 127), LineSamplerMIDI.maxSections - 1)
        // Monotonic and always inside the value scale.
        var previous = -1
        for value in UInt8(0)...UInt8(127) {
            let segment = LineSamplerMIDI.controlSegment(forValue: value)
            XCTAssertGreaterThanOrEqual(segment, previous)
            XCTAssertTrue((0..<LineSamplerMIDI.maxSections).contains(segment))
            previous = segment
        }
        // The midpoint of the value scale reads near the middle segment.
        XCTAssertEqual(LineSamplerMIDI.controlSegment(forValue: 64), LineSamplerMIDI.maxSections / 2)
    }

    func testArpPatternStepping() {
        let candidates = [0, 1, 2, 3]
        let up = (0..<8).map { LineSamplerMIDI.arpSegment(pattern: .up, counter: $0, candidates: candidates) }
        XCTAssertEqual(up, [0, 1, 2, 3, 0, 1, 2, 3])

        let down = (0..<6).map { LineSamplerMIDI.arpSegment(pattern: .down, counter: $0, candidates: candidates) }
        XCTAssertEqual(down, [3, 2, 1, 0, 3, 2])

        // Up-Down ping-pongs without repeating the endpoints.
        let upDown = (0..<8).map { LineSamplerMIDI.arpSegment(pattern: .upDown, counter: $0, candidates: candidates) }
        XCTAssertEqual(upDown, [0, 1, 2, 3, 2, 1, 0, 1])

        // Non-contiguous lit segments are stepped as-is, not enumerated.
        let sparse = [1, 4, 9]
        let sparseUp = (0..<4).map { LineSamplerMIDI.arpSegment(pattern: .up, counter: $0, candidates: sparse) }
        XCTAssertEqual(sparseUp, [1, 4, 9, 1])

        // One lit segment holds under every pattern.
        for counter in 0..<4 {
            for pattern in SampleArpPattern.allCases where pattern != .random {
                XCTAssertEqual(LineSamplerMIDI.arpSegment(pattern: pattern, counter: counter, candidates: [5]), 5)
            }
        }

        // Random always lands on a lit segment.
        for counter in 0..<20 {
            XCTAssertTrue(candidates.contains(
                LineSamplerMIDI.arpSegment(pattern: .random, counter: counter, candidates: candidates)))
        }
    }

    func testMonophonicSegmentPrefersHeldThenBrightest() {
        XCTAssertNil(LineSamplerMIDI.monophonicSegment(mask: 0, levels: nil, held: nil))

        let levels: [UInt8] = [10, 200, 40]
        let mask: UInt64 = (1 << 0) | (1 << 1) | (1 << 2)
        // No held voice: the brightest lit segment wins.
        XCTAssertEqual(LineSamplerMIDI.monophonicSegment(mask: mask, levels: levels, held: nil), 1)
        // A held segment that is still lit wins even when another is brighter.
        XCTAssertEqual(LineSamplerMIDI.monophonicSegment(mask: mask, levels: levels, held: 2), 2)
        // A held segment that went dark is ignored.
        XCTAssertEqual(LineSamplerMIDI.monophonicSegment(mask: 1 << 1, levels: levels, held: 2), 1)
        // Ties keep the lowest index.
        XCTAssertEqual(LineSamplerMIDI.monophonicSegment(
            mask: mask, levels: [100, 100, 100], held: nil), 0)
    }
}
