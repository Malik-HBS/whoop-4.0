import Foundation
import WhoopStore

enum WorkoutType: String, Codable, CaseIterable, Identifiable {
    case strengthTraining
    case outsideRun
    case insideRun
    case insideCycling
    case outsideCycling

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strengthTraining: return "Strength Training"
        case .outsideRun: return "Outside Run"
        case .insideRun: return "Inside Run"
        case .insideCycling: return "Inside Cycling"
        case .outsideCycling: return "Outside Cycling"
        }
    }

    var detail: String {
        switch self {
        case .strengthTraining: return "Gym workout with muscular strain estimate"
        case .outsideRun: return "Outdoor run using heart rate and movement"
        case .insideRun: return "Treadmill run using heart rate and wrist motion"
        case .insideCycling: return "Indoor bike workout using heart rate"
        case .outsideCycling: return "Outdoor ride using heart rate and movement"
        }
    }

    var iconName: String {
        switch self {
        case .strengthTraining: return "dumbbell.fill"
        case .outsideRun, .insideRun: return "figure.run"
        case .insideCycling, .outsideCycling: return "bicycle"
        }
    }

    var cardioBias: Double {
        switch self {
        case .strengthTraining: return 0.55
        case .outsideRun: return 1.12
        case .insideRun: return 1.05
        case .insideCycling: return 0.98
        case .outsideCycling: return 1.08
        }
    }

    var muscularBias: Double {
        switch self {
        case .strengthTraining: return 1.35
        case .outsideRun: return 0.45
        case .insideRun: return 0.35
        case .insideCycling: return 0.28
        case .outsideCycling: return 0.34
        }
    }
}

enum WorkoutStatus: String, Codable {
    case active
    case paused
    case ended
}

struct WorkoutHeartRateSample: Codable, Equatable {
    let timestamp: Date
    let bpm: Int
}

struct MotionSample: Codable, Equatable {
    let timestamp: Date
    let magnitude: Double
    let source: String
}

struct WorkoutZoneBreakdown: Codable, Equatable {
    var percentages: [Int: Double]
    var currentZone: Int?
}

struct WorkoutSession: Identifiable, Codable, Equatable {
    let id: UUID
    let type: WorkoutType
    let startTime: Date
    var endTime: Date?
    var duration: TimeInterval
    var status: WorkoutStatus
    var heartRateSamples: [WorkoutHeartRateSample]
    var accelerometerSamples: [MotionSample]
    var gyroscopeSamples: [MotionSample]
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var cardioLoad: Double
    var muscularLoad: Double
    var dailyStressLoad: Double
    var totalLoad: Double
    var strainScore: Double
    var userIntensity: Int?
    var muscularConfidence: Double
    var recoveryAdjustment: Double
    var baselineStrain: Double?
    var zoneBreakdown: WorkoutZoneBreakdown

    var isStrengthWorkout: Bool { type == .strengthTraining }
    var effectiveIntensity: Int { userIntensity ?? 5 }
}

struct DailyWorkoutStrainSummary: Equatable {
    let day: String
    let score: Double
    let totalLoad: Double
    let workoutCount: Int
}

extension WorkoutType {
    init(localType: LocalWorkoutType) {
        switch localType {
        case .strengthTraining: self = .strengthTraining
        case .outsideRun: self = .outsideRun
        case .insideRun: self = .insideRun
        case .insideCycling: self = .insideCycling
        case .outsideCycling: self = .outsideCycling
        }
    }

    var localType: LocalWorkoutType {
        switch self {
        case .strengthTraining: return .strengthTraining
        case .outsideRun: return .outsideRun
        case .insideRun: return .insideRun
        case .insideCycling: return .insideCycling
        case .outsideCycling: return .outsideCycling
        }
    }
}

extension WorkoutStatus {
    init(localStatus: LocalWorkoutStatus) {
        switch localStatus {
        case .active: self = .active
        case .paused: self = .paused
        case .ended: self = .ended
        }
    }

    var localStatus: LocalWorkoutStatus {
        switch self {
        case .active: return .active
        case .paused: return .paused
        case .ended: return .ended
        }
    }
}

extension WorkoutSession {
    init(local: LocalWorkoutSession) {
        self.init(id: local.id,
                  type: WorkoutType(localType: local.type),
                  startTime: local.startTime,
                  endTime: local.endTime,
                  duration: local.duration,
                  status: WorkoutStatus(localStatus: local.status),
                  heartRateSamples: local.heartRateSamples.map { WorkoutHeartRateSample(timestamp: $0.timestamp, bpm: $0.bpm) },
                  accelerometerSamples: local.accelerometerSamples.map { MotionSample(timestamp: $0.timestamp, magnitude: $0.magnitude, source: $0.source) },
                  gyroscopeSamples: local.gyroscopeSamples.map { MotionSample(timestamp: $0.timestamp, magnitude: $0.magnitude, source: $0.source) },
                  averageHeartRate: local.averageHeartRate,
                  maxHeartRate: local.maxHeartRate,
                  cardioLoad: local.cardioLoad,
                  muscularLoad: local.muscularLoad,
                  dailyStressLoad: local.dailyStressLoad,
                  totalLoad: local.totalLoad,
                  strainScore: local.strainScore,
                  userIntensity: local.userIntensity,
                  muscularConfidence: local.muscularConfidence,
                  recoveryAdjustment: local.recoveryAdjustment,
                  baselineStrain: local.baselineStrain,
                  zoneBreakdown: WorkoutZoneBreakdown(percentages: local.zoneBreakdown.percentages,
                                                      currentZone: local.zoneBreakdown.currentZone))
    }

    var localModel: LocalWorkoutSession {
        LocalWorkoutSession(id: id,
                            type: type.localType,
                            startTime: startTime,
                            endTime: endTime,
                            duration: duration,
                            status: status.localStatus,
                            heartRateSamples: heartRateSamples.map { LocalWorkoutHeartRateSample(timestamp: $0.timestamp, bpm: $0.bpm) },
                            accelerometerSamples: accelerometerSamples.map { LocalMotionSample(timestamp: $0.timestamp, magnitude: $0.magnitude, source: $0.source) },
                            gyroscopeSamples: gyroscopeSamples.map { LocalMotionSample(timestamp: $0.timestamp, magnitude: $0.magnitude, source: $0.source) },
                            averageHeartRate: averageHeartRate,
                            maxHeartRate: maxHeartRate,
                            cardioLoad: cardioLoad,
                            muscularLoad: muscularLoad,
                            dailyStressLoad: dailyStressLoad,
                            totalLoad: totalLoad,
                            strainScore: strainScore,
                            userIntensity: userIntensity,
                            muscularConfidence: muscularConfidence,
                            recoveryAdjustment: recoveryAdjustment,
                            baselineStrain: baselineStrain,
                            zoneBreakdown: LocalWorkoutZoneBreakdown(percentages: zoneBreakdown.percentages,
                                                                     currentZone: zoneBreakdown.currentZone))
    }
}
