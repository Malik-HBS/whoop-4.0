import Foundation
import WhoopProtocol

struct StepSignalFilter {
    let config: StepCounterConfig

    func normalizedMagnitudes(from samples: [AccelerometerSample]) -> [Double] {
        let rawMagnitudes = samples.map { sqrt($0.x * $0.x + $0.y * $0.y + $0.z * $0.z) }
        guard let median = Self.median(rawMagnitudes) else { return [] }
        let scale = median > 5 ? 1.0 / 9.80665 : 1.0
        return rawMagnitudes.map { $0 * scale }
    }

    func centeredAndSmoothed(magnitudes: [Double], timestamps: [Date]) -> [Double] {
        guard magnitudes.count == timestamps.count, !magnitudes.isEmpty else { return [] }
        let centered = subtractRollingMean(values: magnitudes, timestamps: timestamps, window: config.rollingMeanDuration)
        return movingAverage(centered, width: config.smoothingWidth)
    }

    func subtractRollingMean(values: [Double], timestamps: [Date], window: TimeInterval) -> [Double] {
        guard values.count == timestamps.count else { return [] }
        var output: [Double] = []
        output.reserveCapacity(values.count)

        var start = 0
        var sum = 0.0
        for i in values.indices {
            sum += values[i]
            while timestamps[i].timeIntervalSince(timestamps[start]) > window {
                sum -= values[start]
                start += 1
            }
            let count = Double(i - start + 1)
            output.append(values[i] - (sum / count))
        }
        return output
    }

    func movingAverage(_ values: [Double], width: Int) -> [Double] {
        guard width > 1, !values.isEmpty else { return values }
        let radius = width / 2
        return values.indices.map { i in
            let lo = max(values.startIndex, i - radius)
            let hi = min(values.index(before: values.endIndex), i + radius)
            let slice = values[lo...hi]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }

    static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    static func standardDeviation(_ values: [Double], mean: Double) -> Double {
        guard values.count > 1 else { return 0 }
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count - 1)
        return sqrt(variance)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}

