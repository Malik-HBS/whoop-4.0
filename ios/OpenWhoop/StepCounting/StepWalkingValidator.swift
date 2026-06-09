import Foundation

struct StepWalkingValidator {
    let config: StepCounterConfig

    func validate(peaks: [StepPeak], signalEnergy: Double, windowStart: Date, windowEnd: Date) -> WalkingValidation {
        guard signalEnergy >= config.minWindowEnergy else {
            return WalkingValidation(acceptedPeaks: [], cadenceSpm: nil, confidence: .none)
        }
        let windowPeaks = coalesced(peaks.filter {
            $0.timestamp >= windowStart.addingTimeInterval(-config.validationWindow) && $0.timestamp <= windowEnd
        })
        let duration = max(windowEnd.timeIntervalSince(windowPeaks.first?.timestamp ?? windowStart), 0.001)
        if Double(windowPeaks.count) / duration > config.maxPeaksPerSecond {
            return WalkingValidation(acceptedPeaks: [], cadenceSpm: nil, confidence: .none)
        }
        guard windowPeaks.count >= config.minPeaksToStartWalking else {
            return WalkingValidation(acceptedPeaks: [], cadenceSpm: nil, confidence: .low)
        }

        let intervals = zip(windowPeaks.dropFirst(), windowPeaks).map {
            $0.0.timestamp.timeIntervalSince($0.1.timestamp)
        }.filter { $0 >= config.minStepInterval && $0 <= config.maxStepInterval }

        guard intervals.count >= config.minPeaksToStartWalking - 1 else {
            return WalkingValidation(acceptedPeaks: [], cadenceSpm: nil, confidence: .low)
        }

        let meanInterval = intervals.reduce(0, +) / Double(intervals.count)
        let cadence = 60.0 / meanInterval
        guard cadence >= config.minCadenceSpm, cadence <= config.maxCadenceSpm else {
            return WalkingValidation(acceptedPeaks: [], cadenceSpm: cadence, confidence: .none)
        }

        let intervalStd = StepSignalFilter.standardDeviation(intervals, mean: meanInterval)
        let cv = meanInterval > 0 ? intervalStd / meanInterval : Double.infinity
        let confidence: StepConfidence
        if windowPeaks.count >= 5, cv <= config.highConfidenceMaxIntervalCV {
            confidence = .high
        } else if cv <= config.mediumConfidenceMaxIntervalCV {
            confidence = .medium
        } else {
            confidence = .low
        }

        guard confidence == .medium || confidence == .high else {
            return WalkingValidation(acceptedPeaks: [], cadenceSpm: cadence, confidence: confidence)
        }
        return WalkingValidation(acceptedPeaks: windowPeaks, cadenceSpm: cadence, confidence: confidence)
    }

    private func coalesced(_ peaks: [StepPeak]) -> [StepPeak] {
        let sorted = peaks.sorted { $0.timestamp < $1.timestamp }
        var out: [StepPeak] = []
        for peak in sorted {
            guard let last = out.last else {
                out.append(peak)
                continue
            }
            if peak.timestamp.timeIntervalSince(last.timestamp) < config.minStepInterval {
                if peak.value > last.value {
                    out[out.count - 1] = peak
                }
            } else {
                out.append(peak)
            }
        }
        return out
    }
}
