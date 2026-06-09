import Foundation
import WhoopStore

enum RecoveryInputBuilder {
    static func buildInput(
        for session: CachedSleepSession,
        daily: DailyMetric?,
        previousDay: DailyMetric?,
        sleepScore: Int?
    ) -> RecoveryInput {
        let durationMinutes = max(0, Double(session.endTs - session.startTs) / 60)
        return RecoveryInput(
            date: Date(timeIntervalSince1970: TimeInterval(session.endTs)),
            hrvRmssd: positive(daily?.avgHrv) ?? positive(session.avgHrv),
            sleepingRHR: daily?.restingHr.map(Double.init) ?? session.restingHr.map(Double.init),
            sleepScore: sleepScore.map(Double.init) ?? fallbackSleepScore(durationMinutes: durationMinutes, efficiency: daily?.efficiency ?? session.efficiency),
            sleepDurationMinutes: positive(daily?.totalSleepMin) ?? durationMinutes,
            sleepEfficiency: daily?.efficiency ?? session.efficiency,
            respiratoryRate: daily?.respRateBpm,
            skinTemp: daily?.skinTempDevC,
            spo2: daily?.spo2Pct,
            previousDayStrain: previousDay?.strain,
            sensorQuality: nil
        )
    }

    static func buildNight(
        from session: CachedSleepSession,
        daily: DailyMetric?,
        previousDay: DailyMetric?,
        sleepScore: Int?
    ) -> RecoveryNight {
        let durationMinutes = max(0, Double(session.endTs - session.startTs) / 60)
        return RecoveryNight(
            date: Date(timeIntervalSince1970: TimeInterval(session.endTs)),
            hasMainSleepSession: true,
            sleepDurationMinutes: positive(daily?.totalSleepMin) ?? durationMinutes,
            hrvRmssd: positive(daily?.avgHrv) ?? positive(session.avgHrv),
            sleepingRHR: daily?.restingHr.map(Double.init) ?? session.restingHr.map(Double.init),
            sleepScore: sleepScore.map(Double.init) ?? fallbackSleepScore(durationMinutes: durationMinutes, efficiency: daily?.efficiency ?? session.efficiency),
            sleepEfficiency: daily?.efficiency ?? session.efficiency,
            respiratoryRate: daily?.respRateBpm,
            skinTemp: daily?.skinTempDevC,
            spo2: daily?.spo2Pct,
            previousDayStrain: previousDay?.strain,
            hasEnoughCleanHRData: (daily?.avgHrv ?? session.avgHrv) != nil && (daily?.restingHr ?? session.restingHr) != nil,
            isManuallyInvalid: false,
            sensorQuality: nil
        )
    }

    private static func fallbackSleepScore(durationMinutes: Double, efficiency: Double?) -> Double? {
        guard durationMinutes > 0 else { return nil }
        let durationScore = min(100, max(0, durationMinutes / 480 * 100))
        guard let efficiency else { return durationScore }
        return min(100, max(0, durationScore * 0.65 + (efficiency * 100) * 0.35))
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }
}

enum RecoveryRepository {
    static func getRecovery(for date: Date, sessions: [CachedSleepSession], dailyRows: [DailyMetric]) -> RecoveryScore? {
        recalculateRecovery(for: date, sessions: sessions, dailyRows: dailyRows)
    }

    static func saveRecovery(_ recovery: RecoveryScore) -> RecoveryScore {
        guard let data = try? JSONEncoder().encode(recovery) else { return recovery }
        UserDefaults.standard.set(data, forKey: storageKey(for: recovery.id))
        return recovery
    }

    static func savedRecovery(for date: Date) -> RecoveryScore? {
        let id = utcDayFormatter().string(from: date)
        guard let data = UserDefaults.standard.data(forKey: storageKey(for: id)) else { return nil }
        return try? JSONDecoder().decode(RecoveryScore.self, from: data)
    }

    static func getRecoveryHistory(range: ClosedRange<Date>, sessions: [CachedSleepSession], dailyRows: [DailyMetric]) -> [RecoveryScore] {
        sessions.compactMap { session in
            let date = Date(timeIntervalSince1970: TimeInterval(session.endTs))
            guard range.contains(date) else { return nil }
            return recalculateRecovery(for: date, sessions: sessions, dailyRows: dailyRows)
        }
    }

    static func recalculateRecovery(for date: Date, sessions: [CachedSleepSession], dailyRows: [DailyMetric]) -> RecoveryScore? {
        let dayFormatter = utcDayFormatter()
        let dailyByDay = Dictionary(uniqueKeysWithValues: dailyRows.map { ($0.day, $0) })
        let targetDay = dayFormatter.string(from: date)

        let targetSession = sessions
            .filter { dayFormatter.string(from: Date(timeIntervalSince1970: TimeInterval($0.endTs))) == targetDay }
            .max { $0.endTs < $1.endTs }

        guard let targetSession else { return nil }

        let nights = sessions.map { session -> RecoveryNight in
            let day = dayFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(session.endTs)))
            let previous = previousDailyMetric(forDay: day, dailyByDay: dailyByDay)
            return RecoveryInputBuilder.buildNight(
                from: session,
                daily: dailyByDay[day],
                previousDay: previous,
                sleepScore: nil
            )
        }

        let baseline = RecoveryBaselineService.getBaseline(for: Date(timeIntervalSince1970: TimeInterval(targetSession.endTs)), nights: nights)
        let targetPrevious = previousDailyMetric(forDay: targetDay, dailyByDay: dailyByDay)
        let input = RecoveryInputBuilder.buildInput(
            for: targetSession,
            daily: dailyByDay[targetDay],
            previousDay: targetPrevious,
            sleepScore: nil
        )
        return saveRecovery(RecoveryScoreCalculator.calculateRecovery(input: input, baseline: baseline))
    }

    private static func previousDailyMetric(forDay day: String, dailyByDay: [String: DailyMetric]) -> DailyMetric? {
        guard let date = utcDayFormatter().date(from: day),
              let previous = utcCalendar().date(byAdding: .day, value: -1, to: date) else {
            return nil
        }
        return dailyByDay[utcDayFormatter().string(from: previous)]
    }

    private static func storageKey(for id: String) -> String {
        "com.openwhoop.recoveryScore.\(id)"
    }

    private static func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private static func utcDayFormatter() -> DateFormatter {
        let fmt = DateFormatter()
        fmt.calendar = utcCalendar()
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }
}
