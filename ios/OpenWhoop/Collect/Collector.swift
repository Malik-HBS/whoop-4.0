import Foundation
import WhoopProtocol
import WhoopStore

/// Source of a live heart-rate sample. Determines dedupe key and diagnostics.
enum LiveHeartRateSource: Equatable {
    case standardBLE2A37
    case whoopRealtime40
}

struct LiveHeartRatePersistResult: Equatable {
    let attemptedHR: Bool
    let insertedHR: Bool
    let attemptedRRCount: Int
    let insertedRRCount: Int
    let hrDeduped: Bool
    let dedupeReason: String?
    let errorDescription: String?

    static func failed(attemptedHR: Bool, attemptedRRCount: Int, error: String) -> Self {
        Self(
            attemptedHR: attemptedHR,
            insertedHR: false,
            attemptedRRCount: attemptedRRCount,
            insertedRRCount: 0,
            hrDeduped: false,
            dedupeReason: nil,
            errorDescription: error
        )
    }
}

/// The subset of WhoopStore the Collector needs. A protocol so tests can inject a spy
/// (WhoopStore is `final`). WhoopStore conforms via the extension below.
/// Not @MainActor — the WhoopStore actor's async methods satisfy the async requirements;
/// a @MainActor SpyStore in tests also conforms (async witnesses hop actors).
protocol StoreWriting: AnyObject {
    @discardableResult
    func insert(_ streams: Streams, deviceId: String, markSynced: Bool) async throws
        -> (hr: Int, rr: Int, events: Int, battery: Int,
            spo2: Int, skinTemp: Int, resp: Int, gravity: Int)
    func enqueueRawBatch(_ meta: RawBatchMeta, frames: [[UInt8]]) async throws
}
extension StoreWriting {
    /// Source-compat shim: existing callers (Collector live, Backfiller) call `insert(_:deviceId:)`
    /// with no `markSynced`, meaning the rows still need uploading (synced = 0).
    @discardableResult
    func insert(_ streams: Streams, deviceId: String) async throws
        -> (hr: Int, rr: Int, events: Int, battery: Int,
            spo2: Int, skinTemp: Int, resp: Int, gravity: Int) {
        try await insert(streams, deviceId: deviceId, markSynced: false)
    }
}
extension WhoopStore: StoreWriting {}

/// Cadence: flush after this many buffered frames OR this many seconds since the last
/// flush — whichever first. Also flushed explicitly on disconnect/foreground.
struct CollectorPolicy {
    var maxFrames: Int
    var maxInterval: TimeInterval
    /// Defensive cap on the PRE-CLOCK buffer only (see `ingest`). Generous default —
    /// ~4096 frames at ~60 bytes/frame is ~240KB, far beyond the handful seen pre-clock
    /// normally. Custom init keeps `.init(maxFrames:maxInterval:)` call sites compiling.
    var maxPreClockFrames: Int
    init(maxFrames: Int, maxInterval: TimeInterval, maxPreClockFrames: Int = 4096) {
        self.maxFrames = maxFrames
        self.maxInterval = maxInterval
        self.maxPreClockFrames = maxPreClockFrames
    }
    static let `default` = CollectorPolicy(maxFrames: 64, maxInterval: 30, maxPreClockFrames: 4096)
}

/// Buffers complete (reassembled) frames and periodically persists them:
/// parse → extractStreams(clockRef) → store.insert (DECODED FIRST, durable) →
/// store.enqueueRawBatch (raw, transient outbox) → clear buffer.
/// Because decoded is committed before raw is queued, pruning raw never loses a metric.
@MainActor
final class Collector {
    private let store: StoreWriting
    /// Concrete store for prune + stats (the StoreWriting seam covers the hot insert/enqueue path;
    /// prune/stats are infrequent so a direct reference is clearer than widening the protocol).
    private let concreteStore: WhoopStore?
    private let deviceId: String
    private let policy: CollectorPolicy
    /// Research toggle. When false (DEFAULT) no raw frames are persisted at all — the app is
    /// decoded-only. Injected for tests; backed by UserDefaults in the production init site.
    private let enableRawCapture: Bool
    private weak var stepCountingService: StepCountingService?
    private let now: () -> Int
    private let monotonic: () -> TimeInterval

    /// Set once the GET_CLOCK correlation lands (E1). Until then, frames buffer un-persisted.
    var clockRef: ClockRef?
    /// On-demand bounded raw-capture window. ORs into the raw-persist gate so a "capture
    /// activity sample" action can persist raw even when `enableRawCapture` is off. The window's
    /// monotonic deadline auto-expires so a missed stop callback can't leak raw forever.
    private var rawCapture = RawCaptureWindow()
    private var buffer: [[UInt8]] = []
    private var batchStartedAt: TimeInterval
    var bufferedCount: Int { buffer.count }

    struct GravityDeriveStats: Equatable {
        let imuFrames: Int
        let opticalFrames: Int
        let unknownFrames: Int
        let derivedRows: Int
    }

    init(store: StoreWriting, deviceId: String,
         policy: CollectorPolicy = .default,
         enableRawCapture: Bool = false,
         stepCountingService: StepCountingService? = nil,
         now: @escaping () -> Int = { Int(Date().timeIntervalSince1970) },
         monotonic: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }) {
        self.store = store; self.deviceId = deviceId; self.policy = policy
        self.enableRawCapture = enableRawCapture
        self.stepCountingService = stepCountingService
        self.now = now; self.monotonic = monotonic
        self.batchStartedAt = monotonic()
        self.concreteStore = store as? WhoopStore
    }

    /// Light storage summary for the UI. nil if there's no concrete store or the read throws.
    func storageStats() async -> (decodedRows: Int, rawBatches: Int, rawBytes: Int)? {
        guard let s = concreteStore else { return nil }
        return try? await s.storageStats()
    }

    /// Per-decoded-stream count + latest-ts snapshot for THIS device. nil without a concrete
    /// store. Used by the developer diagnostics UI to localise pipeline breaks (collected
    /// but not uploaded vs collected and uploaded vs never collected). Mirrors `storageStats()`
    /// nil-when-no-store semantics.
    func localStoreSnapshot() async -> LocalStoreSnapshot? {
        guard let s = concreteStore else { return nil }
        return try? await s.localCountsAndLatestTs(deviceId: deviceId)
    }

    func latestRawBatchCapturedAt() async -> Date? {
        guard let s = concreteStore,
              let capturedAt = try? await s.latestRawBatchCapturedAt() else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(capturedAt))
    }

    /// Max persisted HR sample ts (the biometric "data frontier" for the stuck-strap watchdog).
    /// nil if there's no concrete store or nothing persisted yet. Mirrors storageStats().
    func latestHRSampleTs() async -> Int? {
        guard let s = concreteStore else { return nil }
        return try? await s.latestHRSampleTs(deviceId: deviceId)
    }

    /// Apply the raw-retention policy. Returns rows pruned (0 if no concrete store).
    @discardableResult
    func prune() async -> Int {
        guard let s = concreteStore else { return 0 }
        return (try? await s.pruneRaw(now: now(),
                                keepWindowSeconds: PrunePolicy.keepWindowSeconds,
                                maxUnsyncedBytes: PrunePolicy.maxUnsyncedBytes)) ?? 0
    }

    /// Buffer one complete frame (synchronous: preserves delegate arrival order).
    /// Auto-flushes via a detached Task when the cadence threshold is hit (flush is async).
    func ingest(_ frame: [UInt8]) {
        buffer.append(frame)
        // Pre-clock only: bound memory if GET_CLOCK never lands while data keeps flowing.
        // Drop OLDEST beyond the cap (keep most recent). Post-clock this branch is skipped —
        // the cadence flush below bounds the buffer instead.
        if clockRef == nil && buffer.count > policy.maxPreClockFrames {
            buffer.removeFirst(buffer.count - policy.maxPreClockFrames)
        }
        guard clockRef != nil else { return }   // can't correlate ts yet → keep buffering
        if buffer.count >= policy.maxFrames || (monotonic() - batchStartedAt) >= policy.maxInterval {
            Task { @MainActor in await self.flush() }
        }
    }

    /// Persist + queue everything buffered. No-op when empty or before a clock ref exists.
    /// Buffer is snapshotted and cleared SYNCHRONOUSLY before the first await so that any
    /// concurrent ingest() calls during persistence accumulate into the NEXT batch cleanly.
    func flush() async {
        guard let ref = clockRef, !buffer.isEmpty else { return }
        // SNAPSHOT + CLEAR before any await: decoded-before-raw ordering AND the
        // buffer-snapshot-before-await invariant are both satisfied here.
        let frames = buffer
        buffer.removeAll(keepingCapacity: true)

        let parsed = frames.map { parseFrame($0) }
        var streams = extractStreams(parsed, deviceClockRef: ref.device, wallClockRef: ref.wall)
        let accelerometerSamples = extractAccelerometerSamples(from: frames,
                                                               deviceClockRef: ref.device,
                                                               wallClockRef: ref.wall)
        let gravityResult = deriveGravityRows(from: frames, accelerometerSamples: accelerometerSamples)
        streams.gravity = gravityResult.rows
        do {
            let inserted = try await store.insert(streams, deviceId: deviceId)   // DECODED FIRST (durable)
            let gravityStats = gravityResult.stats
            if gravityStats.derivedRows > 0 || gravityStats.imuFrames > 0
                || gravityStats.opticalFrames > 0 || gravityStats.unknownFrames > 0 {
                BLEDiagnostics.shared.recordType43CollectorStats(
                    imuFrames: gravityStats.imuFrames,
                    opticalFrames: gravityStats.opticalFrames,
                    unknownFrames: gravityStats.unknownFrames,
                    gravityRowsDerived: gravityStats.derivedRows,
                    gravityRowsSaved: inserted.gravity
                )
            }
        } catch {
            // Re-buffer at the front so these frames are retried on the next cadence.
            buffer.insert(contentsOf: frames, at: 0)
            return
        }
        if !accelerometerSamples.isEmpty {
            stepCountingService?.ingestAccelerometerSamples(accelerometerSamples)
        }
        // Reset only after a successful insert so the interval trigger keeps firing if
        // inserts fail (batchStartedAt must NOT advance on a failed drain).
        batchStartedAt = monotonic()
        // RAW SECOND (transient outbox), only when the research toggle is ON. Default OFF →
        // decoded-only, no raw is stored. Failure is non-fatal — decoded is already durable.
        guard enableRawCapture || rawCapture.isActive(at: monotonic()) else { return }
        let wall = now()
        let tsValues = streams.hr.map(\.ts) + streams.rr.map(\.ts)
            + streams.events.map(\.ts) + streams.battery.map(\.ts)
        let meta = RawBatchMeta(
            batchId: UUID().uuidString, deviceId: deviceId, clockRef: ref, capturedAt: wall,
            startTs: tsValues.min() ?? wall, endTs: tsValues.max() ?? wall,
            frameCount: frames.count, byteSize: frames.reduce(0) { $0 + $1.count })
        try? await store.enqueueRawBatch(meta, frames: frames)
    }

    private func deriveGravityRows(from frames: [[UInt8]],
                                   accelerometerSamples: [AccelerometerSample]) -> (rows: [GravitySample], stats: GravityDeriveStats) {
        var imuFrames = 0
        var opticalFrames = 0
        var unknownFrames = 0
        for frame in frames {
            guard let info = type43PacketInfo(from: frame) else { continue }
            switch info.kind {
            case .imu:
                imuFrames += 1
            case .optical:
                opticalFrames += 1
            case .unknown:
                unknownFrames += 1
            }
        }

        guard !accelerometerSamples.isEmpty else {
            return ([], GravityDeriveStats(imuFrames: imuFrames,
                                           opticalFrames: opticalFrames,
                                           unknownFrames: unknownFrames,
                                           derivedRows: 0))
        }

        var buckets: [Int: [AccelerometerSample]] = [:]
        for sample in accelerometerSamples {
            let ts = Int(sample.timestamp.timeIntervalSince1970)
            buckets[ts, default: []].append(sample)
        }

        let rows = buckets.keys.sorted().compactMap { ts -> GravitySample? in
            guard let samples = buckets[ts], !samples.isEmpty else { return nil }
            let count = Double(samples.count)
            let meanX = samples.reduce(0.0) { $0 + $1.x } / count
            let meanY = samples.reduce(0.0) { $0 + $1.y } / count
            let meanZ = samples.reduce(0.0) { $0 + $1.z } / count
            let magnitude = sqrt(meanX * meanX + meanY * meanY + meanZ * meanZ)
            guard magnitude > 0 else { return nil }
            return GravitySample(ts: ts,
                                 x: meanX / magnitude,
                                 y: meanY / magnitude,
                                 z: meanZ / magnitude)
        }

        return (rows, GravityDeriveStats(imuFrames: imuFrames,
                                         opticalFrames: opticalFrames,
                                         unknownFrames: unknownFrames,
                                         derivedRows: rows.count))
    }

    // MARK: - On-demand raw capture

    /// Open a bounded raw-capture window so the next flushes persist raw even with the global
    /// research toggle off. Auto-expires at the (clamped) monotonic deadline.
    func beginRawCapture(seconds: TimeInterval) {
        rawCapture.open(at: monotonic(), duration: seconds)
    }

    /// Flush WHILE the window is still active so the just-captured frames get persisted as raw,
    /// THEN close the window.
    func endRawCapture() async {
        await flush()
        rawCapture.close()
    }

    // MARK: - Live Heart Rate persistence (standard BLE 0x2A37 + WHOOP frame 40 REALTIME_DATA)
    //
    // Both sources route through the same `store.insert(streams:)` path so the Uploader +
    // ServerSync pipelines pick them up unchanged (History = union(phone, server), no schema split).
    // Dedupe is per-source: standard BLE uses (bpm, second), frame 40 uses (bpm, device-ts second).

    /// Last HR bpm + ts persisted per source (used for 1-second-coarse dedupe).
    private var lastLiveHR: [LiveHeartRateSource: (bpm: Int, ts: Int)] = [:]

    /// Persist a live heart-rate measurement into the decoded store.
    ///
    /// - Parameter hr: Heart rate in bpm. 0 is written (server sees the gap); dedupe applies
    ///   only when hr > 0.
    /// - Parameter rrIntervalsMs: R-R intervals in milliseconds. May be empty.
    /// - Parameter wallTime: Wall-clock instant the sample arrived. R-R timestamps walk
    ///   backward from this point so each interval ends at a distinct wall time.
    /// - Parameter source: Origin of the sample — determines dedupe key and diagnostics.
    ///
    /// Dedupe: HR samples with the same bpm AND a wall-time ts within the SAME second are
    /// treated as the same logical reading and skipped (the table's PK (deviceId, ts) would
    /// DO NOTHING them anyway, but skipping at this layer avoids a no-op write per duplicate).
    ///
    /// R-R: wire order is OLDEST FIRST. The "end" of each interval is the moment of the
    /// NEXT beat. For the NEWEST interval that moment is `wallTime`; for each older interval
    /// it is `wallTime` minus the sum of intervals that come AFTER it. Walk newest-first,
    /// record each interval's END-timestamp, then step back by that interval's duration.
    func ingestLiveHeartRate(hr: Int, rrIntervalsMs: [Int], wallTime: Date, source: LiveHeartRateSource) async -> LiveHeartRatePersistResult {
        let wallTs = Int(wallTime.timeIntervalSince1970)
        var streams = Streams()
        let attemptedHR = hr > 0
        let attemptedRRCount = rrIntervalsMs.count
        var dedupeReason: String?

        // HR: dedupe on (bpm, second) per source.
        if hr > 0 {
            let last = lastLiveHR[source]
            let isDuplicate = last.map { $0.bpm == hr && $0.ts == wallTs } ?? false
            if !isDuplicate {
                streams.hr = [HRSample(ts: wallTs, bpm: hr)]
                lastLiveHR[source] = (hr, wallTs)
            } else {
                dedupeReason = "same bpm in same second from \(source)"
            }
        }

        // R-R: walk newest-first from wallTs, record END timestamps, step back by each interval.
        if !rrIntervalsMs.isEmpty {
            var t = Double(wallTs)
            var rrRows: [RRInterval] = []
            rrRows.reserveCapacity(rrIntervalsMs.count)
            for rrMs in rrIntervalsMs.reversed() {
                let safeMs = max(1, rrMs)
                rrRows.append(RRInterval(ts: max(0, Int(t)), rrMs: safeMs))
                t -= Double(safeMs) / 1000.0
            }
            streams.rr = rrRows.reversed()
        }

        if streams.hr.isEmpty && streams.rr.isEmpty {
            return LiveHeartRatePersistResult(
                attemptedHR: attemptedHR,
                insertedHR: false,
                attemptedRRCount: attemptedRRCount,
                insertedRRCount: 0,
                hrDeduped: attemptedHR,
                dedupeReason: dedupeReason ?? "no live HR/RR rows to write",
                errorDescription: nil
            )
        }

        do {
            let inserted = try await store.insert(streams, deviceId: deviceId, markSynced: false)
            let hrDeduped = attemptedHR && !streams.hr.isEmpty && inserted.hr == 0
            let resolvedReason: String?
            if hrDeduped {
                resolvedReason = "hrSample natural-key conflict at same second"
            } else {
                resolvedReason = dedupeReason
            }
            return LiveHeartRatePersistResult(
                attemptedHR: attemptedHR,
                insertedHR: inserted.hr > 0,
                attemptedRRCount: attemptedRRCount,
                insertedRRCount: inserted.rr,
                hrDeduped: (attemptedHR && streams.hr.isEmpty) || hrDeduped,
                dedupeReason: resolvedReason,
                errorDescription: nil
            )
        } catch {
            return .failed(
                attemptedHR: attemptedHR,
                attemptedRRCount: attemptedRRCount,
                error: error.localizedDescription
            )
        }
    }
}
