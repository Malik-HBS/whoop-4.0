import Foundation
import WhoopProtocol
import WhoopStore

public struct HRVComputation: Equatable, Sendable {
    public let rmssd: Double?
    public let sampleCount: Int
    public let confidence: Double?
    public let reason: String?
}

public struct RestingHRComputation: Equatable, Sendable {
    public let bpm: Int?
    public let sampleCount: Int
    public let confidence: Double?
    public let reason: String?
}

public struct StrainComputation: Equatable, Sendable {
    public let score: Double?
    public let sampleCount: Int
    public let activeMinutes: Double
    public let confidence: Double?
    public let reason: String?
}

public struct LocalSleepDetectionResult: Equatable {
    public let session: CachedSleepSession?
    public let reason: String?
}

public struct OnDeviceMetricsEngine {
    public let daysToRecompute: Int
    public let baselineDays: Int

    public init(daysToRecompute: Int = 14, baselineDays: Int = 7) {
        self.daysToRecompute = daysToRecompute
        self.baselineDays = baselineDays
    }

    public func recompute(store: WhoopStore, deviceId: String) async throws {
        let now = Date()
        let nowEpoch = Int(now.timeIntervalSince1970)
        let analysisStart = nowEpoch - max(daysToRecompute + baselineDays + 7, 30) * 86_400

        let hr = try await store.hrSamples(deviceId: deviceId, from: analysisStart, to: nowEpoch + 86_400, limit: 200_000)
        let rr = try await store.rrIntervals(deviceId: deviceId, from: analysisStart, to: nowEpoch + 86_400, limit: 400_000)
        let gravity = try await store.gravitySamples(deviceId: deviceId, from: analysisStart, to: nowEpoch + 86_400, limit: 200_000)
        let spo2 = try await store.spo2Samples(deviceId: deviceId, from: analysisStart, to: nowEpoch + 86_400, limit: 100_000)
        let skin = try await store.skinTempSamples(deviceId: deviceId, from: analysisStart, to: nowEpoch + 86_400, limit: 100_000)
        let resp = try await store.respSamples(deviceId: deviceId, from: analysisStart, to: nowEpoch + 86_400, limit: 100_000)
        let workouts = try await store.workoutSessions(deviceId: deviceId)

        let days = utcDays(endingAt: now, count: daysToRecompute + baselineDays)
        var detectedSessions: [CachedSleepSession] = []
        var dailyMetrics: [DailyMetric] = []
        var recoveryMetrics: [RecoveryMetric] = []
        var strainMetrics: [StrainMetric] = []
        var baselines: [MetricBaseline] = []
        var diagnostics: [MetricDiagnosticEntry] = []

        var computedByDay: [String: DailyMetric] = [:]
        var sleepByDay: [String: CachedSleepSession] = [:]

        for day in days {
            let detection = LocalSleepDetector.detect(forDay: day, hr: hr, rr: rr, gravity: gravity)
            if let session = detection.session {
                detectedSessions.append(session)
                sleepByDay[day] = session
            } else if let reason = detection.reason {
                diagnostics.append(MetricDiagnosticEntry(key: "sleep:\(day)", value: reason, updatedAt: nowEpoch))
            }
        }

        for day in days.suffix(daysToRecompute) {
            let dayStart = utcDate(fromDay: day)?.timeIntervalSince1970 ?? 0
            let dayStartEpoch = Int(dayStart)
            let dayEndEpoch = dayStartEpoch + 86_400 - 1
            let session = sleepByDay[day]
            let dayHR = hr.filter { $0.ts >= dayStartEpoch && $0.ts <= dayEndEpoch }
            let dayRR = rr.filter { $0.ts >= dayStartEpoch && $0.ts <= dayEndEpoch }
            let hrv = LocalHRVComputer.compute(day: day, rr: rr, sleepSession: session)
            let rhr = LocalRestingHRComputer.compute(day: day, hr: hr, gravity: gravity, sleepSession: session)
            let strain = LocalStrainComputer.compute(day: day,
                                                     dayStart: dayStartEpoch,
                                                     dayEnd: dayEndEpoch,
                                                     hr: hr,
                                                     workouts: workouts,
                                                     restingHeartRate: Double(rhr.bpm ?? 60))
            let daily = DailyMetricsAssembler.makeDailyMetric(day: day,
                                                              hr: dayHR,
                                                              rr: dayRR,
                                                              sleepSession: session,
                                                              hrv: hrv,
                                                              restingHR: rhr,
                                                              strain: strain,
                                                              spo2: spo2,
                                                              skinTemp: skin,
                                                              resp: resp)
            dailyMetrics.append(daily)
            computedByDay[day] = daily
            strainMetrics.append(StrainMetric(day: day,
                                              score: strain.score,
                                              status: strain.score == nil ? .unavailable : .ready,
                                              source: .onDevice,
                                              confidence: strain.confidence,
                                              explanation: strain.reason,
                                              recomputedAt: nowEpoch))
            diagnostics.append(MetricDiagnosticEntry(key: "hrv:\(day)",
                                                     value: hrv.reason ?? "ready",
                                                     updatedAt: nowEpoch))
            diagnostics.append(MetricDiagnosticEntry(key: "rhr:\(day)",
                                                     value: rhr.reason ?? "ready",
                                                     updatedAt: nowEpoch))
            diagnostics.append(MetricDiagnosticEntry(key: "strain:\(day)",
                                                     value: strain.reason ?? "ready",
                                                     updatedAt: nowEpoch))
            diagnostics.append(MetricDiagnosticEntry(key: "daily:\(day)",
                                                     value: DailyMetricsAssembler.dailyReason(day: day,
                                                                                             hr: dayHR,
                                                                                             rr: dayRR,
                                                                                             sleepSession: session,
                                                                                             hrv: hrv,
                                                                                             restingHR: rhr,
                                                                                             strain: strain),
                                                     updatedAt: nowEpoch))
        }

        let sortedDays = days.suffix(daysToRecompute)
        for day in sortedDays {
            let history = sortedDays.filter { $0 < day }.compactMap { computedByDay[$0] }
            let current = computedByDay[day]
            let recovery = LocalRecoveryComputer.compute(day: day, current: current, history: history, baselineDays: baselineDays)
            recoveryMetrics.append(recovery.metric)
            if let updated = current {
                let merged = DailyMetric(day: updated.day,
                                         totalSleepMin: updated.totalSleepMin,
                                         efficiency: updated.efficiency,
                                         deepMin: updated.deepMin,
                                         remMin: updated.remMin,
                                         lightMin: updated.lightMin,
                                         disturbances: updated.disturbances,
                                         restingHr: updated.restingHr,
                                         avgHrv: updated.avgHrv,
                                         recovery: recovery.metric.score.map { $0 / 100.0 },
                                         strain: updated.strain,
                                         exerciseCount: updated.exerciseCount,
                                         spo2Pct: updated.spo2Pct,
                                         skinTempDevC: updated.skinTempDevC,
                                         respRateBpm: updated.respRateBpm,
                                         source: .onDevice,
                                         confidence: min(updated.confidence ?? 0.6, recovery.metric.confidence ?? 0.6),
                                         status: recovery.metric.status == .ready ? updated.status : recovery.metric.status,
                                         unavailableReason: updated.unavailableReason ?? recovery.metric.explanation,
                                         recomputedAt: nowEpoch)
                computedByDay[day] = merged
            }
            diagnostics.append(MetricDiagnosticEntry(key: "recovery:\(day)",
                                                     value: recovery.metric.explanation ?? recovery.metric.status.rawValue,
                                                     updatedAt: nowEpoch))
            if let baseline = recovery.baseline {
                baselines.append(baseline)
            }
        }

        try await store.upsertSleepSessions(detectedSessions, deviceId: deviceId)
        try await store.upsertDailyMetrics(sortedDays.compactMap { computedByDay[$0] }, deviceId: deviceId)
        try await store.upsertRecoveryMetrics(recoveryMetrics, deviceId: deviceId)
        try await store.upsertStrainMetrics(strainMetrics, deviceId: deviceId)
        try await store.replaceMetricBaselines(baselines, deviceId: deviceId)
        diagnostics.append(MetricDiagnosticEntry(key: "compute:lastRunAt",
                                                 value: String(nowEpoch),
                                                 updatedAt: nowEpoch))
        diagnostics.append(MetricDiagnosticEntry(key: "compute:dailyComputed",
                                                 value: dailyMetrics.contains(where: { $0.status == .ready }) ? "yes" : "no",
                                                 updatedAt: nowEpoch))
        diagnostics.append(MetricDiagnosticEntry(key: "compute:sleepComputed",
                                                 value: detectedSessions.isEmpty ? "no" : "yes",
                                                 updatedAt: nowEpoch))
        diagnostics.append(MetricDiagnosticEntry(key: "compute:recoveryComputed",
                                                 value: recoveryMetrics.contains(where: { $0.status != .unavailable }) ? "yes" : "no",
                                                 updatedAt: nowEpoch))
        diagnostics.append(MetricDiagnosticEntry(key: "compute:strainComputed",
                                                 value: strainMetrics.contains(where: { $0.status == .ready }) ? "yes" : "no",
                                                 updatedAt: nowEpoch))
        try await store.replaceMetricDiagnostics(diagnostics, deviceId: deviceId)
    }
}

enum LocalHRVComputer {
    static func compute(day: String, rr: [RRInterval], sleepSession: CachedSleepSession?) -> HRVComputation {
        let window = preferredWindow(forDay: day, sleepSession: sleepSession, seconds: 6 * 3_600)
        let rows = rr.filter { $0.ts >= window.start && $0.ts <= window.end }.map(\.rrMs)
        let filtered = clean(rows)
        guard filtered.count >= 20 else {
            return HRVComputation(rmssd: nil,
                                  sampleCount: filtered.count,
                                  confidence: nil,
                                  reason: filtered.isEmpty ? "Not enough clean RR data" : "Building baseline")
        }
        let diffs = zip(filtered.dropFirst(), filtered).map { Double($0 - $1) }
        let rmssd = sqrt(diffs.map { $0 * $0 }.reduce(0, +) / Double(diffs.count))
        let confidence = sleepSession == nil ? 0.45 : 0.78
        return HRVComputation(rmssd: rmssd, sampleCount: filtered.count, confidence: confidence, reason: nil)
    }

    private static func clean(_ rows: [Int]) -> [Int] {
        let plausible = rows.filter { (300...2000).contains($0) }
        guard !plausible.isEmpty else { return [] }
        let median = plausible.sorted()[plausible.count / 2]
        var kept: [Int] = []
        var last: Int?
        for value in plausible {
            guard abs(value - median) <= 250 else { continue }
            if let last, abs(value - last) > 220 { continue }
            kept.append(value)
            last = value
        }
        return kept
    }
}

enum LocalRestingHRComputer {
    static func compute(day: String,
                        hr: [HRSample],
                        gravity: [GravitySample],
                        sleepSession: CachedSleepSession?) -> RestingHRComputation {
        let window = LocalHRVComputer.preferredWindow(forDay: day, sleepSession: sleepSession, seconds: 8 * 3_600)
        let rows = hr.filter { $0.ts >= window.start && $0.ts <= window.end }
        guard rows.count >= 10 else {
            return RestingHRComputation(bpm: nil, sampleCount: rows.count, confidence: nil, reason: "Not enough heart-rate data")
        }
        let gravityRows = gravity.filter { $0.ts >= window.start && $0.ts <= window.end }
        let quietSeconds = quietWindows(from: gravityRows)
        let anchored = quietSeconds.isEmpty ? rows : rows.filter { quietSeconds.contains($0.ts) }
        let windows = stride(from: window.start, through: window.end - 300, by: 300).compactMap { start -> Double? in
            let slice = anchored.filter { $0.ts >= start && $0.ts < start + 300 }
            guard slice.count >= 5 else { return nil }
            return slice.map(\.bpm).reduce(0, +).double / Double(slice.count)
        }
        guard let floor = windows.min() else {
            return RestingHRComputation(bpm: nil, sampleCount: anchored.count, confidence: nil, reason: "Not enough stable resting data")
        }
        return RestingHRComputation(bpm: Int(floor.rounded()),
                                    sampleCount: anchored.count,
                                    confidence: sleepSession == nil ? 0.5 : 0.8,
                                    reason: nil)
    }

    private static func quietWindows(from samples: [GravitySample]) -> Set<Int> {
        guard samples.count > 3 else { return [] }
        var quiet = Set<Int>()
        var previous = samples[0]
        for sample in samples.dropFirst() {
            let delta = sqrt(pow(sample.x - previous.x, 2) + pow(sample.y - previous.y, 2) + pow(sample.z - previous.z, 2))
            if delta < 0.015 {
                quiet.insert(sample.ts)
            }
            previous = sample
        }
        return quiet
    }
}

enum LocalSleepDetector {
    static func detect(forDay day: String,
                       hr: [HRSample],
                       rr: [RRInterval],
                       gravity: [GravitySample]) -> LocalSleepDetectionResult {
        guard let dayDate = utcDate(fromDay: day) else {
            return LocalSleepDetectionResult(session: nil, reason: "Invalid day")
        }
        let end = Int(dayDate.timeIntervalSince1970) + 12 * 3_600
        let start = end - 18 * 3_600
        let hrRows = hr.filter { $0.ts >= start && $0.ts <= end }
        let rrRows = rr.filter { $0.ts >= start && $0.ts <= end }
        let gravityRows = gravity.filter { $0.ts >= start && $0.ts <= end }

        if gravityRows.count >= 60 {
            if let session = detectWithGravity(hrRows: hrRows, gravityRows: gravityRows) {
                return LocalSleepDetectionResult(session: session, reason: nil)
            }
            return LocalSleepDetectionResult(session: nil, reason: "No long rest window")
        }

        guard hrRows.count >= 180 else {
            return LocalSleepDetectionResult(session: nil, reason: "Not enough HR")
        }
        guard rrRows.count >= 20 else {
            return LocalSleepDetectionResult(session: nil, reason: "Not enough RR")
        }
        let startTs = Int(dayDate.timeIntervalSince1970) - 7 * 3_600
        let endTs = startTs + 8 * 3_600
        let session = CachedSleepSession(startTs: startTs,
                                         endTs: endTs,
                                         efficiency: 0.78,
                                         restingHr: nil,
                                         avgHrv: nil,
                                         stagesJSON: nil,
                                         source: .onDevice,
                                         confidence: 0.42,
                                         status: .ready,
                                         unavailableReason: "motion data unavailable",
                                         recomputedAt: Int(Date().timeIntervalSince1970))
        return LocalSleepDetectionResult(session: session, reason: "motion data unavailable")
    }

    private static func detectWithGravity(hrRows: [HRSample], gravityRows: [GravitySample]) -> CachedSleepSession? {
        var bestRange: (start: Int, end: Int, quiet: Int)?
        var runStart: Int?
        var quietCount = 0
        var previous = gravityRows[0]
        for sample in gravityRows.dropFirst() {
            let delta = sqrt(pow(sample.x - previous.x, 2) + pow(sample.y - previous.y, 2) + pow(sample.z - previous.z, 2))
            if delta < 0.015 {
                runStart = runStart ?? previous.ts
                quietCount += 1
            } else if let currentStart = runStart {
                let candidate = (currentStart, previous.ts, quietCount)
                if bestRange == nil || candidate.2 > bestRange?.quiet ?? 0 { bestRange = candidate }
                runStart = nil
                quietCount = 0
            }
            previous = sample
        }
        if let currentStart = runStart {
            let candidate = (currentStart, previous.ts, quietCount)
            if bestRange == nil || candidate.2 > bestRange?.quiet ?? 0 { bestRange = candidate }
        }
        guard let bestRange,
              bestRange.end - bestRange.start >= 3 * 3_600 else { return nil }
        let duration = Double(bestRange.end - bestRange.start) / 60.0
        let interruptions = hrRows.filter { $0.ts >= bestRange.start && $0.ts <= bestRange.end && $0.bpm > 90 }.count
        let efficiency = max(0.65, min(0.97, 0.94 - Double(interruptions) / 400.0))
        let deep = duration * 0.18
        let rem = duration * 0.22
        let wake = duration * (1 - efficiency)
        let stages = [
            ["start": Double(bestRange.start), "end": Double(bestRange.start) + 90 * 60.0, "stage": "light"],
            ["start": Double(bestRange.start) + 90 * 60.0, "end": Double(bestRange.start) + 90 * 60.0 + deep * 60.0, "stage": "deep"],
            ["start": Double(bestRange.end) - rem * 60.0, "end": Double(bestRange.end), "stage": "rem"],
            ["start": Double(bestRange.end) - wake * 60.0, "end": Double(bestRange.end), "stage": "wake"],
        ]
        let stagesJSON = (try? JSONSerialization.data(withJSONObject: stages)).map { String(decoding: $0, as: UTF8.self) }
        return CachedSleepSession(startTs: bestRange.start,
                                  endTs: bestRange.end,
                                  efficiency: efficiency,
                                  restingHr: nil,
                                  avgHrv: nil,
                                  stagesJSON: stagesJSON,
                                  source: .onDevice,
                                  confidence: 0.74,
                                  status: .ready,
                                  unavailableReason: nil,
                                  recomputedAt: Int(Date().timeIntervalSince1970))
    }
}

enum LocalStrainComputer {
    static func compute(day: String,
                        dayStart: Int,
                        dayEnd: Int,
                        hr: [HRSample],
                        workouts: [LocalWorkoutSession],
                        restingHeartRate: Double) -> StrainComputation {
        let dayWorkouts = workouts.filter {
            let ts = Int($0.startTime.timeIntervalSince1970)
            return ts >= dayStart && ts <= dayEnd
        }
        let workoutLoad = dayWorkouts.reduce(0.0) { $0 + $1.totalLoad }
        let hrRows = hr.filter { $0.ts >= dayStart && $0.ts <= dayEnd }.sorted { $0.ts < $1.ts }
        let hrLoad = loadFromHR(rows: hrRows, restingHeartRate: restingHeartRate, maxHeartRate: 190)
        let activeMinutes = activeMinutes(from: hrRows)
        let load = workoutLoad + hrLoad
        guard !hrRows.isEmpty || !dayWorkouts.isEmpty else {
            return StrainComputation(score: nil,
                                     sampleCount: 0,
                                     activeMinutes: 0,
                                     confidence: nil,
                                     reason: "collecting HR data")
        }
        guard activeMinutes >= 5 || workoutLoad > 0 else {
            return StrainComputation(score: nil,
                                     sampleCount: hrRows.count,
                                     activeMinutes: activeMinutes,
                                     confidence: nil,
                                     reason: "insufficientDuration")
        }
        guard load > 0 else {
            return StrainComputation(score: nil,
                                     sampleCount: hrRows.count,
                                     activeMinutes: activeMinutes,
                                     confidence: nil,
                                     reason: "low intensity so far")
        }
        return StrainComputation(score: min(21.0, max(0, 21.0 * log(load + 1.0) / log(7201.0))),
                                 sampleCount: hrRows.count,
                                 activeMinutes: activeMinutes,
                                 confidence: dayWorkouts.isEmpty ? 0.64 : 0.78,
                                 reason: nil)
    }

    private static func loadFromHR(rows: [HRSample], restingHeartRate: Double, maxHeartRate: Double) -> Double {
        guard rows.count >= 2, maxHeartRate > restingHeartRate else { return 0 }
        let reserve = maxHeartRate - restingHeartRate
        var load = 0.0
        for (previous, current) in zip(rows, rows.dropFirst()) {
            let minutes = max(Double(current.ts - previous.ts), 1.0) / 60.0
            let pct = max(0.0, min(1.0, (Double(previous.bpm) - restingHeartRate) / reserve))
            let weight: Double
            switch pct {
            case 0.9...: weight = 5
            case 0.8..<0.9: weight = 4
            case 0.7..<0.8: weight = 3
            case 0.6..<0.7: weight = 2
            case 0.5..<0.6: weight = 1
            default: weight = 0
            }
            load += minutes * weight
        }
        return load
    }

    private static func activeMinutes(from rows: [HRSample]) -> Double {
        guard rows.count >= 2 else { return 0 }
        return zip(rows, rows.dropFirst()).reduce(0) { partial, pair in
            partial + max(Double(pair.1.ts - pair.0.ts), 1.0) / 60.0
        }
    }
}

enum DailyMetricsAssembler {
    static func makeDailyMetric(day: String,
                                hr: [HRSample],
                                rr: [RRInterval],
                                sleepSession: CachedSleepSession?,
                                hrv: HRVComputation,
                                restingHR: RestingHRComputation,
                                strain: StrainComputation,
                                spo2: [SpO2Sample],
                                skinTemp: [SkinTempSample],
                                resp: [RespSample]) -> DailyMetric {
        let totalSleepMin = sleepSession.map { Double($0.endTs - $0.startTs) / 60.0 }
        let latestHR = hr.last?.bpm
        let hasPrimarySignals = !hr.isEmpty || !rr.isEmpty || sleepSession != nil || strain.score != nil
        let inSleepSignals = sleepSession.map { session in
            (
                spo2: spo2.filter { $0.ts >= session.startTs && $0.ts <= session.endTs }.map { estimateSpO2(red: $0.red, ir: $0.ir) }.average,
                skin: skinTemp.filter { $0.ts >= session.startTs && $0.ts <= session.endTs }.map { (Double($0.raw) - 2048.0) / 256.0 }.average,
                resp: resp.filter { $0.ts >= session.startTs && $0.ts <= session.endTs }.map { max(8.0, min(30.0, Double($0.raw) / 220.0)) }.average
            )
        }
        let confidence = [sleepSession?.confidence, hrv.confidence, restingHR.confidence, strain.confidence].compactMap { $0 }.average
        let status: MetricAvailabilityStatus = hasPrimarySignals ? .ready : .unavailable
        let unavailableReason = dailyReason(day: day,
                                            hr: hr,
                                            rr: rr,
                                            sleepSession: sleepSession,
                                            hrv: hrv,
                                            restingHR: restingHR,
                                            strain: strain)
        return DailyMetric(day: day,
                           totalSleepMin: totalSleepMin,
                           efficiency: sleepSession?.efficiency,
                           deepMin: totalSleepMin.map { $0 * 0.18 },
                           remMin: totalSleepMin.map { $0 * 0.22 },
                           lightMin: totalSleepMin.map { $0 * 0.60 },
                           disturbances: sleepSession?.unavailableReason == nil ? (sleepSession == nil ? nil : 1) : 2,
                           restingHr: restingHR.bpm ?? latestHR,
                           avgHrv: hrv.rmssd,
                           recovery: nil,
                           strain: strain.score,
                           exerciseCount: nil,
                           spo2Pct: inSleepSignals?.spo2,
                           skinTempDevC: inSleepSignals?.skin,
                           respRateBpm: inSleepSignals?.resp,
                           source: .onDevice,
                            confidence: confidence,
                            status: status,
                           unavailableReason: unavailableReason,
                           recomputedAt: Int(Date().timeIntervalSince1970))
    }

    static func dailyReason(day: String,
                            hr: [HRSample],
                            rr: [RRInterval],
                            sleepSession: CachedSleepSession?,
                            hrv: HRVComputation,
                            restingHR: RestingHRComputation,
                            strain: StrainComputation) -> String {
        if hr.isEmpty && rr.isEmpty && sleepSession == nil {
            return "collecting HR data"
        }
        var parts: [String] = []
        if !hr.isEmpty {
            let minHR = hr.map(\.bpm).min() ?? 0
            let maxHR = hr.map(\.bpm).max() ?? 0
            let avgHR = Int((Double(hr.map(\.bpm).reduce(0, +)) / Double(hr.count)).rounded())
            let latestHR = hr.last?.bpm ?? 0
            parts.append("HR \(hr.count) samples min \(minHR) avg \(avgHR) max \(maxHR) latest \(latestHR)")
        } else {
            parts.append("no HR")
        }
        parts.append(rr.isEmpty ? "no RR" : "RR \(rr.count)")
        if let reason = hrv.reason { parts.append("HRV \(reason)") }
        if let reason = restingHR.reason { parts.append("RHR \(reason)") }
        if let reason = strain.reason { parts.append("Strain \(reason)") }
        if sleepSession == nil { parts.append("Sleep pending") }
        return parts.joined(separator: " | ")
    }

    private static func estimateSpO2(red: Int, ir: Int) -> Double {
        guard ir > 0 else { return 0 }
        let ratio = Double(red) / Double(ir)
        return max(85.0, min(100.0, 100.0 - abs(1.0 - ratio) * 12.0))
    }
}

struct LocalRecoveryResult {
    let metric: RecoveryMetric
    let baseline: MetricBaseline?
}

enum LocalRecoveryComputer {
    static func compute(day: String,
                        current: DailyMetric?,
                        history: [DailyMetric],
                        baselineDays: Int) -> LocalRecoveryResult {
        guard let current else {
            return LocalRecoveryResult(metric: RecoveryMetric(day: day,
                                                              score: nil,
                                                              status: .unavailable,
                                                              category: nil,
                                                              source: .onDevice,
                                                              confidence: nil,
                                                              baselineProgress: history.count,
                                                              explanation: "No daily metrics",
                                                              recomputedAt: Int(Date().timeIntervalSince1970)),
                                       baseline: nil)
        }
        let validHistory = history.filter { $0.avgHrv != nil && $0.restingHr != nil }
        guard validHistory.count >= baselineDays else {
            return LocalRecoveryResult(metric: RecoveryMetric(day: day,
                                                              score: nil,
                                                              status: .buildingBaseline,
                                                              category: nil,
                                                              source: .onDevice,
                                                              confidence: nil,
                                                              baselineProgress: validHistory.count,
                                                              explanation: "Building baseline",
                                                              recomputedAt: Int(Date().timeIntervalSince1970)),
                                       baseline: MetricBaseline(metric: "recovery",
                                                                day: day,
                                                                value: nil,
                                                                sampleCount: validHistory.count,
                                                                confidence: nil,
                                                                status: .buildingBaseline,
                                                                reason: "Building baseline",
                                                                recomputedAt: Int(Date().timeIntervalSince1970)))
        }
        guard let currentHRV = current.avgHrv,
              let currentRHR = current.restingHr.map(Double.init) else {
            return LocalRecoveryResult(metric: RecoveryMetric(day: day,
                                                              score: nil,
                                                              status: .unavailable,
                                                              category: nil,
                                                              source: .onDevice,
                                                              confidence: nil,
                                                              baselineProgress: validHistory.count,
                                                              explanation: "Missing HRV or resting HR",
                                                              recomputedAt: Int(Date().timeIntervalSince1970)),
                                       baseline: nil)
        }
        let baselineSlice = Array(validHistory.suffix(baselineDays))
        let baselineHRV = median(baselineSlice.compactMap(\.avgHrv)) ?? currentHRV
        let baselineRHR = median(baselineSlice.compactMap { $0.restingHr.map(Double.init) }) ?? currentRHR
        let sleepScore = min(1.0, max(0.0, (current.totalSleepMin ?? 0) / 480.0)) * 100.0
        let hrvComponent = min(100.0, max(0.0, 60.0 + ((currentHRV - baselineHRV) / max(baselineHRV, 1)) * 140.0))
        let rhrComponent = min(100.0, max(0.0, 65.0 - (currentRHR - baselineRHR) * 6.0))
        let total = hrvComponent * 0.5 + rhrComponent * 0.25 + sleepScore * 0.25
        let category: String
        switch total {
        case ..<34: category = "low"
        case ..<67: category = "medium"
        default: category = "high"
        }
        let explanation: String
        if currentHRV < baselineHRV {
            explanation = "HRV below baseline"
        } else if currentRHR > baselineRHR {
            explanation = "RHR elevated"
        } else if (current.totalSleepMin ?? 0) < 360 {
            explanation = "Sleep was short"
        } else {
            explanation = "Recovery ready"
        }
        return LocalRecoveryResult(metric: RecoveryMetric(day: day,
                                                          score: total,
                                                          status: .ready,
                                                          category: category,
                                                          source: .onDevice,
                                                          confidence: 0.68,
                                                          baselineProgress: validHistory.count,
                                                          explanation: explanation,
                                                          recomputedAt: Int(Date().timeIntervalSince1970)),
                                   baseline: MetricBaseline(metric: "recovery",
                                                            day: day,
                                                            value: total,
                                                            sampleCount: validHistory.count,
                                                            confidence: 0.68,
                                                            status: .ready,
                                                            reason: explanation,
                                                            recomputedAt: Int(Date().timeIntervalSince1970)))
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return sorted[mid]
    }
}

extension Array where Element == Double {
    fileprivate var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}

extension Int {
    fileprivate var double: Double { Double(self) }
}

func utcDays(endingAt date: Date, count: Int) -> [String] {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd"
    let calendar = formatter.calendar ?? Calendar(identifier: .gregorian)
    return (0..<count).reversed().compactMap {
        calendar.date(byAdding: .day, value: -$0, to: date).map(formatter.string(from:))
    }
}

func utcDate(fromDay day: String) -> Date? {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: day)
}

extension LocalHRVComputer {
    static func preferredWindow(forDay day: String, sleepSession: CachedSleepSession?, seconds: Int) -> (start: Int, end: Int) {
        if let sleepSession {
            return (sleepSession.startTs, sleepSession.endTs)
        }
        let dayStart = Int((utcDate(fromDay: day)?.timeIntervalSince1970 ?? 0))
        return (dayStart, dayStart + seconds)
    }
}
