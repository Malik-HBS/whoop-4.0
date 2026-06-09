import Foundation
import WhoopProtocol

@MainActor
final class StepCountingService: ObservableObject {
    @Published private(set) var state: StepCountState

    private let processor: StepCountingProcessorActor
    private let store: StepCountStore
    private let config: StepCounterConfig
    private var processingTask: Task<Void, Never>?

    init(config: StepCounterConfig = StepCounterConfig(),
         store: StepCountStore = StepCountStore(),
         processor: StepCountingProcessorActor? = nil,
         now: Date = Date()) {
        self.config = config
        self.store = store
        self.processor = processor ?? StepCountingProcessorActor(config: config)
        let summary = store.loadSummary(for: now)
        let dailyGoal = store.loadDailyGoal(default: config.dailyGoal)
        self.state = StepCountState(dailySteps: summary.totalSteps,
                                    stepsThisMinute: 0,
                                    currentCadenceSpm: nil,
                                    confidence: .none,
                                    lastStepAt: nil,
                                    lastUpdatedAt: summary.lastUpdatedAt,
                                    isWalkingLikeMotion: false,
                                    availability: .waitingForData,
                                    dailyGoal: dailyGoal)
    }

    func ingestAccelerometerSample(_ sample: AccelerometerSample) {
        ingestAccelerometerSamples([sample])
    }

    func ingestAccelerometerSamples(_ samples: [AccelerometerSample]) {
        guard !samples.isEmpty else { return }
        resetDailyStepsIfNeeded(now: samples.last?.timestamp ?? Date())
        state.availability = .active

        processingTask = Task { [processor, weak self] in
            let results = await processor.ingest(samples)
            await MainActor.run {
                self?.apply(results)
            }
        }
    }

    func resetDailyStepsIfNeeded(now: Date) {
        let current = store.loadSummary(for: now)
        if current.localDate != store.localDayString(for: state.lastUpdatedAt) {
            state.dailySteps = current.totalSteps
            state.stepsThisMinute = 0
            state.currentCadenceSpm = nil
            state.confidence = .none
            state.lastStepAt = nil
            state.lastUpdatedAt = now
            state.isWalkingLikeMotion = false
        }
    }

    func loadPersistedState(now: Date = Date()) {
        let summary = store.loadSummary(for: now)
        state.dailySteps = summary.totalSteps
        state.lastUpdatedAt = summary.lastUpdatedAt
        state.availability = .waitingForData
        state.dailyGoal = store.loadDailyGoal(default: config.dailyGoal)
    }

    func refreshAvailability(now: Date = Date(), connected: Bool) {
        guard connected else {
            state.availability = .noDevice
            return
        }
        if state.availability == .waitingForData { return }
        state.availability = now.timeIntervalSince(state.lastUpdatedAt) > config.staleAfter ? .stale : .active
    }

    func setDailyGoal(_ goal: Int) {
        let clamped = min(50_000, max(1_000, goal))
        store.saveDailyGoal(clamped)
        state.dailyGoal = clamped
    }

    func dailySummaries(endingAt endDate: Date = Date(), days: Int) -> [DailyStepSummary] {
        store.loadSummaries(endingAt: endDate, days: days)
    }

    private func apply(_ results: [StepDetectionResult]) {
        guard !results.isEmpty else { return }
        let newSteps = results.reduce(0) { $0 + $1.newSteps }
        let latest = results.last
        let updateDate = latest?.windowEnd ?? Date()

        if newSteps > 0 {
            let summary = store.add(steps: newSteps, at: updateDate)
            state.dailySteps = summary.totalSteps
            state.stepsThisMinute = stepsInCurrentMinute(summary: summary, date: updateDate)
            state.lastStepAt = results.flatMap(\.acceptedStepTimes).last
        }

        state.currentCadenceSpm = latest?.cadenceSpm
        state.confidence = latest?.confidence ?? .none
        state.lastUpdatedAt = updateDate
        state.isWalkingLikeMotion = state.confidence == .medium || state.confidence == .high
        state.availability = .active
    }

    private func stepsInCurrentMinute(summary: DailyStepSummary, date: Date) -> Int {
        let hour = Calendar.current.component(.hour, from: date)
        return (0..<summary.hourlySteps.count).contains(hour) ? summary.hourlySteps[hour] : 0
    }
}
