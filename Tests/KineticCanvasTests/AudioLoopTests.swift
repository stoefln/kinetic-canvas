import Foundation
import XCTest
@testable import KineticCanvas

final class AudioLoopTests: XCTestCase {
    // MARK: - MusicalTransport

    func testTransportGridMatchesSixteenthNotes() {
        let transport = MusicalTransport(bpm: 120)
        transport.start(at: 0)
        XCTAssertEqual(transport.secondsPerStep, 0.125, accuracy: 1e-9)
        XCTAssertEqual(transport.stepIndex(at: 0), 0)
        XCTAssertEqual(transport.stepIndex(at: 0.13), 1)
        XCTAssertEqual(transport.stepIndex(at: 0.24), 1)
        XCTAssertEqual(transport.stepIndex(at: 0.25), 2)
        // A bar is sixteen sixteenths.
        XCTAssertEqual(transport.nextBarTime(after: 0.13), 2.0, accuracy: 1e-9)
        // Next grid line strictly after the current step.
        XCTAssertEqual(transport.nextStepTime(after: 0.13), 0.25, accuracy: 1e-9)
    }

    func testTempoChangeCommitsOnNextBarAndKeepsPhase() {
        let transport = MusicalTransport(bpm: 120)
        transport.start(at: 0)
        transport.requestBPM(60, at: 0)
        // The old tempo keeps running until the bar line at 2.0 s.
        XCTAssertEqual(transport.bpm, 120, accuracy: 1e-9)
        XCTAssertFalse(transport.commitPending(at: 1.9))
        XCTAssertEqual(transport.bpm, 120, accuracy: 1e-9)

        XCTAssertTrue(transport.commitPending(at: 2.0))
        XCTAssertEqual(transport.bpm, 60, accuracy: 1e-9)
        // Phase is continuous: the boundary is still sixteenth index 16.
        XCTAssertEqual(transport.stepIndex(at: 2.0), 16)
        XCTAssertEqual(transport.secondsPerStep, 0.25, accuracy: 1e-9)
        // The next bar is four seconds later at the new tempo.
        XCTAssertEqual(transport.nextBarTime(after: 2.0), 6.0, accuracy: 1e-9)
    }

    func testTempoChangeBeforeStartAppliesImmediately() {
        let transport = MusicalTransport(bpm: 120)
        transport.requestBPM(90, at: 0)
        XCTAssertEqual(transport.bpm, 90, accuracy: 1e-9)
    }

    // MARK: - Persistence

    func testAudioLineRoundTripsAndLegacyLinesDefaultToMIDI() throws {
        var line = SampleLine(ax: 0.1, ay: 0.2, bx: 0.8, by: 0.2, midiChannel: 2)
        line.destination = .loop
        line.clip = AudioClipReference(fileName: "break.wav", path: "/tmp/break.wav",
                                       bookmark: Data([1, 2, 3]), sourceBPM: 90, beats: 8,
                                       level: 0.5, startMuted: true)
        XCTAssertTrue(line.needsOccupancy)

        let restored = try JSONDecoder().decode(SampleLine.self, from: JSONEncoder().encode(line))
        XCTAssertEqual(restored.destination, .loop)
        XCTAssertEqual(restored.clip?.fileName, "break.wav")
        XCTAssertEqual(restored.clip?.sourceBPM, 90)
        XCTAssertEqual(restored.clip?.beats, 8)
        XCTAssertEqual(restored.clip?.level, 0.5)
        XCTAssertEqual(restored.clip?.startMuted, true)

        // A preset saved before audio existed decodes to a plain MIDI line.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(SampleLine(ax: 0, ay: 0, bx: 1, by: 1))) as? [String: Any])
        json.removeValue(forKey: "destination")
        json.removeValue(forKey: "clip")
        let legacy = try JSONDecoder().decode(
            SampleLine.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy.destination, .midi)
        XCTAssertNil(legacy.clip)
        XCTAssertFalse(legacy.needsOccupancy)
    }

    func testClipReferenceClampsValuesAndReportsMissingFile() {
        let clip = AudioClipReference(fileName: "x", path: "/does/not/exist.wav", bookmark: nil,
                                      sourceBPM: 5, beats: 999, level: 4)
        XCTAssertEqual(clip.sourceBPM, 30)
        XCTAssertEqual(clip.beats, 64)
        XCTAssertEqual(clip.level, 1)
        XCTAssertNil(clip.resolveURL())
    }

    // MARK: - Hosted Vital instrument

    func testDestinationNoteRouting() {
        XCTAssertTrue(SampleLineDestination.midi.usesNotes)
        XCTAssertTrue(SampleLineDestination.vital.usesNotes)
        XCTAssertFalse(SampleLineDestination.loop.usesNotes)
        XCTAssertFalse(SampleLineDestination.oneShot.usesNotes)
    }

    func testVitalLineRoundTripsStateReference() throws {
        var line = SampleLine(ax: 0.2, ay: 0.3, bx: 0.7, by: 0.3, midiChannel: 1)
        line.destination = .vital
        line.midiEnabled = true
        line.instrument = AUStateReference(name: "Warm Pad", componentName: "Vital",
                                           componentManufacturer: "Vital Audio",
                                           componentType: 0x61756d75, componentSubType: 0x56697461,
                                           componentManufacturerCode: 0x54797465)
        XCTAssertTrue(line.needsOccupancy)

        let restored = try JSONDecoder().decode(SampleLine.self, from: JSONEncoder().encode(line))
        XCTAssertEqual(restored.destination, .vital)
        XCTAssertEqual(restored.instrument?.name, "Warm Pad")
        XCTAssertEqual(restored.instrument?.componentSubType, 0x56697461)

        // A preset saved before hosting existed has no instrument reference.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(SampleLine(ax: 0, ay: 0, bx: 1, by: 1))) as? [String: Any])
        json.removeValue(forKey: "instrument")
        let legacy = try JSONDecoder().decode(
            SampleLine.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(legacy.instrument)
    }

    func testLineEnabledDefaultsTrueAndGatesOccupancy() throws {
        var line = SampleLine(ax: 0, ay: 0, bx: 1, by: 1, midiChannel: 0)
        line.midiEnabled = true
        XCTAssertTrue(line.isEnabled)
        XCTAssertTrue(line.needsOccupancy)
        line.isEnabled = false
        XCTAssertFalse(line.needsOccupancy)

        // A preset saved before the switch existed opens enabled.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(SampleLine(ax: 0, ay: 0, bx: 1, by: 1))) as? [String: Any])
        json.removeValue(forKey: "isEnabled")
        let legacy = try JSONDecoder().decode(
            SampleLine.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(legacy.isEnabled)
    }

    func testAUStateStoreRoundTripsPropertyList() throws {
        let id = UUID()
        let state: [String: Any] = [
            "version": 1,
            "name": "Test",
            "values": [1.0, 2.0, 3.0],
            "nested": ["enabled": true, "gain": 0.5]
        ]
        defer { AUStateStore.delete(id: id) }
        XCTAssertTrue(AUStateStore.save(state, id: id))
        let loaded = try XCTUnwrap(AUStateStore.load(id: id))
        XCTAssertEqual(loaded["name"] as? String, "Test")
        XCTAssertEqual(loaded["values"] as? [Double], [1.0, 2.0, 3.0])
        XCTAssertEqual((loaded["nested"] as? [String: Any])?["gain"] as? Double, 0.5)
    }
}
