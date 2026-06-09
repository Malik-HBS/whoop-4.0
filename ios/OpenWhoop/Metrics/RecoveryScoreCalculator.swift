import Foundation

enum RecoveryZone: String, Codable, Equatable {
    case buildingBaseline
    case red
    case yellow
    case green
}

struct BaselineStatus: Codable, Equatable {
    let hasEnoughBaseline: Bool
    let validNightCount: Int
    let requiredNightCount: Int
    let message: String

    init(hasEnoughBaseline: Bool, validNightCount: Int, requiredNightCount: Int = RecoveryScoringConfig.default.requiredBaselineNights, message: String) {
        self.hasEnoughBaseline = hasEnoughBaseline
        self.validNightCount = validNightCount
        self.requiredNightCount = requiredNightCount
        self.message = message
    }
}

struct RecoveryComponents: Codable, Equatable {
    let hrvScore: Double?
    let rhrScore: Double?
    let sleepScore: Double?
    let stabilityScore: Double?
    let strainScore: Double?
    let finalBeforeCaps: Double?
    let finalAfterCaps: Double?
    let appliedCaps: [String]
}

struct RecoveryBaseline: Codable, Equatable {
    let hrvBaseline: Double?
    let rhrBaseline: Double?
    let respiratoryRateBaseline: Double?
    let skinTempBaseline: Double?
    let spo2Baseline: Double?
    let sleepScoreBaseline: Double?
    let strainBaseline: Double?
    let validNightCount: Int
    let baselineWindowDays: Int

    var status: BaselineStatus {
        let required = RecoveryScoringConfig.default.requiredBaselineNights
        let enough = validNightCount >= required
        return BaselineStatus(
            hasEnoughBaseline: enough,
            validNightCount: validNightCount,
            requiredNightCount: required,
            message: enough ? "Baseline ready" : "Day \(validNightCount) of \(required)"
        )
    }
}

struct RecoveryInput: Codable, Equatable {
    let date: Date
    let hrvRmssd: Double?
    let sleepingRHR: Double?
    let sleepScore: Double?
    let sleepDurationMinutes: Double?
    let sleepEfficiency: Double?
    let respiratoryRate: Double?
    let skinTemp: Double?
    let spo2: Double?
    let previousDayStrain: Double?
    let sensorQuality: Double?
}

struct RecoveryScore: Identifiable, Codable, Equatable {
    let id: String
    let date: Date
    let score: Int?
    let zone: RecoveryZone?
    let statusText: String
    let baselineStatus: BaselineStatus
    let components: RecoveryComponents
    let explanation: [String]
    let inputSnapshot: RecoveryInput?
    let baselineSnapshot: RecoveryBaseline?
    let createdAt: Date
    let updatedAt: Date
}

struct RecoveryScoringConfig: Equatable {
    static let `default` = RecoveryScoringConfig()

    let requiredBaselineNights = 7
    let baselineWindowDays = 7
    let minimumSleepDurationMinutes = 180.0
    let minimumSensorQuality = 0.25
    let highStrainThreshold = 14.0
    let veryHighStrainThreshold = 18.0

    let hrvWeight = 0.40
    let rhrWeight = 0.25
    let sleepWeight = 0.20
    let stabilityWeight = 0.10
    let strainWeight = 0.05
}

struct RecoveryNight: Equatable {
    let date: Date
    let hasMainSleepSession: Bool
    let sleepDurationMinutes: Double?
    let hrvRmssd: Double?
    let sleepingRHR: Double?
    let sleepScore: Double?
    let sleepEfficiency: Double?
    let respiratoryRate: Double?
    let skinTemp: Double?
    let spo2: Double?
    let previousDayStrain: Double?
    let hasEnoughCleanHRData: Bool
    let isManuallyInvalid: Bool
    let sensorQuality: Double?
}

enum RecoveryBaselineService {
    static func isValidRecoveryNight(_ night: RecoveryNight, config: RecoveryScoringConfig = .default) -> Bool {
        guard night.hasMainSleepSession else { return false }
        guard (night.sleepDurationMinutes ?? 0) >= config.minimumSleepDurationMinutes else { return false }
        guard let hrv = night.hrvRmssd, hrv > 0, (5...250).contains(hrv) else { return false }
        guard let rhr = night.sleepingRHR, rhr > 0, (30...120).contains(rhr) else { return false }
        guard night.hasEnoughCleanHRData else { return false }
        guard !night.isManuallyInvalid else { return false }
        if let sensorQuality = night.sensorQuality, sensorQuality < config.minimumSensorQuality { return false }
        if let rr = night.respiratoryRate, !(8...30).contains(rr) { return false }
        if let spo2 = night.spo2, !(70...100).contains(spo2) { return false }
        return true
    }

    static func getBaseline(for date: Date, nights: [RecoveryNight], config: RecoveryScoringConfig = .default) -> RecoveryBaseline {
        let validNights = nights
            .filter { $0.date < date }
            .filter { isValidRecoveryNight($0, config: config) }
            .sorted { $0.date < $1.date }

        guard validNights.count >= config.requiredBaselineNights else {
            return RecoveryBaseline(
                hrvBaseline: nil,
                rhrBaseline: nil,
                respiratoryRateBaseline: nil,
                skinTempBaseline: nil,
                spo2Baseline: nil,
                sleepScoreBaseline: nil,
                strainBaseline: nil,
                validNightCount: validNights.count,
                baselineWindowDays: config.baselineWindowDays
            )
        }

        let baselineNights = Array(validNights.suffix(config.baselineWindowDays))
        return RecoveryBaseline(
            hrvBaseline: median(baselineNights.compactMap(\.hrvRmssd)),
            rhrBaseline: median(baselineNights.compactMap(\.sleepingRHR)),
            respiratoryRateBaseline: median(baselineNights.compactMap(\.respiratoryRate)),
            skinTempBaseline: median(baselineNights.compactMap(\.skinTemp)),
            spo2Baseline: median(baselineNights.compactMap(\.spo2)),
            sleepScoreBaseline: median(baselineNights.compactMap(\.sleepScore)),
            strainBaseline: median(baselineNights.compactMap(\.previousDayStrain)),
            validNightCount: validNights.count,
            baselineWindowDays: baselineNights.count
        )
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}

enum RecoveryScoreCalculator {
    static func calculateRecovery(input: RecoveryInput, baseline: RecoveryBaseline, config: RecoveryScoringConfig = .default) -> RecoveryScore {
        let now = Date()
        let baselineStatus = baseline.status
        let emptyComponents = RecoveryComponents(
            hrvScore: nil,
            rhrScore: nil,
            sleepScore: nil,
            stabilityScore: nil,
            strainScore: nil,
            finalBeforeCaps: nil,
            finalAfterCaps: nil,
            appliedCaps: []
        )

        guard baselineStatus.hasEnoughBaseline else {
            return makeScore(
                input: input,
                score: nil,
                zone: .buildingBaseline,
                statusText: "Building baseline",
                baselineStatus: baselineStatus,
                components: emptyComponents,
                explanation: [baselineStatus.message, "Recovery needs 7 valid nights to learn your normal HRV, resting heart rate, and sleep patterns."],
                baseline: baseline,
                now: now
            )
        }

        var missingRequired: [String] = []
        if input.hrvRmssd == nil { missingRequired.append("HRV") }
        if input.sleepingRHR == nil { missingRequired.append("sleeping resting heart rate") }
        if input.sleepScore == nil && input.sleepDurationMinutes == nil { missingRequired.append("valid sleep session") }

        guard missingRequired.isEmpty,
              let todayHRV = input.hrvRmssd,
              let baselineHRV = baseline.hrvBaseline,
              baselineHRV > 0,
              let todayRHR = input.sleepingRHR,
              let baselineRHR = baseline.rhrBaseline else {
            return makeScore(
                input: input,
                score: nil,
                zone: nil,
                statusText: "Not enough data",
                baselineStatus: baselineStatus,
                components: emptyComponents,
                explanation: missingRequired.isEmpty
                    ? ["Not enough baseline data for required HRV or resting heart rate signals."]
                    : ["Missing required recovery signal: \(missingRequired.joined(separator: ", "))."],
                baseline: baseline,
                now: now
            )
        }

        let hrvScore = clamp(85 + ((todayHRV - baselineHRV) / baselineHRV) * 200, 0, 100)
        let rhrScore = clamp(85 - (todayRHR - baselineRHR) * 7, 0, 100)
        let sleepComponent = sleepScore(input)
        let stability = stabilityScore(input: input, baseline: baseline)
        let strain = strainScore(input: input, hrvScore: hrvScore, config: config)

        let finalBeforeCaps = hrvScore * config.hrvWeight
            + rhrScore * config.rhrWeight
            + sleepComponent * config.sleepWeight
            + stability.score * config.stabilityWeight
            + strain * config.strainWeight

        let capped = applyCaps(
            score: finalBeforeCaps,
            input: input,
            baseline: baseline,
            todayHRV: todayHRV,
            todayRHR: todayRHR
        )
        let finalScore = Int(clamp(capped.score, 0, 100).rounded())
        let zone = zone(for: finalScore)

        let components = RecoveryComponents(
            hrvScore: hrvScore,
            rhrScore: rhrScore,
            sleepScore: sleepComponent,
            stabilityScore: stability.score,
            strainScore: strain,
            finalBeforeCaps: finalBeforeCaps,
            finalAfterCaps: capped.score,
            appliedCaps: capped.appliedCaps
        )

        return makeScore(
            input: input,
            score: finalScore,
            zone: zone,
            statusText: statusText(for: zone),
            baselineStatus: baselineStatus,
            components: components,
            explanation: explanations(
                hrvScore: hrvScore,
                rhrScore: rhrScore,
                sleepScore: sleepComponent,
                stabilityScore: stability.score,
                strainScore: strain,
                limitedInputs: stability.limitedInputs,
                appliedCaps: capped.appliedCaps
            ),
            baseline: baseline,
            now: now
        )
    }

    static func zone(for score: Int) -> RecoveryZone {
        switch score {
        case ...33: return .red
        case 34...66: return .yellow
        default: return .green
        }
    }

    private static func makeScore(
        input: RecoveryInput,
        score: Int?,
        zone: RecoveryZone?,
        statusText: String,
        baselineStatus: BaselineStatus,
        components: RecoveryComponents,
        explanation: [String],
        baseline: RecoveryBaseline?,
        now: Date
    ) -> RecoveryScore {
        RecoveryScore(
            id: Self.dayID(for: input.date),
            date: input.date,
            score: score,
            zone: zone,
            statusText: statusText,
            baselineStatus: baselineStatus,
            components: components,
            explanation: explanation,
            inputSnapshot: input,
            baselineSnapshot: baseline,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func sleepScore(_ input: RecoveryInput) -> Double {
        var component = input.sleepScore ?? {
            guard let duration = input.sleepDurationMinutes else { return 60.0 }
            return clamp(duration / 480 * 100, 0, 100)
        }()
        if let duration = input.sleepDurationMinutes {
            if duration < 240 {
                component = min(component, 30)
            } else if duration < 300 {
                component = min(component, 50)
            }
        }
        if let efficiency = input.sleepEfficiency, efficiency < 0.75 {
            component = max(0, component - 10)
        }
        return clamp(component, 0, 100)
    }

    private static func stabilityScore(input: RecoveryInput, baseline: RecoveryBaseline) -> (score: Double, limitedInputs: Bool) {
        var score = 100.0
        var available = 0

        if let today = input.respiratoryRate, let base = baseline.respiratoryRateBaseline {
            available += 1
            let diff = today - base
            if diff >= 2.0 { score -= 35 }
            else if diff >= 1.0 { score -= 15 }
        }

        if let today = input.skinTemp, let base = baseline.skinTempBaseline {
            available += 1
            let diff = today - base
            if diff >= 1.0 { score -= 40 }
            else if diff >= 0.5 { score -= 20 }
        }

        if let spo2 = input.spo2 {
            available += 1
            if spo2 < 90 { score -= 40 }
            else if spo2 < 94 { score -= 20 }
        }

        if available == 0 {
            return (85, true)
        }
        return (clamp(score, 0, 100), available < 3)
    }

    private static func strainScore(input: RecoveryInput, hrvScore: Double, config: RecoveryScoringConfig) -> Double {
        guard let strain = input.previousDayStrain else { return 85 }
        var score = 90.0
        let sleep = input.sleepScore ?? 100
        if strain >= config.veryHighStrainThreshold, sleep < 60 {
            score = 35
        } else if strain >= config.highStrainThreshold, sleep < 70 {
            score = 50
        }
        if strain >= config.highStrainThreshold, hrvScore < 50 {
            score = min(score, 50)
        }
        return score
    }

    private static func applyCaps(
        score: Double,
        input: RecoveryInput,
        baseline: RecoveryBaseline,
        todayHRV: Double,
        todayRHR: Double
    ) -> (score: Double, appliedCaps: [String]) {
        var capped = score
        var caps: [String] = []

        if let duration = input.sleepDurationMinutes, duration < 240 {
            capped = min(capped, 45)
            caps.append("Sleep duration under 4 hours capped recovery at 45")
        }
        if let baselineRHR = baseline.rhrBaseline, todayRHR >= baselineRHR + 10 {
            capped = min(capped, 40)
            caps.append("Resting heart rate was 10+ bpm above baseline")
        }
        if let baselineHRV = baseline.hrvBaseline, todayHRV <= baselineHRV * 0.70 {
            capped = min(capped, 45)
            caps.append("HRV was below 70% of baseline")
        }
        if let rr = input.respiratoryRate,
           let baselineRR = baseline.respiratoryRateBaseline,
           rr >= baselineRR + 2 {
            capped = min(capped, 50)
            caps.append("Respiratory rate was 2+ above baseline")
        }
        if let skinTemp = input.skinTemp,
           let baselineSkinTemp = baseline.skinTempBaseline,
           skinTemp >= baselineSkinTemp + 1.0 {
            capped = min(capped, 45)
            caps.append("Skin temperature was 1.0C+ above baseline")
        }
        if let spo2 = input.spo2, spo2 < 90 {
            capped = min(capped, 40)
            caps.append("SpO2 was unusually low")
        }

        return (capped, caps)
    }

    private static func explanations(
        hrvScore: Double,
        rhrScore: Double,
        sleepScore: Double,
        stabilityScore: Double,
        strainScore: Double,
        limitedInputs: Bool,
        appliedCaps: [String]
    ) -> [String] {
        var explanation: [String] = []

        if hrvScore >= 80 { explanation.append("HRV was strong compared to your baseline.") }
        else if hrvScore < 50 { explanation.append("HRV was lower than your normal baseline.") }

        if rhrScore >= 80 { explanation.append("Resting heart rate was close to or better than baseline.") }
        else if rhrScore < 50 { explanation.append("Resting heart rate was elevated overnight.") }

        if sleepScore >= 80 { explanation.append("Sleep supported recovery.") }
        else if sleepScore < 60 { explanation.append("Sleep limited recovery.") }

        if stabilityScore < 70 {
            explanation.append("Respiratory rate, temperature, or SpO2 showed unusual stress signals.")
        } else if limitedInputs {
            explanation.append("Limited recovery inputs available.")
        }

        if strainScore < 70 { explanation.append("Yesterday's strain may have reduced readiness.") }
        explanation.append(contentsOf: appliedCaps)

        return explanation
    }

    private static func statusText(for zone: RecoveryZone) -> String {
        switch zone {
        case .buildingBaseline: return "Building baseline"
        case .red: return "Low recovery"
        case .yellow: return "Moderate recovery"
        case .green: return "High recovery"
        }
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(high, max(low, value))
    }

    private static func dayID(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
