import Foundation

public enum MetricValueSource: String, Codable, CaseIterable, Sendable {
    case server
    case onDevice
    case manual
    case imported
    case unknown
}

public enum MetricAvailabilityStatus: String, Codable, CaseIterable, Sendable {
    case ready
    case buildingBaseline
    case unavailable
    case processing
}

public struct RecoveryMetric: Equatable, Codable, Sendable {
    public let day: String
    public let score: Double?
    public let status: MetricAvailabilityStatus
    public let category: String?
    public let source: MetricValueSource
    public let confidence: Double?
    public let baselineProgress: Int
    public let explanation: String?
    public let recomputedAt: Int?

    public init(day: String,
                score: Double?,
                status: MetricAvailabilityStatus,
                category: String?,
                source: MetricValueSource,
                confidence: Double?,
                baselineProgress: Int,
                explanation: String?,
                recomputedAt: Int?) {
        self.day = day
        self.score = score
        self.status = status
        self.category = category
        self.source = source
        self.confidence = confidence
        self.baselineProgress = baselineProgress
        self.explanation = explanation
        self.recomputedAt = recomputedAt
    }
}

public struct StrainMetric: Equatable, Codable, Sendable {
    public let day: String
    public let score: Double?
    public let status: MetricAvailabilityStatus
    public let source: MetricValueSource
    public let confidence: Double?
    public let explanation: String?
    public let recomputedAt: Int?

    public init(day: String,
                score: Double?,
                status: MetricAvailabilityStatus,
                source: MetricValueSource,
                confidence: Double?,
                explanation: String?,
                recomputedAt: Int?) {
        self.day = day
        self.score = score
        self.status = status
        self.source = source
        self.confidence = confidence
        self.explanation = explanation
        self.recomputedAt = recomputedAt
    }
}

public struct MetricBaseline: Equatable, Codable, Sendable {
    public let metric: String
    public let day: String
    public let value: Double?
    public let sampleCount: Int
    public let confidence: Double?
    public let status: MetricAvailabilityStatus
    public let reason: String?
    public let recomputedAt: Int?

    public init(metric: String,
                day: String,
                value: Double?,
                sampleCount: Int,
                confidence: Double?,
                status: MetricAvailabilityStatus,
                reason: String?,
                recomputedAt: Int?) {
        self.metric = metric
        self.day = day
        self.value = value
        self.sampleCount = sampleCount
        self.confidence = confidence
        self.status = status
        self.reason = reason
        self.recomputedAt = recomputedAt
    }
}

public struct MetricDiagnosticEntry: Equatable, Codable, Sendable {
    public let key: String
    public let value: String
    public let updatedAt: Int?

    public init(key: String, value: String, updatedAt: Int?) {
        self.key = key
        self.value = value
        self.updatedAt = updatedAt
    }
}

public enum LocalWorkoutType: String, Codable, CaseIterable, Sendable {
    case strengthTraining
    case outsideRun
    case insideRun
    case insideCycling
    case outsideCycling
}

public enum LocalWorkoutStatus: String, Codable, Sendable {
    case active
    case paused
    case ended
}

public struct LocalWorkoutHeartRateSample: Equatable, Codable, Sendable {
    public let timestamp: Date
    public let bpm: Int

    public init(timestamp: Date, bpm: Int) {
        self.timestamp = timestamp
        self.bpm = bpm
    }
}

public struct LocalMotionSample: Equatable, Codable, Sendable {
    public let timestamp: Date
    public let magnitude: Double
    public let source: String

    public init(timestamp: Date, magnitude: Double, source: String) {
        self.timestamp = timestamp
        self.magnitude = magnitude
        self.source = source
    }
}

public struct LocalWorkoutZoneBreakdown: Equatable, Codable, Sendable {
    public let percentages: [Int: Double]
    public let currentZone: Int?

    public init(percentages: [Int: Double], currentZone: Int?) {
        self.percentages = percentages
        self.currentZone = currentZone
    }
}

public struct LocalWorkoutSession: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let type: LocalWorkoutType
    public let startTime: Date
    public let endTime: Date?
    public let duration: TimeInterval
    public let status: LocalWorkoutStatus
    public let heartRateSamples: [LocalWorkoutHeartRateSample]
    public let accelerometerSamples: [LocalMotionSample]
    public let gyroscopeSamples: [LocalMotionSample]
    public let averageHeartRate: Double?
    public let maxHeartRate: Double?
    public let cardioLoad: Double
    public let muscularLoad: Double
    public let dailyStressLoad: Double
    public let totalLoad: Double
    public let strainScore: Double
    public let userIntensity: Int?
    public let muscularConfidence: Double
    public let recoveryAdjustment: Double
    public let baselineStrain: Double?
    public let zoneBreakdown: LocalWorkoutZoneBreakdown

    public init(id: UUID,
                type: LocalWorkoutType,
                startTime: Date,
                endTime: Date?,
                duration: TimeInterval,
                status: LocalWorkoutStatus,
                heartRateSamples: [LocalWorkoutHeartRateSample],
                accelerometerSamples: [LocalMotionSample],
                gyroscopeSamples: [LocalMotionSample],
                averageHeartRate: Double?,
                maxHeartRate: Double?,
                cardioLoad: Double,
                muscularLoad: Double,
                dailyStressLoad: Double,
                totalLoad: Double,
                strainScore: Double,
                userIntensity: Int?,
                muscularConfidence: Double,
                recoveryAdjustment: Double,
                baselineStrain: Double?,
                zoneBreakdown: LocalWorkoutZoneBreakdown) {
        self.id = id
        self.type = type
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.status = status
        self.heartRateSamples = heartRateSamples
        self.accelerometerSamples = accelerometerSamples
        self.gyroscopeSamples = gyroscopeSamples
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.cardioLoad = cardioLoad
        self.muscularLoad = muscularLoad
        self.dailyStressLoad = dailyStressLoad
        self.totalLoad = totalLoad
        self.strainScore = strainScore
        self.userIntensity = userIntensity
        self.muscularConfidence = muscularConfidence
        self.recoveryAdjustment = recoveryAdjustment
        self.baselineStrain = baselineStrain
        self.zoneBreakdown = zoneBreakdown
    }
}
