import Foundation
import XCTest
@testable import KineticCanvas

final class SampleLineRoutingTests: XCTestCase {
    func testLegacyLinesReceiveUniqueChannelsAndReorderingPreservesThem() throws {
        let first = SampleLine(ax: 0, ay: 0, bx: 0.5, by: 0.5)
        let second = SampleLine(ax: 0.1, ay: 0.1, bx: 0.6, by: 0.6)
        let legacy = try JSONEncoder().encode([first, second])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: legacy) as? [[String: Any]])
        for index in json.indices { json[index].removeValue(forKey: "midiChannel") }
        let restored = try JSONDecoder().decode([SampleLine].self, from: JSONSerialization.data(withJSONObject: json))
        let routed = SampleLine.withStableChannels(restored)
        XCTAssertEqual(routed.map(\.midiChannel), [0, 1])
        XCTAssertEqual(SampleLine.withStableChannels(routed.reversed()).map(\.midiChannel), [1, 0])
        let persisted = try JSONDecoder().decode([SampleLine].self, from: JSONEncoder().encode(routed))
        XCTAssertEqual(persisted.map(\.midiChannel), [0, 1])
    }

    func testNewLineCopiesSettingsButNotIdentityOrRoute() {
        var previous = SampleLine(ax: 0.1, ay: 0.2, bx: 0.3, by: 0.4, midiChannel: 4)
        previous.midiEnabled = true
        previous.scale = .blues
        previous.root = 7
        previous.octave = 3
        previous.rhythm = 3
        previous.triggerMode = .singleShot
        previous.visibility = 0.25
        previous.showNotes = true
        previous.samplesOtherLines = true
        previous.sampleSafeDistance = 14
        let next = SampleLine(ax: 0.5, ay: 0.6, bx: 0.7, by: 0.8,
                              midiChannel: 0, copying: previous)
        XCTAssertNotEqual(next.id, previous.id)
        XCTAssertEqual(next.midiChannel, 0)
        XCTAssertEqual(next.ax, 0.5)
        XCTAssertEqual(next.midiEnabled, previous.midiEnabled)
        XCTAssertEqual(next.scale, previous.scale)
        XCTAssertEqual(next.root, previous.root)
        XCTAssertEqual(next.octave, previous.octave)
        XCTAssertEqual(next.rhythm, previous.rhythm)
        XCTAssertEqual(next.triggerMode, previous.triggerMode)
        XCTAssertEqual(next.visibility, previous.visibility)
        XCTAssertEqual(next.showNotes, previous.showNotes)
        XCTAssertEqual(next.samplesOtherLines, previous.samplesOtherLines)
        XCTAssertEqual(next.sampleSafeDistance, previous.sampleSafeDistance)
    }

    func testLegacyLinesDefaultToLiveSourceAndSafeDistance() throws {
        let line = SampleLine(ax: 0, ay: 0, bx: 1, by: 1)
        XCTAssertFalse(line.samplesOtherLines)
        XCTAssertEqual(line.sampleSafeDistance, 8)

        let encoded = try JSONEncoder().encode([line])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        json[0].removeValue(forKey: "samplesOtherLines")
        json[0].removeValue(forKey: "sampleSafeDistance")
        let restored = try JSONDecoder().decode(
            [SampleLine].self,
            from: JSONSerialization.data(withJSONObject: json)
        )
        XCTAssertFalse(restored[0].samplesOtherLines)
        XCTAssertEqual(restored[0].sampleSafeDistance, 8)
    }

    func testDuplicateRoutesArePreserved() {
        let first = SampleLine(ax: 0, ay: 0, bx: 1, by: 1, midiChannel: 5)
        let duplicate = SampleLine(ax: 0, ay: 0, bx: 1, by: 1, midiChannel: 5)
        let existing = SampleLine(ax: 0, ay: 0, bx: 1, by: 1, midiChannel: 2)
        // Sharing a channel is legal, so explicit routes are never repaired away.
        XCTAssertEqual(SampleLine.withStableChannels([first, duplicate, existing]).map(\.midiChannel), [5, 5, 2])
    }

    func testMissingRoutesAreSpreadOntoLeastUsedChannels() {
        let a = SampleLine(ax: 0, ay: 0, bx: 1, by: 1, midiChannel: -1)
        let b = SampleLine(ax: 0, ay: 0.2, bx: 1, by: 1, midiChannel: -1)
        let c = SampleLine(ax: 0, ay: 0.4, bx: 1, by: 1, midiChannel: 4)
        let d = SampleLine(ax: 0, ay: 0.6, bx: 1, by: 1, midiChannel: -1)
        // First missing picks channel 0, then 1; the existing route on 4 is kept.
        XCTAssertEqual(SampleLine.withStableChannels([a, b, c, d]).map(\.midiChannel), [0, 1, 4, 2])
    }

    func testAssigningChannelAllowsSharingAndLeavesOtherLinesAlone() {
        let first = SampleLine(ax: 0, ay: 0, bx: 1, by: 1, midiChannel: 0)
        let second = SampleLine(ax: 0, ay: 1, bx: 1, by: 0, midiChannel: 1)
        let third = SampleLine(ax: 0, ay: 0.5, bx: 1, by: 0.5, midiChannel: 2)

        // Taking a channel that is already in use now shares it; nobody swaps.
        let shared = SampleLine.assigningChannel(0, to: third.id, in: [first, second, third])
        XCTAssertEqual(shared.map(\.midiChannel), [0, 1, 0])

        // An unused channel just moves.
        let moved = SampleLine.assigningChannel(7, to: third.id, in: [first, second, third])
        XCTAssertEqual(moved.map(\.midiChannel), [0, 1, 7])

        // Out-of-range or unchanged requests are ignored.
        XCTAssertEqual(SampleLine.assigningChannel(16, to: third.id, in: [first, second, third]).map(\.midiChannel), [0, 1, 2])
        XCTAssertEqual(SampleLine.assigningChannel(2, to: third.id, in: [first, second, third]).map(\.midiChannel), [0, 1, 2])
    }

    func testKeyCountDefaultsToAutoAndClampsOnDecode() throws {
        let line = SampleLine(ax: 0, ay: 0, bx: 1, by: 1)
        XCTAssertEqual(line.keyCount, 0)

        let encoded = try JSONEncoder().encode([line])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        json[0].removeValue(forKey: "keyCount")
        let legacy = try JSONDecoder().decode(
            [SampleLine].self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy[0].keyCount, 0)

        json[0]["keyCount"] = 2
        let small = try JSONDecoder().decode(
            [SampleLine].self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(small[0].keyCount, 2)

        json[0]["keyCount"] = -5
        let negative = try JSONDecoder().decode(
            [SampleLine].self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(negative[0].keyCount, 0)
    }

    func testLinesAreHiddenByDefaultAndInheritedOnCopy() throws {
        let line = SampleLine(ax: 0, ay: 0, bx: 1, by: 1)
        XCTAssertEqual(line.visibility, 0)

        let copied = SampleLine(ax: 0, ay: 0.5, bx: 1, by: 0.5, midiChannel: 1, copying: line)
        XCTAssertEqual(copied.visibility, 0)

        // Presets saved before the visibility field existed must also open hidden.
        let encoded = try JSONEncoder().encode([line])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        json[0].removeValue(forKey: "visibility")
        let restored = try JSONDecoder().decode(
            [SampleLine].self,
            from: JSONSerialization.data(withJSONObject: json)
        )
        XCTAssertEqual(restored[0].visibility, 0)
    }

    func testLegacyLinesDefaultToRhythmTrigger() throws {
        let line = SampleLine(ax: 0, ay: 0, bx: 1, by: 1)
        XCTAssertEqual(line.triggerMode, .rhythm)

        let encoded = try JSONEncoder().encode([line])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        json[0].removeValue(forKey: "triggerMode")
        let restored = try JSONDecoder().decode(
            [SampleLine].self,
            from: JSONSerialization.data(withJSONObject: json)
        )
        XCTAssertEqual(restored[0].triggerMode, .rhythm)
    }

    func testControlDestinationPreservesNoteSettings() {
        var line = SampleLine(ax: 0, ay: 0, bx: 1, by: 1)
        line.midiEnabled = true
        line.octave = 3
        line.keyCount = 5
        line.triggerMode = .singleShot

        let control = SampleLine.settingDestination(.control, for: line.id, in: [line])
        XCTAssertEqual(control[0].destination, .control)
        XCTAssertTrue(control[0].isControlLine)
        XCTAssertFalse(control[0].isLead)
        // The note settings survive the round trip, so switching back to MIDI
        // does not strip the Octave/Keys controls or silence the line.
        XCTAssertTrue(control[0].midiEnabled)
        XCTAssertEqual(control[0].octave, 3)
        XCTAssertEqual(control[0].keyCount, 5)
        XCTAssertEqual(control[0].triggerMode, .singleShot)

        let back = SampleLine.settingDestination(.midi, for: line.id, in: control)
        XCTAssertEqual(back[0].destination, .midi)
        XCTAssertFalse(back[0].isControlLine)
        XCTAssertTrue(back[0].midiEnabled)
        XCTAssertEqual(back[0].octave, 3)
        XCTAssertEqual(back[0].keyCount, 5)
    }

    func testStableChannelsPreservesMultipleControlLines() {
        var first = SampleLine(ax: 0, ay: 0, bx: 1, by: 1)
        var second = SampleLine(ax: 0, ay: 0.2, bx: 1, by: 1)
        first.destination = .control
        second.destination = .control
        XCTAssertEqual(SampleLine.withStableChannels([first, second]).map(\.destination), [.control, .control])
    }

    func testModulationCCDefaultsAndClampsOnDecode() throws {
        let line = SampleLine(ax: 0, ay: 0, bx: 1, by: 1)
        XCTAssertEqual(line.modulationCC, 74)

        let encoded = try JSONEncoder().encode([line])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        json[0].removeValue(forKey: "modulationCC")
        var restored = try JSONDecoder().decode(
            [SampleLine].self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored[0].modulationCC, 74)

        json[0]["modulationCC"] = 300
        restored = try JSONDecoder().decode(
            [SampleLine].self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored[0].modulationCC, 127)

        json[0]["modulationCC"] = -5
        restored = try JSONDecoder().decode(
            [SampleLine].self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored[0].modulationCC, 0)
    }

    func testLegacyModulationFlagMigratesToControlDestination() throws {
        let line = SampleLine(ax: 0, ay: 0, bx: 1, by: 1)
        XCTAssertEqual(line.destination, .midi)
        XCTAssertFalse(line.isControlLine)

        let encoded = try JSONEncoder().encode([line])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        // A preset saved before Control existed marked a MIDI line with a flag.
        json[0]["isModulationSource"] = true
        json[0].removeValue(forKey: "destination")
        let migrated = try JSONDecoder().decode(
            [SampleLine].self,
            from: JSONSerialization.data(withJSONObject: json)
        )
        XCTAssertEqual(migrated[0].destination, .control)
        XCTAssertTrue(migrated[0].isControlLine)

        // Without the legacy flag the line still opens as MIDI.
        json[0]["isModulationSource"] = false
        let plain = try JSONDecoder().decode(
            [SampleLine].self,
            from: JSONSerialization.data(withJSONObject: json)
        )
        XCTAssertEqual(plain[0].destination, .midi)
    }

    func testControlRoleIsNotInheritedOnCopy() {
        var source = SampleLine(ax: 0, ay: 0, bx: 1, by: 1)
        source.destination = .control
        let copy = SampleLine(ax: 0, ay: 0.5, bx: 1, by: 0.5, midiChannel: 1, copying: source)
        XCTAssertEqual(copy.destination, .midi, "a new line must not silently steal the role")
    }

    func testArpeggioDefaultsClampAndAreInheritedOnCopy() throws {
        let line = SampleLine(ax: 0, ay: 0, bx: 1, by: 1)
        XCTAssertEqual(line.arpPattern, .up)
        XCTAssertEqual(line.arpRate, 1)

        let encoded = try JSONEncoder().encode([line])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        json[0].removeValue(forKey: "arpPattern")
        json[0].removeValue(forKey: "arpRate")
        var restored = try JSONDecoder().decode(
            [SampleLine].self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored[0].arpPattern, .up)
        XCTAssertEqual(restored[0].arpRate, 1)

        json[0]["arpRate"] = 99
        restored = try JSONDecoder().decode(
            [SampleLine].self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored[0].arpRate, 16)

        json[0]["arpRate"] = 0
        restored = try JSONDecoder().decode(
            [SampleLine].self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored[0].arpRate, 1)

        // A new line copies the arp settings like the other note settings.
        var source = line
        source.triggerMode = .arpeggio
        source.arpPattern = .upDown
        source.arpRate = 4
        let copy = SampleLine(ax: 0, ay: 0.5, bx: 1, by: 0.5, midiChannel: 1, copying: source)
        XCTAssertEqual(copy.triggerMode, .arpeggio)
        XCTAssertEqual(copy.arpPattern, .upDown)
        XCTAssertEqual(copy.arpRate, 4)
    }

    func testNoteLengthDefaultsClampsAndIsInheritedOnCopy() throws {
        let line = SampleLine(ax: 0, ay: 0, bx: 1, by: 1)
        XCTAssertEqual(line.noteLength, 0.5)

        let encoded = try JSONEncoder().encode([line])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        json[0].removeValue(forKey: "noteLength")
        var restored = try JSONDecoder().decode(
            [SampleLine].self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored[0].noteLength, 0.5)

        json[0]["noteLength"] = 5
        restored = try JSONDecoder().decode(
            [SampleLine].self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored[0].noteLength, 1)

        json[0]["noteLength"] = 0
        restored = try JSONDecoder().decode(
            [SampleLine].self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored[0].noteLength, 0.05)

        // A new line inherits the length like the other note settings.
        var source = line
        source.noteLength = 0.25
        let copy = SampleLine(ax: 0, ay: 0.5, bx: 1, by: 0.5, midiChannel: 1, copying: source)
        XCTAssertEqual(copy.noteLength, 0.25)
    }

    func testMonophonicDefaultsOffAndIsInheritedOnCopy() throws {
        let line = SampleLine(ax: 0, ay: 0, bx: 1, by: 1)
        XCTAssertFalse(line.isMonophonic)

        var source = line
        source.isMonophonic = true
        let copy = SampleLine(ax: 0, ay: 0.5, bx: 1, by: 0.5, midiChannel: 1, copying: source)
        XCTAssertTrue(copy.isMonophonic)

        let encoded = try JSONEncoder().encode([line])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        json[0].removeValue(forKey: "isMonophonic")
        let restored = try JSONDecoder().decode(
            [SampleLine].self, from: JSONSerialization.data(withJSONObject: json)
        )
        XCTAssertFalse(restored[0].isMonophonic)
    }
}
