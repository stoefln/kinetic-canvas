import Foundation
import QuartzCore

struct PerformanceSnapshot {
    let captureFPS: Double
    let processedFPS: Double
    let inferenceMS: Double
    let renderMS: Double
    let latencyMS: Double
    let droppedFrames: Int

    static let zero = PerformanceSnapshot(
        captureFPS: 0, processedFPS: 0, inferenceMS: 0,
        renderMS: 0, latencyMS: 0, droppedFrames: 0
    )
}

final class PerformanceMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var captureTimes: [CFTimeInterval] = []
    private var processedTimes: [CFTimeInterval] = []
    private var inferenceSamples: [Double] = []
    private var renderSamples: [Double] = []
    private var latencySamples: [Double] = []
    private var dropped = 0
    private let window = 90

    func recordCapture() {
        lock.withLock {
            captureTimes.append(CACurrentMediaTime())
            trim(&captureTimes)
        }
    }

    func recordDroppedFrame() {
        lock.withLock { dropped += 1 }
    }

    func recordProcessed(inferenceMS: Double) {
        lock.withLock {
            processedTimes.append(CACurrentMediaTime())
            inferenceSamples.append(inferenceMS)
            trim(&processedTimes)
            trim(&inferenceSamples)
        }
    }

    func recordRendered(renderMS: Double, captureHostTime: CFTimeInterval) {
        lock.withLock {
            renderSamples.append(renderMS)
            latencySamples.append((CACurrentMediaTime() - captureHostTime) * 1_000)
            trim(&renderSamples)
            trim(&latencySamples)
        }
    }

    func snapshot() -> PerformanceSnapshot {
        lock.withLock {
            PerformanceSnapshot(
                captureFPS: fps(captureTimes),
                processedFPS: fps(processedTimes),
                inferenceMS: average(inferenceSamples),
                renderMS: average(renderSamples),
                latencyMS: average(latencySamples),
                droppedFrames: dropped
            )
        }
    }

    func reset() {
        lock.withLock {
            captureTimes.removeAll(keepingCapacity: true)
            processedTimes.removeAll(keepingCapacity: true)
            inferenceSamples.removeAll(keepingCapacity: true)
            renderSamples.removeAll(keepingCapacity: true)
            latencySamples.removeAll(keepingCapacity: true)
            dropped = 0
        }
    }

    private func trim<T>(_ values: inout [T]) {
        if values.count > window { values.removeFirst(values.count - window) }
    }

    private func average(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private func fps(_ times: [CFTimeInterval]) -> Double {
        guard times.count > 1, let first = times.first, let last = times.last, last > first else { return 0 }
        return Double(times.count - 1) / (last - first)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
