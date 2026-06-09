import Foundation
import SwiftUI
import Combine
import WhoopMetrics
import WhoopProtocol
import WhoopStore

// MARK: - MetricsRepository
//
// View-facing read facade over locally-computed metrics and decoded streams in WhoopStore.
// The app recomputes daily/sleep/recovery/strain rows on device and reads them back from the
// store; server sync is optional and only used for profile/debug helpers.
//
// LAZY-OPEN DESIGN: The synchronous init() does NOT open the on-disk store (WhoopStore.init
// is async). Instead, ensureOpen() is called at the top of every async method and opens the
// store + builds ServerSync on the first call. This lets AppRoot create the repo synchronously
// (as a @StateObject) and always inject a non-nil env object — eliminating the brief window
// where RootTabView rendered without the env object and would crash any @EnvironmentObject read.

@MainActor
final class MetricsRepository: ObservableObject {
    @Published private(set) var today: DailyMetric?            // most-recent cached daily row
    @Published private(set) var lastNight: CachedSleepSession? // most-recent cached sleep session
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastRefreshedAt: Date?
    @Published private(set) var localProcessingState = LocalProcessingState()

    // Injected directly (test path): store + sync are ready immediately; skip ensureOpen.
    private var store: WhoopStore?
    private var serverSync: ServerSync?
    private var engine: OnDeviceMetricsEngine
    private let deviceId: String

    // Lazy-open state (app path).
    private var _alreadyOpen = false
    private var _openTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var scheduledComputeTask: Task<Void, Never>?
    private var lastAutoComputeAt: Date?

    // MARK: - Synchronous init (app path — store not yet open)

    /// Creates a repository without opening the on-disk store. The store is opened lazily on the
    /// first async call to load()/refresh()/daily()/sleepSessions(). AppRoot uses this init so it
    /// can always provide a non-nil MetricsRepository env object from the very first frame.
    init(deviceId: String = "my-whoop") {
        self.deviceId = deviceId
        self.store = nil
        self.serverSync = nil
        self.engine = OnDeviceMetricsEngine()
        self._alreadyOpen = false
        configureLocalProcessingObservers()
    }

    // MARK: - Designated init (test path — store + sync injected)

    /// Designated initializer for tests: store and sync are ready immediately; ensureOpen() is
    /// a no-op. Keeps all existing MetricsRepository tests passing without modification.
    init(store: WhoopStore, serverSync: ServerSync?, deviceId: String) {
        self.store = store
        self.serverSync = serverSync
        self.engine = OnDeviceMetricsEngine()
        self.deviceId = deviceId
        self._alreadyOpen = true   // already wired — no lazy open needed
        configureLocalProcessingObservers()
    }

    // MARK: - Lazy open (app path)

    /// Idempotent: opens the on-disk store and builds ServerSync exactly once.
    /// All async public methods call this first so the first real operation bootstraps the stack.
    ///
    /// Concurrency contract: all callers on @MainActor await the SAME Task so no second caller
    /// can observe store == nil after ensureOpen() returns. The guard+assign block has no await
    /// between check and assign, so it is atomic on the single MainActor executor.
    private func ensureOpen() async {
        // Test path (store injected) or a previously-completed open: nothing to do.
        if _alreadyOpen, store != nil { return }
        // An open is already in flight — await the SAME task so we don't double-open.
        if let openTask = _openTask { await openTask.value; return }
        let task = Task { @MainActor [self] in
            guard let path = try? StorePaths.defaultDatabasePath(),
                  let openedStore = try? await WhoopStore(path: path) else {
                lastError = "Could not open local database"
                // Allow a retry on a future call.
                _openTask = nil
                return
            }
            store = openedStore
            serverSync = AppConfig.uploaderConfig(deviceId: deviceId)
                .map { ServerSync(config: $0, store: openedStore, deviceId: deviceId) }
            _alreadyOpen = true
        }
        _openTask = task
        await task.value
    }

    // MARK: - App factory (kept for backward-compat; AppRoot now prefers init())

    /// Opens the shared on-disk store and builds ServerSync from AppConfig.
    /// Returns nil if the store can't be opened (e.g. sandbox unavailable).
    static func makeDefault(deviceId: String = "my-whoop") async -> MetricsRepository? {
        guard let path = try? StorePaths.defaultDatabasePath(),
              let store = try? await WhoopStore(path: path) else { return nil }
        let sync = AppConfig.uploaderConfig(deviceId: deviceId)
            .map { ServerSync(config: $0, store: store, deviceId: deviceId) }
        return MetricsRepository(store: store, serverSync: sync, deviceId: deviceId)
    }

    // MARK: - Load from cache (no network)

    /// Populate `today`/`lastNight` from the local cache. No network call.
    func load() async {
        await ensureOpen()
        guard let store else { return }

        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyy-MM-dd"

        // Fetch last 14 days of daily metrics; take the most-recent (last) row.
        if let start = cal.date(byAdding: .day, value: -14, to: now) {
            let fromDay = fmt.string(from: start)
            let toDay = fmt.string(from: now)
            today = (try? await store.dailyMetrics(deviceId: deviceId, from: fromDay, to: toDay))?.last
        }

        // Fetch last 14 days of sleep sessions; take the most-recent (last) row.
        let windowStart = Int(now.timeIntervalSince1970) - 14 * 86_400
        let windowEnd   = Int(now.timeIntervalSince1970) + 86_400   // +1 day buffer
        lastNight = (try? await store.sleepSessions(deviceId: deviceId,
                                                    from: windowStart,
                                                    to: windowEnd,
                                                    limit: 50))?.last
        await refreshLocalProcessingStateFromStore()
    }

    // MARK: - Refresh from local compute then reload

    /// Recompute on-device metrics, then reload the canonical local rows from WhoopStore.
    func refresh() async {
        await runLocalProcessingNow(trigger: .manual)
    }

    // MARK: - Range reads for Trends/Sleep tabs

    /// Daily metrics for a day range (YYYY-MM-DD bounds, inclusive). Reads straight from cache.
    func daily(fromDay: String, toDay: String) async -> [DailyMetric] {
        await ensureOpen()
        guard let store else { return [] }
        return (try? await store.dailyMetrics(deviceId: deviceId, from: fromDay, to: toDay)) ?? []
    }

    /// Sleep sessions overlapping [from, to] (epoch seconds). Reads straight from cache.
    func sleepSessions(from: Int, to: Int, limit: Int) async -> [CachedSleepSession] {
        await ensureOpen()
        guard let store else { return [] }
        return (try? await store.sleepSessions(deviceId: deviceId, from: from, to: to, limit: limit)) ?? []
    }

    // MARK: - Local diagnostics

    func localDiagnosticsSnapshot() async -> LocalMetricsDiagnosticsSnapshot? {
        await ensureOpen()
        guard let store else { return nil }
        let snapshot = try? await store.localCountsAndLatestTs(deviceId: deviceId)
        let metricDiagnostics = (try? await store.metricDiagnosticEntries(deviceId: deviceId)) ?? []
        if snapshot == nil && metricDiagnostics.isEmpty { return nil }
        return LocalMetricsDiagnosticsSnapshot(localStore: snapshot, metricDiagnostics: metricDiagnostics)
    }

    // MARK: - Profile (M0.5)

    /// Best-effort GET /v1/profile. Returns nil when unconfigured or on error.
    func getProfile() async -> Profile? {
        await ensureOpen()
        return await serverSync?.getProfile()
    }

    /// Best-effort POST /v1/profile. Returns true on 2xx, false when unconfigured or on error.
    func putProfile(_ profile: Profile) async -> Bool {
        await ensureOpen()
        return await serverSync?.putProfile(profile) ?? false
    }

    // MARK: - Sleep tab reads (M2)

    /// Returns the most-recent sleep session paired with the `DailyMetric` for the day its
    /// `endTs` falls on (UTC date), or nil when there are no cached sessions.
    ///
    /// The session carries stagesJSON / efficiency / RHR / HRV; the daily row carries stage
    /// minutes, disturbances, total_sleep_min, and the new in-sleep signals (spo2/skin-temp/resp).
    /// The Sleep tab reads both from this single call to avoid two separate async round-trips.
    func sleepDetail() async -> (session: CachedSleepSession, daily: DailyMetric?)? {
        await ensureOpen()
        guard let store else { return nil }

        // Fetch the most-recent session from the last 14 days.
        let now = Int(Date().timeIntervalSince1970)
        let windowStart = now - 14 * 86_400
        let windowEnd   = now + 86_400
        guard let session = (try? await store.sleepSessions(deviceId: deviceId,
                                                            from: windowStart,
                                                            to: windowEnd,
                                                            limit: 50))?.last else { return nil }

        // Derive the YYYY-MM-DD day that the session's endTs falls on (UTC).
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyy-MM-dd"
        let endDate = Date(timeIntervalSince1970: TimeInterval(session.endTs))
        let day = fmt.string(from: endDate)

        // Look up the daily row for that exact day.
        let daily = (try? await store.dailyMetrics(deviceId: deviceId, from: day, to: day))?.first

        return (session: session, daily: daily)
    }

    /// Calculates the local v1 Sleep Score from cached raw-derived sleep metrics. The score is
    /// intentionally app-owned: it uses our sleep session + daily aggregates, not WHOOP API scores.
    func sleepScore() async -> SleepScoreResult {
        await ensureOpen()
        guard let store else {
            return SleepScoreResult(score: nil,
                                    status: .insufficientData,
                                    baselineProgress: 0,
                                    requiredBaselineNights: SleepScoreCalculator.requiredBaselineNights,
                                    components: nil,
                                    explanation: "Insufficient sleep data")
        }

        let now = Date()
        let nowEpoch = Int(now.timeIntervalSince1970)
        let windowStart = nowEpoch - 90 * 86_400
        let windowEnd = nowEpoch + 86_400
        let sessions = (try? await store.sleepSessions(deviceId: deviceId,
                                                       from: windowStart,
                                                       to: windowEnd,
                                                       limit: 120)) ?? []

        let dayFormatter = Self.utcDayFormatter()
        let fromDay = dayFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(windowStart)))
        let toDay = dayFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(windowEnd)))
        let dailyRows = (try? await store.dailyMetrics(deviceId: deviceId, from: fromDay, to: toDay)) ?? []
        let dailyByDay = Dictionary(uniqueKeysWithValues: dailyRows.map { ($0.day, $0) })

        let nights = sessions.map { session in
            let day = dayFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(session.endTs)))
            return Self.sleepScoreNight(from: session, daily: dailyByDay[day])
        }

        return SleepScoreCalculator.calculate(for: nights.last, history: nights)
    }

    /// Calculates the app-owned Recovery Score from cached sleep and daily rows.
    /// Recovery is anchored to the main sleep session ending on the selected day and
    /// uses only valid previous nights for the personalized baseline.
    func recoveryScore(for date: Date = Date()) async -> RecoveryScore? {
        await ensureOpen()
        guard let store else { return nil }

        let nowEpoch = Int(date.timeIntervalSince1970)
        let windowStart = nowEpoch - 90 * 86_400
        let windowEnd = nowEpoch + 86_400
        let sessions = (try? await store.sleepSessions(deviceId: deviceId,
                                                       from: windowStart,
                                                       to: windowEnd,
                                                       limit: 140)) ?? []

        let dayFormatter = Self.utcDayFormatter()
        let fromDay = dayFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(windowStart)))
        let toDay = dayFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(windowEnd)))
        let dailyRows = (try? await store.dailyMetrics(deviceId: deviceId, from: fromDay, to: toDay)) ?? []

        let targetDate = lastNight.map { Date(timeIntervalSince1970: TimeInterval($0.endTs)) } ?? date
        return RecoveryRepository.getRecovery(for: targetDate, sessions: sessions, dailyRows: dailyRows)
    }

    /// Returns up to `nights` most-recent sleep sessions, ordered oldest→newest, for the
    /// fall-asleep(startTs)/wake(endTs) trend chart on the Sleep tab.
    ///
    /// Fetches a slightly wider window (`nights + 2` days) so a session that started just before
    /// the window boundary is still included, then trims to the last `nights` entries.
    func sevenNightSleepWake(nights: Int = 7) async -> [CachedSleepSession] {
        await ensureOpen()
        guard let store else { return [] }

        let now = Int(Date().timeIntervalSince1970)
        let windowStart = now - (nights + 2) * 86_400
        let windowEnd   = now + 86_400
        let sessions = (try? await store.sleepSessions(deviceId: deviceId,
                                                       from: windowStart,
                                                       to: windowEnd,
                                                       limit: nights + 2)) ?? []
        // sleepSessions returns ASC by startTs; take the last `nights` (most-recent), keep ASC order.
        return Array(sessions.suffix(nights))
    }

    private static func sleepScoreNight(from session: CachedSleepSession, daily: DailyMetric?) -> SleepScoreNight {
        let timeInBed = max(0, Double(session.endTs - session.startTs) / 60)
        let stageSummary = SleepStageSummary(stagesJSON: session.stagesJSON, sessionStartTs: session.startTs)
        let timeAsleep = positive(daily?.totalSleepMin)
            ?? stageSummary?.timeAsleepMinutes
            ?? {
                let efficiency = positive(daily?.efficiency) ?? positive(session.efficiency)
                return efficiency.map { timeInBed * $0 }
            }()

        return SleepScoreNight(
            sleepStart: Date(timeIntervalSince1970: TimeInterval(session.startTs)),
            sleepEnd: Date(timeIntervalSince1970: TimeInterval(session.endTs)),
            timeAsleepMinutes: timeAsleep,
            timeInBedMinutes: timeInBed > 0 ? timeInBed : nil,
            wakeAfterSleepOnsetMinutes: stageSummary?.wakeAfterSleepOnsetMinutes
                ?? timeAsleep.map { max(0, timeInBed - $0) },
            wakeEventCount: daily?.disturbances ?? stageSummary?.wakeEventCount,
            deepSleepMinutes: positive(daily?.deepMin) ?? stageSummary?.deepSleepMinutes,
            remSleepMinutes: positive(daily?.remMin) ?? stageSummary?.remSleepMinutes,
            averageSleepingHR: daily?.restingHr.map(Double.init) ?? session.restingHr.map(Double.init),
            averageHRV: daily?.avgHrv ?? session.avgHrv,
            respiratoryRate: daily?.respRateBpm,
            spo2: daily?.spo2Pct,
            skinTemperatureDeviationC: daily?.skinTempDevC,
            restlessnessRatio: nil
        )
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func utcDayFormatter() -> DateFormatter {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }

    // MARK: - Raw HR series (downsampled stream, for Trends card + HeartRateDetailView)

    /// Fetch a downsampled local HR series for a given epoch-second window.
    func hrSeries(fromEpoch: Int, toEpoch: Int, maxPoints: Int) async -> [TrendPoint] {
        await ensureOpen()
        guard let store else { return [] }
        let raw = (try? await store.hrSamples(deviceId: deviceId, from: fromEpoch, to: toEpoch, limit: maxPoints * 12)) ?? []
        let sampled = Self.downsample(hr: raw, maxPoints: maxPoints)
        return sampled.map { pair in
            TrendPoint(
                id: "\(pair.ts)",
                date: Date(timeIntervalSince1970: TimeInterval(pair.ts)),
                value: Double(pair.bpm)
            )
        }
    }

    // MARK: - Workouts (M5)

    /// Reads locally-stored workout sessions for the given UTC day range.
    func workouts(from: String, to: String) async -> [Workout] {
        await ensureOpen()
        guard let store,
              let fromDate = Self.utcDayFormatter().date(from: from),
              let toDate = Self.utcDayFormatter().date(from: to) else { return [] }
        let sessions = (try? await store.workoutSessions(deviceId: deviceId)) ?? []
        return sessions.compactMap { session in
            let startTs = Int(session.startTime.timeIntervalSince1970)
            guard startTs >= Int(fromDate.timeIntervalSince1970),
                  startTs <= Int(toDate.timeIntervalSince1970) + 86_399 else { return nil }
            return Workout(
                id: "\(deviceId)|\(startTs)",
                deviceId: deviceId,
                startTs: startTs,
                endTs: session.endTime.map { Int($0.timeIntervalSince1970) } ?? startTs,
                avgHr: session.averageHeartRate ?? 0,
                peakHr: Int(session.maxHeartRate ?? session.averageHeartRate ?? 0),
                strain: session.strainScore,
                kind: session.type.rawValue,
                durationS: Int(session.duration),
                zoneTimePct: session.zoneBreakdown.percentages,
                avgHrrPct: nil,
                hrmax: session.maxHeartRate,
                hrmaxSource: "local",
                caloriesKcal: nil,
                caloriesKj: nil
            )
        }
    }

    // MARK: - Workout calorie backfill (M7)

    /// Asks the server to recompute calorie estimates for workouts in [from, to] (YYYY-MM-DD UTC).
    /// Fire-and-forget: the caller should not await a meaningful result; returns false silently if
    /// unconfigured or the request fails. Never throws.
    @discardableResult
    func backfillWorkouts(from: String, to: String) async -> Bool {
        await ensureOpen()
        return await serverSync?.backfillWorkouts(from: from, to: to) ?? false
    }

    // MARK: - Local processing scheduler

    func startLocalProcessing() {
        scheduleLocalProcessing(trigger: .launch, minimumDelay: 0.5, force: true)
    }

    func noteAppForegrounded() {
        scheduleLocalProcessing(trigger: .foreground, minimumDelay: 0.5, force: true)
    }

    func noteWorkoutEnded() {
        scheduleLocalProcessing(trigger: .workoutEnded, minimumDelay: 1.0, force: true)
    }

    func noteNewBiometricSamples() {
        scheduleLocalProcessing(trigger: .samplesArrived, minimumDelay: 10.0, force: false)
    }

    func runLocalProcessingNow(trigger: LocalProcessingTrigger = .manual) async {
        await ensureOpen()
        guard let store else { return }
        scheduledComputeTask?.cancel()
        isRefreshing = true
        lastError = nil
        localProcessingState = localProcessingState.started(trigger: trigger)
        let startedAt = Date()
        do {
            try await engine.recompute(store: store, deviceId: deviceId)
            lastAutoComputeAt = Date()
            await load()
            let duration = Date().timeIntervalSince(startedAt)
            localProcessingState = await makeProcessingState(trigger: trigger,
                                                             startedAt: startedAt,
                                                             duration: duration,
                                                             result: "success")
            lastRefreshedAt = Date()
            if let metric = today, let recovery = metric.recovery {
                RecoveryNotifier.notify(recovery: recovery, forDay: metric.day)
            }
        } catch {
            lastError = "Local metric recompute failed: \(error.localizedDescription)"
            let duration = Date().timeIntervalSince(startedAt)
            localProcessingState = localProcessingState.finished(trigger: trigger,
                                                                 duration: duration,
                                                                 result: "failed",
                                                                 lastError: error.localizedDescription)
        }
        isRefreshing = false
    }

    private func scheduleLocalProcessing(trigger: LocalProcessingTrigger,
                                         minimumDelay: TimeInterval,
                                         force: Bool) {
        let now = Date()
        if !force, let lastAutoComputeAt, now.timeIntervalSince(lastAutoComputeAt) < 60 {
            localProcessingState = localProcessingState.withSkip(trigger: trigger, reason: "throttled")
            return
        }
        scheduledComputeTask?.cancel()
        localProcessingState = localProcessingState.withPending(trigger: trigger)
        scheduledComputeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if minimumDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(minimumDelay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await self.runLocalProcessingNow(trigger: trigger)
        }
    }

    private func refreshLocalProcessingStateFromStore() async {
        await ensureOpen()
        guard let store else { return }
        let snapshot = try? await store.localCountsAndLatestTs(deviceId: deviceId)
        let entries = (try? await store.metricDiagnosticEntries(deviceId: deviceId)) ?? []
        localProcessingState = localProcessingState.merging(snapshot: snapshot, diagnostics: entries)
    }

    private func makeProcessingState(trigger: LocalProcessingTrigger,
                                     startedAt: Date,
                                     duration: TimeInterval,
                                     result: String) async -> LocalProcessingState {
        await ensureOpen()
        guard let store else {
            return localProcessingState.finished(trigger: trigger,
                                                 duration: duration,
                                                 result: result,
                                                 lastError: "local store unavailable")
        }
        let snapshot = try? await store.localCountsAndLatestTs(deviceId: deviceId)
        let entries = (try? await store.metricDiagnosticEntries(deviceId: deviceId)) ?? []
        return LocalProcessingState(localProcessingEnabled: true,
                                    serverSyncOptional: true,
                                    lastTrigger: trigger,
                                    lastComputeAt: startedAt,
                                    lastComputeDuration: duration,
                                    lastComputeResult: result,
                                    dailyComputed: snapshot?.dailyMetrics.count ?? 0 > 0,
                                    recoveryComputed: snapshot?.recoveryMetrics.count ?? 0 > 0,
                                    strainComputed: snapshot?.strainMetrics.count ?? 0 > 0,
                                    sleepComputed: snapshot?.sleepSessions.count ?? 0 > 0,
                                    workoutComputed: snapshot?.workouts.count ?? 0 > 0,
                                    lastComputeError: nil,
                                    reason: nil,
                                    diagnostics: entries,
                                    snapshot: snapshot)
    }

    private func configureLocalProcessingObservers() {
        NotificationCenter.default.publisher(for: .didPersistLocalBiometrics)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.noteNewBiometricSamples()
            }
            .store(in: &cancellables)
    }

    private static func downsample(hr: [HRSample], maxPoints: Int) -> [HRSample] {
        guard maxPoints > 0, hr.count > maxPoints else { return hr }
        let strideValue = max(1, hr.count / maxPoints)
        return hr.enumerated().compactMap { index, sample in
            index.isMultiple(of: strideValue) ? sample : nil
        }
    }
}

enum LocalProcessingTrigger: String, Equatable {
    case launch
    case foreground
    case samplesArrived
    case workoutEnded
    case manual
}

struct LocalProcessingState: Equatable {
    let localProcessingEnabled: Bool
    let serverSyncOptional: Bool
    let lastTrigger: LocalProcessingTrigger?
    let lastComputeAt: Date?
    let lastComputeDuration: TimeInterval?
    let lastComputeResult: String?
    let dailyComputed: Bool
    let recoveryComputed: Bool
    let strainComputed: Bool
    let sleepComputed: Bool
    let workoutComputed: Bool
    let lastComputeError: String?
    let reason: String?
    let diagnostics: [MetricDiagnosticEntry]
    let snapshot: LocalStoreSnapshot?

    init(localProcessingEnabled: Bool = true,
         serverSyncOptional: Bool = true,
         lastTrigger: LocalProcessingTrigger? = nil,
         lastComputeAt: Date? = nil,
         lastComputeDuration: TimeInterval? = nil,
         lastComputeResult: String? = nil,
         dailyComputed: Bool = false,
         recoveryComputed: Bool = false,
         strainComputed: Bool = false,
         sleepComputed: Bool = false,
         workoutComputed: Bool = false,
         lastComputeError: String? = nil,
         reason: String? = nil,
         diagnostics: [MetricDiagnosticEntry] = [],
         snapshot: LocalStoreSnapshot? = nil) {
        self.localProcessingEnabled = localProcessingEnabled
        self.serverSyncOptional = serverSyncOptional
        self.lastTrigger = lastTrigger
        self.lastComputeAt = lastComputeAt
        self.lastComputeDuration = lastComputeDuration
        self.lastComputeResult = lastComputeResult
        self.dailyComputed = dailyComputed
        self.recoveryComputed = recoveryComputed
        self.strainComputed = strainComputed
        self.sleepComputed = sleepComputed
        self.workoutComputed = workoutComputed
        self.lastComputeError = lastComputeError
        self.reason = reason
        self.diagnostics = diagnostics
        self.snapshot = snapshot
    }

    func started(trigger: LocalProcessingTrigger) -> LocalProcessingState {
        LocalProcessingState(localProcessingEnabled: localProcessingEnabled,
                             serverSyncOptional: serverSyncOptional,
                             lastTrigger: trigger,
                             lastComputeAt: Date(),
                             lastComputeDuration: lastComputeDuration,
                             lastComputeResult: "running",
                             dailyComputed: dailyComputed,
                             recoveryComputed: recoveryComputed,
                             strainComputed: strainComputed,
                             sleepComputed: sleepComputed,
                             workoutComputed: workoutComputed,
                             lastComputeError: nil,
                             reason: nil,
                             diagnostics: diagnostics,
                             snapshot: snapshot)
    }

    func finished(trigger: LocalProcessingTrigger,
                  duration: TimeInterval,
                  result: String,
                  lastError: String?) -> LocalProcessingState {
        LocalProcessingState(localProcessingEnabled: localProcessingEnabled,
                             serverSyncOptional: serverSyncOptional,
                             lastTrigger: trigger,
                             lastComputeAt: lastComputeAt ?? Date(),
                             lastComputeDuration: duration,
                             lastComputeResult: result,
                             dailyComputed: dailyComputed,
                             recoveryComputed: recoveryComputed,
                             strainComputed: strainComputed,
                             sleepComputed: sleepComputed,
                             workoutComputed: workoutComputed,
                             lastComputeError: lastError,
                             reason: lastError,
                             diagnostics: diagnostics,
                             snapshot: snapshot)
    }

    func withPending(trigger: LocalProcessingTrigger) -> LocalProcessingState {
        LocalProcessingState(localProcessingEnabled: localProcessingEnabled,
                             serverSyncOptional: serverSyncOptional,
                             lastTrigger: trigger,
                             lastComputeAt: lastComputeAt,
                             lastComputeDuration: lastComputeDuration,
                             lastComputeResult: "scheduled",
                             dailyComputed: dailyComputed,
                             recoveryComputed: recoveryComputed,
                             strainComputed: strainComputed,
                             sleepComputed: sleepComputed,
                             workoutComputed: workoutComputed,
                             lastComputeError: nil,
                             reason: nil,
                             diagnostics: diagnostics,
                             snapshot: snapshot)
    }

    func withSkip(trigger: LocalProcessingTrigger, reason: String) -> LocalProcessingState {
        LocalProcessingState(localProcessingEnabled: localProcessingEnabled,
                             serverSyncOptional: serverSyncOptional,
                             lastTrigger: trigger,
                             lastComputeAt: lastComputeAt,
                             lastComputeDuration: lastComputeDuration,
                             lastComputeResult: "skipped",
                             dailyComputed: dailyComputed,
                             recoveryComputed: recoveryComputed,
                             strainComputed: strainComputed,
                             sleepComputed: sleepComputed,
                             workoutComputed: workoutComputed,
                             lastComputeError: nil,
                             reason: reason,
                             diagnostics: diagnostics,
                             snapshot: snapshot)
    }

    func merging(snapshot: LocalStoreSnapshot?, diagnostics: [MetricDiagnosticEntry]) -> LocalProcessingState {
        LocalProcessingState(localProcessingEnabled: localProcessingEnabled,
                             serverSyncOptional: serverSyncOptional,
                             lastTrigger: lastTrigger,
                             lastComputeAt: lastComputeAt,
                             lastComputeDuration: lastComputeDuration,
                             lastComputeResult: lastComputeResult,
                             dailyComputed: snapshot?.dailyMetrics.count ?? 0 > 0,
                             recoveryComputed: snapshot?.recoveryMetrics.count ?? 0 > 0,
                             strainComputed: snapshot?.strainMetrics.count ?? 0 > 0,
                             sleepComputed: snapshot?.sleepSessions.count ?? 0 > 0,
                             workoutComputed: snapshot?.workouts.count ?? 0 > 0,
                             lastComputeError: lastComputeError,
                             reason: reason,
                             diagnostics: diagnostics,
                             snapshot: snapshot)
    }
}

extension Notification.Name {
    static let didPersistLocalBiometrics = Notification.Name("OpenWhoop.didPersistLocalBiometrics")
}

struct LocalMetricsDiagnosticsSnapshot: Equatable {
    let localStore: LocalStoreSnapshot?
    let metricDiagnostics: [MetricDiagnosticEntry]
}

private struct SleepStageSummary {
    let timeAsleepMinutes: Double
    let wakeAfterSleepOnsetMinutes: Double
    let wakeEventCount: Int
    let deepSleepMinutes: Double
    let remSleepMinutes: Double

    init?(stagesJSON: String?, sessionStartTs: Int) {
        guard let stagesJSON,
              let data = stagesJSON.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        var timeAsleep = 0.0
        var wakeAfterSleepOnset = 0.0
        var wakeEventCount = 0
        var deep = 0.0
        var rem = 0.0
        var hasSleepStarted = false

        for segment in raw {
            guard let start = Self.double(segment["start"]),
                  let end = Self.double(segment["end"]),
                  end > start,
                  let stage = segment["stage"] as? String else { continue }

            let minutes = (end - start) / 60
            switch stage.lowercased() {
            case "wake", "awake":
                if hasSleepStarted {
                    wakeAfterSleepOnset += minutes
                    if minutes >= 2 { wakeEventCount += 1 }
                } else if Int(start) > sessionStartTs {
                    continue
                }
            case "deep":
                hasSleepStarted = true
                timeAsleep += minutes
                deep += minutes
            case "rem":
                hasSleepStarted = true
                timeAsleep += minutes
                rem += minutes
            default:
                hasSleepStarted = true
                timeAsleep += minutes
            }
        }

        guard timeAsleep > 0 || wakeAfterSleepOnset > 0 || deep > 0 || rem > 0 else {
            return nil
        }

        self.timeAsleepMinutes = timeAsleep
        self.wakeAfterSleepOnsetMinutes = wakeAfterSleepOnset
        self.wakeEventCount = wakeEventCount
        self.deepSleepMinutes = deep
        self.remSleepMinutes = rem
    }

    private static func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String { return Double(value) }
        return nil
    }
}
