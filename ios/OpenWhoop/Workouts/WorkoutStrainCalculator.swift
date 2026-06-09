import Foundation

struct WorkoutStrainContext {
    var restingHeartRate: Double
    var age: Int?
    var sex: String?
    var recoveryScore: Int?
    var sleepEfficiency: Double?
    var baselineStrain: Double?
    var currentDayLoad: Double
}

struct WorkoutStrainResult: Equatable {
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    let cardioLoad: Double
    let muscularLoad: Double
    let dailyStressLoad: Double
    let totalLoad: Double
    let strainScore: Double
    let muscularConfidence: Double
    let recoveryAdjustment: Double
    let zoneBreakdown: WorkoutZoneBreakdown
}

enum WorkoutStrainCalculator {
    private static let maxStrain = 21.0
    private static let strainDenominator = 7201.0

    static func calculate(session: WorkoutSession, context: WorkoutStrainContext) -> WorkoutStrainResult {
        let samples = session.heartRateSamples.sorted { $0.timestamp < $1.timestamp }
        let durationMinutes = max(session.duration, 60) / 60

        let averageHeartRate = samples.isEmpty ? nil : samples.map(\.bpm).map(Double.init).reduce(0, +) / Double(samples.count)
        let maxHeartRate = samples.map(\.bpm).max().map(Double.init)
        let hrMax = estimateMaxHeartRate(age: context.age, observedPeak: maxHeartRate)
        let cardioLoad = calculateCardioLoad(
            samples: samples,
            restingHeartRate: context.restingHeartRate,
            maxHeartRate: hrMax,
            type: session.type
        )
        let muscularLoad = calculateMuscularLoad(
            type: session.type,
            durationMinutes: durationMinutes,
            averageHeartRate: averageHeartRate,
            intensity: session.userIntensity,
            baselineStrain: context.baselineStrain
        )
        let dailyStressLoad = context.currentDayLoad * 0.12
        let recoveryAdjustment = recoveryAdjustmentMultiplier(
            recoveryScore: context.recoveryScore,
            sleepEfficiency: context.sleepEfficiency
        )

        let totalLoad = max(0, (cardioLoad + muscularLoad + dailyStressLoad) * recoveryAdjustment)
        let strainScore = strainFromLoad(totalLoad)
        let zoneBreakdown = zoneBreakdown(
            samples: samples,
            restingHeartRate: context.restingHeartRate,
            maxHeartRate: hrMax
        )

        return WorkoutStrainResult(
            averageHeartRate: averageHeartRate.map { round($0, places: 1) },
            maxHeartRate: maxHeartRate,
            cardioLoad: round(cardioLoad, places: 2),
            muscularLoad: round(muscularLoad, places: 2),
            dailyStressLoad: round(dailyStressLoad, places: 2),
            totalLoad: round(totalLoad, places: 2),
            strainScore: round(strainScore, places: 2),
            muscularConfidence: session.userIntensity == nil && session.isStrengthWorkout ? 0.55 : 0.9,
            recoveryAdjustment: round(recoveryAdjustment, places: 3),
            zoneBreakdown: zoneBreakdown
        )
    }

    static func strainFromLoad(_ load: Double) -> Double {
        guard load > 0 else { return 0 }
        let raw = maxStrain * log(load + 1) / log(strainDenominator)
        return min(maxStrain, max(0, raw))
    }

    static func loadFromStrain(_ strain: Double) -> Double {
        guard strain > 0 else { return 0 }
        return exp((strain / maxStrain) * log(strainDenominator)) - 1
    }

    private static func calculateCardioLoad(
        samples: [WorkoutHeartRateSample],
        restingHeartRate: Double,
        maxHeartRate: Double,
        type: WorkoutType
    ) -> Double {
        guard samples.count >= 2, maxHeartRate > restingHeartRate else { return 0 }
        let reserve = maxHeartRate - restingHeartRate
        var load = 0.0
        for index in 1..<samples.count {
            let previous = samples[index - 1]
            let current = samples[index]
            let durationMinutes = max(current.timestamp.timeIntervalSince(previous.timestamp), 1) / 60
            let pctHrr = max(0, min(1, (Double(previous.bpm) - restingHeartRate) / reserve))
            let weight: Double
            switch pctHrr {
            case 0.9...: weight = 5
            case 0.8..<0.9: weight = 4
            case 0.7..<0.8: weight = 3
            case 0.6..<0.7: weight = 2
            case 0.5..<0.6: weight = 1
            default: weight = 0
            }
            load += durationMinutes * weight
        }
        return load * type.cardioBias
    }

    private static func calculateMuscularLoad(
        type: WorkoutType,
        durationMinutes: Double,
        averageHeartRate: Double?,
        intensity: Int?,
        baselineStrain: Double?
    ) -> Double {
        let baselineFactor: Double
        if let baselineStrain {
            baselineFactor = clamp(1.18 - baselineStrain / 35, min: 0.78, max: 1.12)
        } else {
            baselineFactor = 1
        }

        if type == .strengthTraining {
            let rpe = Double(intensity ?? 5)
            let intensityFactor = pow(rpe / 10, 1.35)
            let durationFactor = pow(max(durationMinutes, 10) / 30, 0.92)
            return 42 * intensityFactor * durationFactor * baselineFactor * type.muscularBias
        }

        let hrFactor = max(0.6, min(1.4, (averageHeartRate ?? 115) / 135))
        return durationMinutes * 0.42 * hrFactor * baselineFactor * type.muscularBias
    }

    private static func recoveryAdjustmentMultiplier(recoveryScore: Int?, sleepEfficiency: Double?) -> Double {
        let recoveryEffect: Double
        if let recoveryScore {
            recoveryEffect = clamp(1.08 - (Double(recoveryScore) / 100) * 0.16, min: 0.92, max: 1.12)
        } else {
            recoveryEffect = 1
        }

        let sleepEffect: Double
        if let sleepEfficiency {
            sleepEffect = clamp(1.06 - sleepEfficiency * 0.08, min: 0.96, max: 1.08)
        } else {
            sleepEffect = 1
        }

        return recoveryEffect * sleepEffect
    }

    private static func estimateMaxHeartRate(age: Int?, observedPeak: Double?) -> Double {
        let tanaka = age.map { 208 - 0.7 * Double($0) } ?? 187
        guard let observedPeak else { return tanaka }
        return max(observedPeak, tanaka)
    }

    private static func zoneBreakdown(
        samples: [WorkoutHeartRateSample],
        restingHeartRate: Double,
        maxHeartRate: Double
    ) -> WorkoutZoneBreakdown {
        guard samples.count >= 2, maxHeartRate > restingHeartRate else {
            return WorkoutZoneBreakdown(percentages: [:], currentZone: nil)
        }

        let reserve = maxHeartRate - restingHeartRate
        var minutesByZone: [Int: Double] = [:]
        for index in 1..<samples.count {
            let previous = samples[index - 1]
            let current = samples[index]
            let durationMinutes = max(current.timestamp.timeIntervalSince(previous.timestamp), 1) / 60
            let pct = max(0, min(1, (Double(previous.bpm) - restingHeartRate) / reserve))
            let zone: Int
            switch pct {
            case 0.9...: zone = 5
            case 0.8..<0.9: zone = 4
            case 0.7..<0.8: zone = 3
            case 0.6..<0.7: zone = 2
            case 0.5..<0.6: zone = 1
            default: zone = 0
            }
            minutesByZone[zone, default: 0] += durationMinutes
        }

        let totalMinutes = minutesByZone.values.reduce(0, +)
        let percentages = minutesByZone.mapValues {
            totalMinutes > 0 ? round(($0 / totalMinutes) * 100, places: 1) : 0
        }
        let currentZone = samples.last.map {
            let pct = max(0, min(1, (Double($0.bpm) - restingHeartRate) / reserve))
            switch pct {
            case 0.9...: return 5
            case 0.8..<0.9: return 4
            case 0.7..<0.8: return 3
            case 0.6..<0.7: return 2
            case 0.5..<0.6: return 1
            default: return 0
            }
        }
        return WorkoutZoneBreakdown(percentages: percentages, currentZone: currentZone)
    }

    private static func clamp(_ value: Double, min lower: Double, max upper: Double) -> Double {
        Swift.max(lower, Swift.min(upper, value))
    }

    private static func round(_ value: Double, places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (value * factor).rounded() / factor
    }
}
