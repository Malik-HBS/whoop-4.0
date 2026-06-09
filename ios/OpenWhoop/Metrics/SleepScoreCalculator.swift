import Foundation

enum SleepScoreStatus: Equatable {
    case buildingBaseline
    case ready
    case insufficientData
}

struct SleepScoreResult: Equatable {
    let score: Int?
    let status: SleepScoreStatus
    let baselineProgress: Int
    let requiredBaselineNights: Int
    let components: SleepScoreComponents?
    let explanation: String
}

struct SleepScoreComponents: Equatable {
    let sleepNeedCompletion: Double
    let sleepEfficiency: Double
    let disturbances: Double
    let recovery: Double
    let consistency: Double
    let architecture: Double
}

struct SleepBaseline: Equatable {
    let averageSleepDurationMinutes: Double
    let averageSleepEfficiency: Double
    let averageBedtimeMinutesFromMidnight: Double
    let averageWakeTimeMinutesFromMidnight: Double
    let averageHRV: Double?
    let averageSleepingHR: Double?
    let averageDeepSleepMinutes: Double?
    let averageREMSleepMinutes: Double?
}

struct SleepScoreNight: Equatable {
    let sleepStart: Date
    let sleepEnd: Date
    let timeAsleepMinutes: Double?
    let timeInBedMinutes: Double?
    let wakeAfterSleepOnsetMinutes: Double?
    let wakeEventCount: Int?
    let deepSleepMinutes: Double?
    let remSleepMinutes: Double?
    let averageSleepingHR: Double?
    let averageHRV: Double?
    let respiratoryRate: Double?
    let spo2: Double?
    let skinTemperatureDeviationC: Double?
    let restlessnessRatio: Double?
}

enum SleepScoreCalculator {
    static let requiredBaselineNights = 7

    static func calculate(
        for targetNight: SleepScoreNight?,
        history: [SleepScoreNight],
        requiredBaselineNights: Int = Self.requiredBaselineNights,
        calendar: Calendar = .current
    ) -> SleepScoreResult {
        let validHistory = history
            .filter(isValidNight)
            .sorted { $0.sleepStart < $1.sleepStart }
        let progress = min(validHistory.count, requiredBaselineNights)

        guard validHistory.count >= requiredBaselineNights else {
            return SleepScoreResult(
                score: nil,
                status: .buildingBaseline,
                baselineProgress: progress,
                requiredBaselineNights: requiredBaselineNights,
                components: nil,
                explanation: validHistory.isEmpty
                    ? "Building baseline. Wear your WHOOP 4.0 for 7 valid nights to unlock sleep scoring."
                    : "Building baseline"
            )
        }

        guard let targetNight, isValidNight(targetNight) else {
            return SleepScoreResult(
                score: nil,
                status: .insufficientData,
                baselineProgress: progress,
                requiredBaselineNights: requiredBaselineNights,
                components: nil,
                explanation: "Insufficient sleep data"
            )
        }

        let baselineNights = Array(validHistory.suffix(30))
        let baseline = makeBaseline(from: baselineNights, calendar: calendar)

        let components = SleepScoreComponents(
            sleepNeedCompletion: sleepNeedCompletionScore(targetNight, baseline: baseline),
            sleepEfficiency: sleepEfficiencyScore(targetNight),
            disturbances: disturbancesScore(targetNight),
            recovery: recoveryScore(targetNight, baseline: baseline),
            consistency: consistencyScore(targetNight, baseline: baseline, calendar: calendar),
            architecture: architectureScore(targetNight, baseline: baseline)
        )

        let rawScore = components.sleepNeedCompletion
            + components.sleepEfficiency
            + components.disturbances
            + components.recovery
            + components.consistency
            + components.architecture
        let score = Int(clamp(rawScore, 0, 100).rounded())

        return SleepScoreResult(
            score: score,
            status: .ready,
            baselineProgress: progress,
            requiredBaselineNights: requiredBaselineNights,
            components: components,
            explanation: explanation(for: targetNight, baseline: baseline, components: components)
        )
    }

    static func isValidNight(_ night: SleepScoreNight) -> Bool {
        guard night.sleepEnd > night.sleepStart else { return false }
        let duration = night.timeAsleepMinutes ?? estimateTimeAsleepMinutes(night)
        return (duration ?? 0) >= 180
    }

    static func makeBaseline(
        from nights: [SleepScoreNight],
        calendar: Calendar = .current
    ) -> SleepBaseline {
        let validNights = nights.filter(isValidNight).suffix(30)
        return SleepBaseline(
            averageSleepDurationMinutes: average(validNights.compactMap { $0.timeAsleepMinutes ?? estimateTimeAsleepMinutes($0) }) ?? 480,
            averageSleepEfficiency: average(validNights.compactMap(efficiency)) ?? 0.85,
            averageBedtimeMinutesFromMidnight: circularAverageMinutes(validNights.map { minutesFromMidnight($0.sleepStart, calendar: calendar) }),
            averageWakeTimeMinutesFromMidnight: circularAverageMinutes(validNights.map { minutesFromMidnight($0.sleepEnd, calendar: calendar) }),
            averageHRV: average(validNights.compactMap(\.averageHRV)),
            averageSleepingHR: average(validNights.compactMap(\.averageSleepingHR)),
            averageDeepSleepMinutes: average(validNights.compactMap(\.deepSleepMinutes)),
            averageREMSleepMinutes: average(validNights.compactMap(\.remSleepMinutes))
        )
    }

    static func circularDifferenceMinutes(_ lhs: Double, _ rhs: Double) -> Double {
        let day = 24.0 * 60.0
        let raw = abs(lhs - rhs).truncatingRemainder(dividingBy: day)
        return min(raw, day - raw)
    }

    private static func sleepNeedCompletionScore(_ night: SleepScoreNight, baseline: SleepBaseline) -> Double {
        let baseNeed = max(baseline.averageSleepDurationMinutes, 480)
        let actual = night.timeAsleepMinutes ?? estimateTimeAsleepMinutes(night) ?? 0
        return clamp(actual / baseNeed, 0, 1) * 35
    }

    private static func sleepEfficiencyScore(_ night: SleepScoreNight) -> Double {
        guard let e = efficiency(night) else { return 10 }
        if e >= 0.90 { return 20 }
        if e >= 0.85 { return 16 + ((e - 0.85) / 0.05) * 4 }
        if e >= 0.80 { return 11 + ((e - 0.80) / 0.05) * 4 }
        if e >= 0.75 { return 6 + ((e - 0.75) / 0.05) * 4 }
        return max(0, e / 0.75 * 5)
    }

    private static func disturbancesScore(_ night: SleepScoreNight) -> Double {
        var score = 15.0
        let waso = max(0, night.wakeAfterSleepOnsetMinutes ?? estimatedAwakeMinutes(night) ?? 0)
        switch waso {
        case ...20:
            break
        case ...40:
            score -= 3
        case ...60:
            score -= 6
        default:
            score -= 9
        }

        switch night.wakeEventCount ?? 0 {
        case 0...1:
            break
        case 2...3:
            score -= 2
        case 4...5:
            score -= 4
        default:
            score -= 6
        }

        if let restlessness = night.restlessnessRatio, restlessness > 1.15 {
            score -= min(3, (restlessness - 1.0) / 0.15)
        }

        return clamp(score, 0, 15)
    }

    private static func recoveryScore(_ night: SleepScoreNight, baseline: SleepBaseline) -> Double {
        var total = 0.0
        var possible = 0.0

        if let hrv = night.averageHRV, let baselineHRV = baseline.averageHRV, baselineHRV > 0 {
            let ratio = hrv / baselineHRV
            possible += 7
            if ratio >= 1 {
                total += 7
            } else if ratio >= 0.90 {
                total += 5 + ((ratio - 0.90) / 0.10) * 2
            } else if ratio >= 0.80 {
                total += 3 + ((ratio - 0.80) / 0.10) * 2
            } else {
                total += clamp(ratio / 0.80, 0, 1) * 2
            }
        }

        if let hr = night.averageSleepingHR, let baselineHR = baseline.averageSleepingHR {
            let delta = hr - baselineHR
            possible += 6
            if delta <= 0 {
                total += 6
            } else if delta <= 3 {
                total += 4 + ((3 - delta) / 3) * 2
            } else if delta <= 7 {
                total += 2 + ((7 - delta) / 4) * 2
            } else {
                total += max(0, 1 - ((delta - 8) / 8))
            }
        }

        let stability = stabilityScore(night)
        if stability.hasData {
            possible += 2
            total += stability.score
        }

        guard possible > 0 else { return 8 }
        return clamp(total / possible * 15, 0, 15)
    }

    private static func consistencyScore(
        _ night: SleepScoreNight,
        baseline: SleepBaseline,
        calendar: Calendar
    ) -> Double {
        let bedtime = minutesFromMidnight(night.sleepStart, calendar: calendar)
        let wake = minutesFromMidnight(night.sleepEnd, calendar: calendar)
        let avgDiff = (
            circularDifferenceMinutes(bedtime, baseline.averageBedtimeMinutesFromMidnight)
            + circularDifferenceMinutes(wake, baseline.averageWakeTimeMinutesFromMidnight)
        ) / 2

        if avgDiff <= 30 { return 10 }
        if avgDiff <= 60 { return 7 + (60 - avgDiff) / 30 * 3 }
        if avgDiff <= 90 { return 4 + (90 - avgDiff) / 30 * 3 }
        return max(0, 3 - ((avgDiff - 90) / 60) * 3)
    }

    private static func architectureScore(_ night: SleepScoreNight, baseline: SleepBaseline) -> Double {
        var total = 0.0
        var possible = 0.0

        if let deep = night.deepSleepMinutes, let baselineDeep = baseline.averageDeepSleepMinutes, baselineDeep > 0 {
            total += clamp(deep / baselineDeep, 0, 1) * 2.5
            possible += 2.5
        }

        if let rem = night.remSleepMinutes, let baselineREM = baseline.averageREMSleepMinutes, baselineREM > 0 {
            total += clamp(rem / baselineREM, 0, 1) * 2.5
            possible += 2.5
        }

        guard possible > 0 else { return 3 }
        return clamp(total / possible * 5, 0, 5)
    }

    private static func explanation(
        for night: SleepScoreNight,
        baseline: SleepBaseline,
        components: SleepScoreComponents
    ) -> String {
        let ranked: [(name: String, percent: Double)] = [
            ("sleep need", components.sleepNeedCompletion / 35),
            ("efficiency", components.sleepEfficiency / 20),
            ("wake time", components.disturbances / 15),
            ("recovery", components.recovery / 15),
            ("consistency", components.consistency / 10),
            ("sleep stages", components.architecture / 5)
        ].sorted { $0.percent < $1.percent }

        if (night.averageHRV == nil && night.averageSleepingHR == nil) {
            return "Physiology data was limited, so the score focused on duration, efficiency, and continuity."
        }

        if night.deepSleepMinutes == nil && night.remSleepMinutes == nil && ranked.first?.name == "sleep stages" {
            return "Sleep stage data was limited, so the score focused on duration, efficiency, and continuity."
        }

        let completionRatio = clamp((night.timeAsleepMinutes ?? estimateTimeAsleepMinutes(night) ?? 0) / max(baseline.averageSleepDurationMinutes, 480), 0, 1)
        let completion = Int((completionRatio * 100).rounded())
        switch ranked.first?.name {
        case "sleep need":
            return "You met \(completion)% of your sleep need; more time asleep would raise this score."
        case "efficiency":
            return "Your sleep duration was useful, but sleep efficiency was below your baseline."
        case "wake time":
            return "You met \(completion)% of your sleep need, but wake time or disturbances were higher."
        case "recovery":
            return "Your sleep duration was good, but HR or HRV recovery was below your baseline."
        case "consistency":
            return "Your timing was less consistent than your recent sleep baseline."
        case "sleep stages":
            return "REM or deep sleep was lighter than your recent baseline."
        default:
            return "Sleep score is based on duration, efficiency, continuity, recovery, timing, and sleep balance."
        }
    }

    private static func efficiency(_ night: SleepScoreNight) -> Double? {
        if let timeAsleep = night.timeAsleepMinutes,
           let timeInBed = night.timeInBedMinutes,
           timeInBed > 0 {
            return clamp(timeAsleep / timeInBed, 0, 1)
        }
        return nil
    }

    private static func estimateTimeAsleepMinutes(_ night: SleepScoreNight) -> Double? {
        if let timeAsleep = night.timeAsleepMinutes { return timeAsleep }
        guard let timeInBed = night.timeInBedMinutes, let e = efficiency(night) else {
            return nil
        }
        return timeInBed * e
    }

    private static func estimatedAwakeMinutes(_ night: SleepScoreNight) -> Double? {
        guard let timeInBed = night.timeInBedMinutes,
              let timeAsleep = night.timeAsleepMinutes else { return nil }
        return max(0, timeInBed - timeAsleep)
    }

    private static func stabilityScore(_ night: SleepScoreNight) -> (score: Double, hasData: Bool) {
        var checks: [Double] = []
        if let respiratoryRate = night.respiratoryRate, respiratoryRate > 0 {
            checks.append(respiratoryRate >= 10 && respiratoryRate <= 20 ? 1 : 0.4)
        }
        if let spo2 = night.spo2 {
            checks.append(spo2 >= 95 ? 1 : (spo2 >= 92 ? 0.5 : 0))
        }
        if let temp = night.skinTemperatureDeviationC {
            checks.append(abs(temp) <= 0.5 ? 1 : (abs(temp) <= 1.0 ? 0.5 : 0))
        }
        guard let avg = average(checks) else { return (0, false) }
        return (avg * 2, true)
    }

    private static func minutesFromMidnight(_ date: Date, calendar: Calendar) -> Double {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
            + Double(components.second ?? 0) / 60
    }

    private static func circularAverageMinutes(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let day = 24.0 * 60.0
        var sinSum = 0.0
        var cosSum = 0.0
        for value in values {
            let angle = value / day * 2 * Double.pi
            sinSum += sin(angle)
            cosSum += cos(angle)
        }
        let angle = atan2(sinSum / Double(values.count), cosSum / Double(values.count))
        let normalized = angle >= 0 ? angle : angle + 2 * Double.pi
        return normalized / (2 * Double.pi) * day
    }

    private static func average<S: Sequence>(_ values: S) -> Double? where S.Element == Double {
        let values = values.filter { $0.isFinite }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(upper, max(lower, value))
    }
}
