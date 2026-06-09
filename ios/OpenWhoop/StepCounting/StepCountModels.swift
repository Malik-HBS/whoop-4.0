import Foundation
import WhoopProtocol

enum StepConfidence: String, Codable, Equatable {
    case none
    case low
    case medium
    case high
}

enum StepDataAvailability: String, Codable, Equatable {
    case noDevice
    case waitingForData
    case active
    case stale
}

struct StepCountState: Equatable {
    var dailySteps: Int
    var stepsThisMinute: Int
    var currentCadenceSpm: Double?
    var confidence: StepConfidence
    var lastStepAt: Date?
    var lastUpdatedAt: Date
    var isWalkingLikeMotion: Bool
    var availability: StepDataAvailability
    var dailyGoal: Int
}

struct StepDetectionResult: Equatable {
    let newSteps: Int
    let cadenceSpm: Double?
    let confidence: StepConfidence
    let windowStart: Date
    let windowEnd: Date
    let acceptedStepTimes: [Date]
    let debugInfo: StepDebugInfo?
}

struct StepDebugInfo: Equatable {
    let sampleCount: Int
    let peakCount: Int
    let acceptedPeakCount: Int
    let rejectedPeakCount: Int
    let meanMagnitude: Double
    let signalEnergy: Double
    let threshold: Double
}

struct StepCounterConfig: Equatable {
    var expectedSampleRateHz: Double = 50.0
    var windowDuration: TimeInterval = 2.0
    var windowStride: TimeInterval = 1.0
    var historyDuration: TimeInterval = 8.0
    var acceptedHistoryDuration: TimeInterval = 10.0
    var minStepInterval: TimeInterval = 0.25
    var maxStepInterval: TimeInterval = 2.0
    var rollingMeanDuration: TimeInterval = 1.0
    var smoothingWidth: Int = 5
    var thresholdStdMultiplier: Double = 0.5
    var minThresholdG: Double = 0.04
    var minWindowEnergy: Double = 0.002
    var minPeaksToStartWalking: Int = 4
    var validationWindow: TimeInterval = 6.0
    var minCadenceSpm: Double = 30
    var maxCadenceSpm: Double = 220
    var highConfidenceMaxIntervalCV: Double = 0.35
    var mediumConfidenceMaxIntervalCV: Double = 0.50
    var maxPeaksPerSecond: Double = 4.0
    var dailyGoal: Int = 10_000
    var staleAfter: TimeInterval = 120
}

struct DailyStepSummary: Codable, Equatable {
    let localDate: String
    var totalSteps: Int
    var hourlySteps: [Int]
    var lastUpdatedAt: Date

    init(localDate: String, totalSteps: Int = 0, hourlySteps: [Int] = Array(repeating: 0, count: 24), lastUpdatedAt: Date) {
        self.localDate = localDate
        self.totalSteps = totalSteps
        self.hourlySteps = hourlySteps.count == 24 ? hourlySteps : Array(hourlySteps.prefix(24)) + Array(repeating: 0, count: max(0, 24 - hourlySteps.count))
        self.lastUpdatedAt = lastUpdatedAt
    }
}

struct StepPeak: Equatable {
    let timestamp: Date
    let value: Double
}

struct WalkingValidation: Equatable {
    let acceptedPeaks: [StepPeak]
    let cadenceSpm: Double?
    let confidence: StepConfidence
}

