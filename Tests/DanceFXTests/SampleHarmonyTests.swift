import Foundation
import XCTest
@testable import DanceFX

final class SampleHarmonyTests: XCTestCase {
    func testIntervalClassification() {
        // Very consonant: unison/octave, thirds, perfect fifth, sixths.
        for interval in [0, 3, 4, 7, 8, 9, 12, 15] {
            XCTAssertEqual(SampleHarmony.intervalTension(interval), .consonant, "\(interval)")
        }
        // Moderately tense: perfect fourth, major second, minor seventh.
        for interval in [2, 5, 10, 14] {
            XCTAssertEqual(SampleHarmony.intervalTension(interval), .moderate, "\(interval)")
        }
        // Strongly tense: minor second, tritone, major seventh.
        for interval in [1, 6, 11] {
            XCTAssertEqual(SampleHarmony.intervalTension(interval), .tense, "\(interval)")
        }
        // Direction does not matter.
        XCTAssertEqual(SampleHarmony.intervalTension(-1), .tense)
        XCTAssertEqual(SampleHarmony.intervalTension(-7), .consonant)
    }

    func testTensionZones() {
        XCTAssertEqual(SampleHarmony(tension: 0).maximumAllowed, .consonant)
        XCTAssertEqual(SampleHarmony(tension: 0.2).maximumAllowed, .consonant)
        XCTAssertEqual(SampleHarmony(tension: 0.5).maximumAllowed, .moderate)
        XCTAssertEqual(SampleHarmony(tension: 0.66).maximumAllowed, .moderate)
        XCTAssertEqual(SampleHarmony(tension: 0.8).maximumAllowed, .tense)
        XCTAssertEqual(SampleHarmony(tension: 1).maximumAllowed, .tense)
    }

    func testGatingBlocksAgainstEveryActiveNote() {
        let consonant = SampleHarmony(root: 0, scale: .chromatic, tension: 0)
        // C4 active.
        XCTAssertTrue(consonant.allows(64, against: [60]))   // major third
        XCTAssertTrue(consonant.allows(60, against: [60]))   // unison / octave
        XCTAssertTrue(consonant.allows(72, against: [60]))   // octave
        XCTAssertFalse(consonant.allows(66, against: [60]))  // tritone
        XCTAssertFalse(consonant.allows(61, against: [60]))  // minor second
        // One bad interval is enough to block, even next to a good one.
        XCTAssertFalse(consonant.allows(61, against: [60, 64]))

        let moderate = SampleHarmony(root: 0, scale: .chromatic, tension: 0.5)
        XCTAssertTrue(moderate.allows(62, against: [60]))    // major second
        XCTAssertFalse(moderate.allows(61, against: [60]))   // still minor second

        let tense = SampleHarmony(root: 0, scale: .chromatic, tension: 1)
        XCTAssertTrue(tense.allows(61, against: [60]))
        XCTAssertTrue(tense.allows(66, against: [60]))
    }

    func testPitchesFollowGlobalRootAndScale() {
        let major = SampleHarmony(root: 0, scale: .major, tension: 0.5)
        XCTAssertEqual(major.pitches(octave: 4), [60, 62, 64, 65, 67, 69, 71])
        let gBlues = SampleHarmony(root: 7, scale: .blues, tension: 0.5)
        XCTAssertEqual(gBlues.pitches(octave: 4), [67, 70, 72, 73, 74, 77])
    }

    func testDiatonicTranspositionStaysInScale() {
        // C major, lead on E (degree 2). A line on C should move to E, D to F.
        let harmony = SampleHarmony(root: 0, scale: .major, tension: 0.5)
        XCTAssertEqual(harmony.effectivePitch(degree: 0, octave: 4, leadDegree: 2,
                                              mode: .diatonic, isLead: false), 64) // C -> E
        XCTAssertEqual(harmony.effectivePitch(degree: 1, octave: 4, leadDegree: 2,
                                              mode: .diatonic, isLead: false), 65) // D -> F
        // The top of the scale wraps into the next octave rather than clamping.
        XCTAssertEqual(harmony.effectivePitch(degree: 6, octave: 4, leadDegree: 2,
                                              mode: .diatonic, isLead: false), 74) // B -> D5
        // The lead itself never transposes, and neither does an inactive lead.
        XCTAssertEqual(harmony.effectivePitch(degree: 0, octave: 4, leadDegree: 2,
                                              mode: .diatonic, isLead: true), 60)
        XCTAssertEqual(harmony.effectivePitch(degree: 0, octave: 4, leadDegree: 0,
                                              mode: .diatonic, isLead: false), 60)
    }

    func testChromaticTranspositionShiftsBySemitones() {
        // C major, lead on E (offset +4). C -> E, D -> F# (leaves the scale).
        let harmony = SampleHarmony(root: 0, scale: .major, tension: 0.5)
        XCTAssertEqual(harmony.effectivePitch(degree: 0, octave: 4, leadDegree: 2,
                                              mode: .chromatic, isLead: false), 64)
        XCTAssertEqual(harmony.effectivePitch(degree: 1, octave: 4, leadDegree: 2,
                                              mode: .chromatic, isLead: false), 66)
    }

    func testKeyCountControlsKeyboardSize() {
        let chromatic = SampleHarmony(root: 0, scale: .chromatic)
        XCTAssertEqual(chromatic.resolvedKeyCount(0), 12)   // auto: one octave
        XCTAssertEqual(chromatic.resolvedKeyCount(1), 1)    // tiny keyboard
        XCTAssertEqual(chromatic.resolvedKeyCount(2), 2)
        XCTAssertEqual(chromatic.resolvedKeyCount(24), 24)  // two octaves
        XCTAssertEqual(chromatic.resolvedKeyCount(99), 48)  // clamped to four octaves
        XCTAssertEqual(chromatic.keyCapacity, 48)

        // The capacity follows the scale: a 7-note scale tops out at 28 keys.
        let major = SampleHarmony(root: 0, scale: .major)
        XCTAssertEqual(major.resolvedKeyCount(0), 7)
        XCTAssertEqual(major.resolvedKeyCount(99), 28)
    }

    func testKeysBeyondOneOctaveKeepClimbing() {
        let chromatic = SampleHarmony(root: 0, scale: .chromatic)
        let pitches = chromatic.effectivePitches(octave: 4, keyCount: 24, leadDegree: 0,
                                                 mode: .diatonic, isLead: true)
        XCTAssertEqual(pitches.count, 24)
        XCTAssertEqual(pitches[0], 60)   // C4
        XCTAssertEqual(pitches[11], 71)  // B4
        XCTAssertEqual(pitches[12], 72)  // C5, the next octave rather than a repeat
        XCTAssertEqual(pitches[23], 83)  // B5
    }

    func testOneOrTwoKeyKeyboard() {
        let major = SampleHarmony(root: 0, scale: .major)
        XCTAssertEqual(major.effectivePitches(octave: 4, keyCount: 1, leadDegree: 0,
                                              mode: .diatonic, isLead: true), [60])
        XCTAssertEqual(major.effectivePitches(octave: 4, keyCount: 2, leadDegree: 0,
                                              mode: .diatonic, isLead: true), [60, 62])
    }

    @MainActor
    func testSegmentStatePrecedence() {
        let harmony = SampleHarmony(root: 0, scale: .chromatic, tension: 0)
        var line = SampleLine(ax: 0, ay: 0, bx: 1, by: 1)
        line.midiEnabled = true
        let state = SamplerVisualState(activeMasks: [line.id: 0b10], blockedMasks: [line.id: 0b11])

        XCTAssertEqual(harmony.segmentState(index: 0, line: line, by: state), .blocked)
        // Active wins even when the degree is also blocked.
        XCTAssertEqual(harmony.segmentState(index: 1, line: line, by: state), .active)
        XCTAssertEqual(harmony.segmentState(index: 2, line: line, by: state), .available)

        // A line that does not generate MIDI never reads as active or blocked.
        line.midiEnabled = false
        XCTAssertEqual(harmony.segmentState(index: 1, line: line, by: state), .available)
        XCTAssertEqual(harmony.segmentState(index: 0, line: line, by: state), .available)
    }

    func testSegmentOpacityIsRelativeToVisibility() {
        let harmony = SampleHarmony()
        XCTAssertEqual(harmony.segmentOpacity(.active, visibility: 0.8), 0.8, accuracy: 1e-9)
        XCTAssertEqual(harmony.segmentOpacity(.available, visibility: 0.8), 0.4, accuracy: 1e-9)
        XCTAssertEqual(harmony.segmentOpacity(.blocked, visibility: 0.8), 0.24, accuracy: 1e-9)
        XCTAssertEqual(harmony.segmentOpacity(.active, visibility: 0.0), 0.0, accuracy: 1e-9)
    }
}
