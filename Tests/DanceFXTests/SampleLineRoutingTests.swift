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
        previous.visibility = 0.25
        previous.showNotes = true
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
        XCTAssertEqual(next.visibility, previous.visibility)
        XCTAssertEqual(next.showNotes, previous.showNotes)
    }

    func testDuplicateRouteRepairsWithoutMovingValidRoutes() {
        let first = SampleLine(ax: 0, ay: 0, bx: 1, by: 1, midiChannel: 5)
        let duplicate = SampleLine(ax: 0, ay: 0, bx: 1, by: 1, midiChannel: 5)
        let existing = SampleLine(ax: 0, ay: 0, bx: 1, by: 1, midiChannel: 2)
        XCTAssertEqual(SampleLine.withStableChannels([first, duplicate, existing]).map(\.midiChannel), [5, 0, 2])
    }
}
