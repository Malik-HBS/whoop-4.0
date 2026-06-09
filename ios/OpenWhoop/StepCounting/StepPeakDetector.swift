import Foundation

struct StepPeakDetector {
    let config: StepCounterConfig

    func dynamicThreshold(signal: [Double]) -> Double {
        let mean = StepSignalFilter.mean(signal)
        let std = StepSignalFilter.standardDeviation(signal, mean: mean)
        return max(mean + config.thresholdStdMultiplier * std, config.minThresholdG)
    }

    func detect(signal: [Double], timestamps: [Date], threshold: Double) -> [StepPeak] {
        rejectTooClose(localMaxima(signal: signal, timestamps: timestamps, threshold: threshold))
    }

    func localMaxima(signal: [Double], timestamps: [Date], threshold: Double) -> [StepPeak] {
        guard signal.count == timestamps.count, signal.count >= 3 else { return [] }
        var peaks: [StepPeak] = []
        for i in 1..<(signal.count - 1) {
            guard signal[i] > threshold,
                  signal[i] > signal[i - 1],
                  signal[i] >= signal[i + 1] else { continue }
            peaks.append(StepPeak(timestamp: timestamps[i], value: signal[i]))
        }
        return peaks
    }

    private func rejectTooClose(_ peaks: [StepPeak]) -> [StepPeak] {
        var accepted: [StepPeak] = []
        for peak in peaks {
            guard let last = accepted.last else {
                accepted.append(peak)
                continue
            }
            let interval = peak.timestamp.timeIntervalSince(last.timestamp)
            if interval >= config.minStepInterval {
                accepted.append(peak)
            } else if peak.value > last.value {
                accepted[accepted.count - 1] = peak
            }
        }
        return accepted
    }
}
