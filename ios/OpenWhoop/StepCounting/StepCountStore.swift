import Foundation

final class StepCountStore {
    private let defaults: UserDefaults
    private let keyPrefix: String
    private let calendar: Calendar
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var goalKey: String { "\(keyPrefix).dailyGoal" }

    init(defaults: UserDefaults = .standard, keyPrefix: String = "stepCount", calendar: Calendar = .current) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
        self.calendar = calendar
    }

    func loadSummary(for date: Date) -> DailyStepSummary {
        let day = localDayString(for: date)
        if let data = defaults.data(forKey: key(for: day)),
           let summary = try? decoder.decode(DailyStepSummary.self, from: data) {
            return summary
        }
        return DailyStepSummary(localDate: day, lastUpdatedAt: date)
    }

    func save(_ summary: DailyStepSummary) {
        guard let data = try? encoder.encode(summary) else { return }
        defaults.set(data, forKey: key(for: summary.localDate))
    }

    func loadDailyGoal(default defaultGoal: Int) -> Int {
        let stored = defaults.integer(forKey: goalKey)
        return stored > 0 ? stored : defaultGoal
    }

    func saveDailyGoal(_ goal: Int) {
        defaults.set(goal, forKey: goalKey)
    }

    func loadSummaries(endingAt endDate: Date = Date(), days: Int) -> [DailyStepSummary] {
        guard days > 0 else { return [] }
        let endOfDay = calendar.startOfDay(for: endDate)
        return stride(from: days - 1, through: 0, by: -1).map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: endOfDay) ?? endOfDay
            return loadSummary(for: date)
        }
    }

    func add(steps: Int, at date: Date) -> DailyStepSummary {
        var summary = loadSummary(for: date)
        guard steps > 0 else { return summary }
        let hour = calendar.component(.hour, from: date)
        summary.totalSteps += steps
        if (0..<24).contains(hour) {
            summary.hourlySteps[hour] += steps
        }
        summary.lastUpdatedAt = date
        save(summary)
        return summary
    }

    func localDayString(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func key(for day: String) -> String {
        "\(keyPrefix).daily.\(day)"
    }
}
