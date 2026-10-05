import Foundation
import XCTest
@testable import DanceFX

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

    func testStableChannelsPreservesMultipleModulationSources() {
        var first = SampleLine(ax: 0, ay: 0, bx: 1, by: 1)
        var second = SampleLine(ax: 0, ay: 0.2, bx: 1, by: 1)
        first.isModulationSource = true
        second.isModulationSource = true
        XCTAssertEqual(SampleLine.withStableChannels([first, second]).map(\.isModulationSource), [true, true])
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

    func testLegacyLinesAreNotModulationSources() throws {
        let line = SampleLine(ax: 0, ay: 0, bx: 1, by: 1)
        XCTAssertFalse(line.isModulationSource)

        let encoded = try JSONEncoder().encode([line])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        json[0].removeValue(forKey: "isModulationSource")
        let restored = try JSONDecoder().decode(
            [SampleLine].self,
            from: JSONSerialization.data(withJSONObject: json)
        )
        XCTAssertFalse(restored[0].isModulationSource)
    }

    func testModulationRoleIsNotInheritedOnCopy() {
        var source = SampleLine(ax: 0, ay: 0, bx: 1, by: 1)
        source.isModulationSource = true
        let copy = SampleLine(ax: 0, ay: 0.5, bx: 1, by: 0.5, midiChannel: 1, copying: source)
        XCTAssertFalse(copy.isModulationSource, "a new line must not silently steal the role")
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
