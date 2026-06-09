import Combine
import Foundation
import WhoopStore

@MainActor
final class WorkoutManager: ObservableObject {
    @Published private(set) var sessions: [WorkoutSession] = []
    @Published private(set) var activeSessionID: UUID?
    @Published private(set) var lastCompletedSessionID: UUID?

    private let deviceId: String
    private let metrics: MetricsRepository
    private let liveState: LiveState
    private let legacyStore: WorkoutSessionStore
    private var tickerTask: Task<Void, Never>?
    private var localStore: WhoopStore?
    private var openTask: Task<Void, Never>?

    init(
        deviceId: String = AppConfig.deviceId,
        metrics: MetricsRepository,
        liveState: LiveState,
        store: WorkoutSessionStore = WorkoutSessionStore()
    ) {
        self.deviceId = deviceId
        self.metrics = metrics
        self.liveState = liveState
        self.legacyStore = store
        Task { await load() }
    }

    deinit {
        tickerTask?.cancel()
    }

    var activeSession: WorkoutSession? {
        guard let activeSessionID else { return nil }
        return sessions.first(where: { $0.id == activeSessionID })
    }

    var recentCompletedSessions: [WorkoutSession] {
        sessions
            .filter { $0.status == .ended }
            .sorted { ($0.endTime ?? $0.startTime) > ($1.endTime ?? $1.startTime) }
    }

    var todaysSummary: DailyWorkoutStrainSummary? {
        let day = Self.dayString(from: Date())
        let daySessions = sessions.filter {
            $0.status == .ended && Self.dayString(from: $0.startTime) == day
        }
        guard !daySessions.isEmpty else { return nil }
        let totalLoad = daySessions.reduce(0) { $0 + $1.totalLoad }
        return DailyWorkoutStrainSummary(
            day: day,
            score: round(WorkoutStrainCalculator.strainFromLoad(totalLoad), places: 2),
            totalLoad: round(totalLoad, places: 2),
            workoutCount: daySessions.count
        )
    }

    func load() async {
        await ensureStore()
        guard let localStore else { return }
        if (try? await localStore.workoutSessionCount(deviceId: deviceId)) == 0 {
            let legacy = await legacyStore.load()
            if !legacy.isEmpty {
                _ = try? await localStore.upsertWorkoutSessions(legacy.map(\.localModel), deviceId: deviceId)
            } else {
                _ = try? await localStore.importLegacyWorkoutSessionsIfNeeded(deviceId: deviceId,
                                                                              from: WorkoutSessionStore.defaultURL())
            }
        }
        let loaded = ((try? await localStore.workoutSessions(deviceId: deviceId)) ?? []).map(WorkoutSession.init(local:))
        sessions = loaded.sorted { $0.startTime > $1.startTime }
        activeSessionID = sessions.first(where: { $0.status == .active })?.id
        if activeSessionID != nil {
            startTickerIfNeeded()
        }
    }

    func startWorkout(type: WorkoutType) {
        guard activeSessionID == nil else { return }
        let session = WorkoutSession(
            id: UUID(),
            type: type,
            startTime: Date(),
            endTime: nil,
            duration: 0,
            status: .active,
            heartRateSamples: [],
            accelerometerSamples: [],
            gyroscopeSamples: [],
            averageHeartRate: nil,
            maxHeartRate: nil,
            cardioLoad: 0,
            muscularLoad: 0,
            dailyStressLoad: 0,
            totalLoad: 0,
            strainScore: 0,
            userIntensity: nil,
            muscularConfidence: type == .strengthTraining ? 0.55 : 0.9,
            recoveryAdjustment: 1,
            baselineStrain: nil,
            zoneBreakdown: WorkoutZoneBreakdown(percentages: [:], currentZone: nil)
        )
        sessions.insert(session, at: 0)
        activeSessionID = session.id
        persist()
        startTickerIfNeeded()
    }

    func endActiveWorkout() async -> WorkoutSession? {
        guard let activeSessionID,
              let index = sessions.firstIndex(where: { $0.id == activeSessionID }) else { return nil }

        tickerTask?.cancel()
        tickerTask = nil

        var session = sessions[index]
        session.status = .ended
        session.endTime = Date()
        session.duration = max(session.endTime?.timeIntervalSince(session.startTime) ?? session.duration, session.duration)
        let context = await strainContext(excludingSessionID: session.id)
        applyStrain(to: &session, context: context)

        sessions[index] = session
        self.activeSessionID = nil
        lastCompletedSessionID = session.id
        persist()
        metrics.noteWorkoutEnded()
        return session
    }

    func setStrengthIntensity(_ intensity: Int?, for sessionID: UUID) async {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        var session = sessions[index]
        session.userIntensity = intensity
        let context = await strainContext(excludingSessionID: session.id)
        applyStrain(to: &session, context: context)
        sessions[index] = session
        persist()
    }

    func dismissSummary() {
        lastCompletedSessionID = nil
    }

    func session(id: UUID) -> WorkoutSession? {
        sessions.first(where: { $0.id == id })
    }

    private func startTickerIfNeeded() {
        guard tickerTask == nil else { return }
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self?.captureTick()
            }
        }
    }

    private func captureTick() async {
        guard let activeSessionID,
              let index = sessions.firstIndex(where: { $0.id == activeSessionID }) else {
            tickerTask?.cancel()
            tickerTask = nil
            return
        }

        var session = sessions[index]
        session.duration = Date().timeIntervalSince(session.startTime)

        if let heartRate = liveState.heartRate {
            session.heartRateSamples.append(WorkoutHeartRateSample(timestamp: Date(), bpm: heartRate))
        }

        let context = await strainContext(excludingSessionID: session.id)
        applyStrain(to: &session, context: context)
        sessions[index] = session
        persist()
    }

    private func strainContext(excludingSessionID sessionID: UUID) async -> WorkoutStrainContext {
        await metrics.load()
        let profile: Profile?
        if let cached = ProfileStorage.load() {
            profile = cached
        } else {
            profile = await metrics.getProfile()
        }
        let recovery = await metrics.recoveryScore()

        let recentRows = await recentDailyRows()
        let baselineStrain = median(recentRows.compactMap(\.strain))
        let todayDay = Self.dayString(from: Date())
        let currentDayLoad = sessions
            .filter { $0.id != sessionID && $0.status == .ended && Self.dayString(from: $0.startTime) == todayDay }
            .reduce(0) { $0 + $1.totalLoad }

        return WorkoutStrainContext(
            restingHeartRate: Double(metrics.lastNight?.restingHr ?? metrics.today?.restingHr ?? 60),
            age: profile?.age,
            sex: profile?.sex,
            recoveryScore: recovery?.score,
            sleepEfficiency: metrics.lastNight?.efficiency ?? metrics.today?.efficiency,
            baselineStrain: baselineStrain,
            currentDayLoad: currentDayLoad
        )
    }

    private func recentDailyRows() async -> [DailyMetric] {
        let calendar = Calendar(identifier: .gregorian)
        let formatter = Self.utcDayFormatter
        let end = Date()
        let start = calendar.date(byAdding: .day, value: -14, to: end) ?? end
        return await metrics.daily(fromDay: formatter.string(from: start), toDay: formatter.string(from: end))
    }

    private func applyStrain(to session: inout WorkoutSession, context: WorkoutStrainContext) {
        let result = WorkoutStrainCalculator.calculate(session: session, context: context)
        session.averageHeartRate = result.averageHeartRate
        session.maxHeartRate = result.maxHeartRate
        session.cardioLoad = result.cardioLoad
        session.muscularLoad = result.muscularLoad
        session.dailyStressLoad = result.dailyStressLoad
        session.totalLoad = result.totalLoad
        session.strainScore = result.strainScore
        session.muscularConfidence = result.muscularConfidence
        session.recoveryAdjustment = result.recoveryAdjustment
        session.baselineStrain = context.baselineStrain
        session.zoneBreakdown = result.zoneBreakdown
    }

    private func persist() {
        let snapshot = sessions
        Task {
            await ensureStore()
            guard let localStore else { return }
            _ = try? await localStore.upsertWorkoutSessions(snapshot.map(\.localModel), deviceId: deviceId)
        }
    }

    private func ensureStore() async {
        if localStore != nil { return }
        if let openTask {
            await openTask.value
            return
        }
        let task = Task { @MainActor [self] in
            guard let path = try? StorePaths.defaultDatabasePath(),
                  let opened = try? await WhoopStore(path: path) else {
                openTask = nil
                return
            }
            localStore = opened
        }
        openTask = task
        await task.value
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private func round(_ value: Double, places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (value * factor).rounded() / factor
    }

    private static func dayString(from date: Date) -> String {
        utcDayFormatter.string(from: date)
    }

    private static let utcDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
