import CoreMIDI
import Foundation
import XCTest
@testable import KineticCanvas

final class LineSamplerMIDIPortTests: XCTestCase {
    func testPerLineModeKeepsChannelPortsAlive() {
        var midi: LineSamplerMIDI? = LineSamplerMIDI()
        let portName = "Kinetic Canvas Ch 1"
        // Another Kinetic Canvas instance can legally own the same-named source, so
        // compare against the baseline instead of asserting absence.
        let baseline = countSources(named: portName)

        var line = SampleLine(ax: 0, ay: 0, bx: 1, by: 1, midiChannel: 0)
        line.midiEnabled = true
        midi?.configure(lines: [line], harmony: SampleHarmony(), bpm: 120, threshold: 0.2,
                        quantize: true, transposeMode: .diatonic, portMode: .perLine, enabled: true)
        XCTAssertTrue(waitForSources(named: portName, count: baseline + 1),
                      "per-line mode should publish a port")

        // Removing the line must NOT tear the port down: hosts keep their track
        // input bound to the same virtual device across preset switches, so a
        // channel only disappears when the sampler itself is released.
        midi?.configure(lines: [], harmony: SampleHarmony(), bpm: 120, threshold: 0.2,
                        quantize: true, transposeMode: .diatonic, portMode: .perLine, enabled: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(countSources(named: portName), baseline + 1,
                       "a published channel port should stay available while the app runs")

        midi?.stop()
        midi = nil
        XCTAssertTrue(waitForSources(named: portName, count: baseline),
                      "ports should be released when the sampler is deallocated")
    }

    func testAnyLinePublishesItsChannelPort() {
        var midi: LineSamplerMIDI? = LineSamplerMIDI()
        let portName = "Kinetic Canvas Ch 3"
        let baseline = countSources(named: portName)

        // A line with MIDI off is still a device: a modulation line (or a line
        // the user has not enabled yet) must be bindable in a host that only
        // scans MIDI inputs at startup.
        let line = SampleLine(ax: 0, ay: 0, bx: 1, by: 1, midiChannel: 2)
        XCTAssertFalse(line.midiEnabled)
        midi?.configure(lines: [line], harmony: SampleHarmony(), bpm: 120, threshold: 0.2,
                        quantize: true, transposeMode: .diatonic, portMode: .perLine, enabled: true)
        XCTAssertTrue(waitForSources(named: portName, count: baseline + 1),
                      "a configured line should publish its channel port before it sends anything")

        midi?.stop()
        midi = nil
        XCTAssertTrue(waitForSources(named: portName, count: baseline))
    }

    private func waitForSources(named name: String, count: Int, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if countSources(named: name) == count { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return countSources(named: name) == count
    }

    private func countSources(named name: String) -> Int {
        (0..<MIDIGetNumberOfSources()).reduce(into: 0) { total, index in
            var display: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(MIDIGetSource(index), kMIDIPropertyDisplayName, &display)
            if (display?.takeRetainedValue() as String?) == name { total += 1 }
        }
    }
}
