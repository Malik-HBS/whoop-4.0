import Foundation
import WhoopProtocol

actor StepCountingProcessorActor {
    private let config: StepCounterConfig
    private let filter: StepSignalFilter
    private let detector: StepPeakDetector
    private let validator: StepWalkingValidator
    private var buffer: [AccelerometerSample] = []
    private var recentCandidatePeaks: [StepPeak] = []
    private var acceptedStepTimestamps: [Date] = []
    private var nextWindowStart: Date?

    init(config: StepCounterConfig = StepCounterConfig()) {
        self.config = config
        self.filter = StepSignalFilter(config: config)
        self.detector = StepPeakDetector(config: config)
        self.validator = StepWalkingValidator(config: config)
    }

    func ingest(_ samples: [AccelerometerSample]) async -> [StepDetectionResult] {
        guard !samples.isEmpty else { return [] }
        buffer.append(contentsOf: samples)
        buffer.sort { $0.timestamp < $1.timestamp }

        guard let first = buffer.first?.timestamp,
              let last = buffer.last?.timestamp else { return [] }
        if nextWindowStart == nil { nextWindowStart = first }

        var results: [StepDetectionResult] = []
        while let start = nextWindowStart {
            let end = start.addingTimeInterval(config.windowDuration)
            guard end <= last else { break }

            let windowSamples = buffer.filter { $0.timestamp >= start && $0.timestamp <= end }
            results.append(processWindow(windowSamples, windowStart: start, windowEnd: end))
            nextWindowStart = start.addingTimeInterval(config.windowStride)
        }

        trimHistory(anchor: last)
        return results
    }

    private func processWindow(_ samples: [AccelerometerSample], windowStart: Date, windowEnd: Date) -> StepDetectionResult {
        guard samples.count >= Int(config.expectedSampleRateHz * config.windowDuration * 0.4) else {
            return emptyResult(windowStart: windowStart, windowEnd: windowEnd, sampleCount: samples.count)
        }

        let timestamps = samples.map(\.timestamp)
        let magnitudes = filter.normalizedMagnitudes(from: samples)
        let signal = filter.centeredAndSmoothed(magnitudes: magnitudes, timestamps: timestamps)
        guard !signal.isEmpty else {
            return emptyResult(windowStart: windowStart, windowEnd: windowEnd, sampleCount: samples.count)
        }

        let meanMagnitude = StepSignalFilter.mean(magnitudes)
        let signalEnergy = signal.reduce(0) { $0 + $1 * $1 } / Double(signal.count)
        let threshold = detector.dynamicThreshold(signal: signal)
        let rawPeaks = detector.localMaxima(signal: signal, timestamps: timestamps, threshold: threshold)
        if Double(rawPeaks.count) / config.windowDuration > config.maxPeaksPerSecond {
            return StepDetectionResult(
                newSteps: 0,
                cadenceSpm: nil,
                confidence: .none,
                windowStart: windowStart,
                windowEnd: windowEnd,
                acceptedStepTimes: [],
                debugInfo: StepDebugInfo(
                    sampleCount: samples.count,
                    peakCount: rawPeaks.count,
                    acceptedPeakCount: 0,
                    rejectedPeakCount: rawPeaks.count,
                    meanMagnitude: meanMagnitude,
                    signalEnergy: signalEnergy,
                    threshold: threshold
                )
            )
        }
        let candidatePeaks = detector.detect(signal: signal, timestamps: timestamps, threshold: threshold)

        appendRecentCandidatePeaks(candidatePeaks)
        let validation = validator.validate(peaks: recentCandidatePeaks,
                                            signalEnergy: signalEnergy,
                                            windowStart: windowStart,
                                            windowEnd: windowEnd)

        let newPeaks = validation.acceptedPeaks.filter { peak in
            !acceptedStepTimestamps.contains {
                abs($0.timeIntervalSince(peak.timestamp)) < config.minStepInterval
            }
        }
        acceptedStepTimestamps.append(contentsOf: newPeaks.map(\.timestamp))

        let acceptedCount = newPeaks.count
        return StepDetectionResult(
            newSteps: acceptedCount,
            cadenceSpm: validation.cadenceSpm,
            confidence: acceptedCount > 0 ? validation.confidence : .none,
            windowStart: windowStart,
            windowEnd: windowEnd,
            acceptedStepTimes: newPeaks.map(\.timestamp),
            debugInfo: StepDebugInfo(
                sampleCount: samples.count,
                peakCount: candidatePeaks.count,
                acceptedPeakCount: acceptedCount,
                rejectedPeakCount: max(0, candidatePeaks.count - acceptedCount),
                meanMagnitude: meanMagnitude,
                signalEnergy: signalEnergy,
                threshold: threshold
            )
        )
    }

    private func emptyResult(windowStart: Date, windowEnd: Date, sampleCount: Int) -> StepDetectionResult {
        StepDetectionResult(newSteps: 0,
                            cadenceSpm: nil,
                            confidence: .none,
                            windowStart: windowStart,
                            windowEnd: windowEnd,
                            acceptedStepTimes: [],
                            debugInfo: StepDebugInfo(sampleCount: sampleCount,
                                                     peakCount: 0,
                                                     acceptedPeakCount: 0,
                                                     rejectedPeakCount: 0,
                                                     meanMagnitude: 0,
                                                     signalEnergy: 0,
                                                     threshold: config.minThresholdG))
    }

    private func trimHistory(anchor: Date) {
        buffer.removeAll { anchor.timeIntervalSince($0.timestamp) > config.historyDuration }
        recentCandidatePeaks.removeAll { anchor.timeIntervalSince($0.timestamp) > config.validationWindow }
        acceptedStepTimestamps.removeAll { anchor.timeIntervalSince($0) > config.acceptedHistoryDuration }
    }

    private func appendRecentCandidatePeaks(_ peaks: [StepPeak]) {
        for peak in peaks {
            if let index = recentCandidatePeaks.firstIndex(where: {
                abs($0.timestamp.timeIntervalSince(peak.timestamp)) < config.minStepInterval
            }) {
                if peak.value > recentCandidatePeaks[index].value {
                    recentCandidatePeaks[index] = peak
                }
            } else {
                recentCandidatePeaks.append(peak)
            }
        }
        recentCandidatePeaks.sort { $0.timestamp < $1.timestamp }
    }
}
