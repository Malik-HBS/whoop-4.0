import Foundation
import GRDB
import WhoopProtocol

extension WhoopStore {
    public func hrSamples(deviceId: String, from: Int, to: Int, limit: Int) async throws -> [HRSample] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT ts, bpm FROM hrSample
                WHERE deviceId = ? AND ts >= ? AND ts <= ?
                ORDER BY ts ASC LIMIT ?
                """, arguments: [deviceId, from, to, limit])
                .map { HRSample(ts: $0["ts"], bpm: $0["bpm"]) }
        }
    }

    public func rrIntervals(deviceId: String, from: Int, to: Int, limit: Int) async throws -> [RRInterval] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT ts, rrMs FROM rrInterval
                WHERE deviceId = ? AND ts >= ? AND ts <= ?
                ORDER BY ts ASC, rrMs ASC LIMIT ?
                """, arguments: [deviceId, from, to, limit])
                .map { RRInterval(ts: $0["ts"], rrMs: $0["rrMs"]) }
        }
    }

    public func events(deviceId: String, from: Int, to: Int, limit: Int) async throws -> [WhoopEvent] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT ts, kind, payloadJSON FROM event
                WHERE deviceId = ? AND ts >= ? AND ts <= ?
                ORDER BY ts ASC, kind ASC LIMIT ?
                """, arguments: [deviceId, from, to, limit])
                .map { row in
                    let json: String = row["payloadJSON"]
                    let payload = (try? JSONDecoder().decode(
                        [String: ParsedValue].self,
                        from: Data(json.utf8))) ?? [:]
                    return WhoopEvent(ts: row["ts"], kind: row["kind"], payload: payload)
                }
        }
    }

    public func batterySamples(deviceId: String, from: Int, to: Int, limit: Int) async throws -> [BatterySample] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT ts, soc, mv FROM battery
                WHERE deviceId = ? AND ts >= ? AND ts <= ?
                ORDER BY ts ASC LIMIT ?
                """, arguments: [deviceId, from, to, limit])
                .map { BatterySample(ts: $0["ts"], soc: $0["soc"], mv: $0["mv"]) }
        }
    }

    public func spo2Samples(deviceId: String, from: Int, to: Int, limit: Int) async throws -> [SpO2Sample] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT ts, red, ir FROM spo2Sample
                WHERE deviceId = ? AND ts >= ? AND ts <= ?
                ORDER BY ts ASC LIMIT ?
                """, arguments: [deviceId, from, to, limit])
                .map { SpO2Sample(ts: $0["ts"], red: $0["red"], ir: $0["ir"]) }
        }
    }

    public func skinTempSamples(deviceId: String, from: Int, to: Int, limit: Int) async throws -> [SkinTempSample] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT ts, raw FROM skinTempSample
                WHERE deviceId = ? AND ts >= ? AND ts <= ?
                ORDER BY ts ASC LIMIT ?
                """, arguments: [deviceId, from, to, limit])
                .map { SkinTempSample(ts: $0["ts"], raw: $0["raw"]) }
        }
    }

    public func respSamples(deviceId: String, from: Int, to: Int, limit: Int) async throws -> [RespSample] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT ts, raw FROM respSample
                WHERE deviceId = ? AND ts >= ? AND ts <= ?
                ORDER BY ts ASC LIMIT ?
                """, arguments: [deviceId, from, to, limit])
                .map { RespSample(ts: $0["ts"], raw: $0["raw"]) }
        }
    }

    public func gravitySamples(deviceId: String, from: Int, to: Int, limit: Int) async throws -> [GravitySample] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT ts, x, y, z FROM gravitySample
                WHERE deviceId = ? AND ts >= ? AND ts <= ?
                ORDER BY ts ASC LIMIT ?
                """, arguments: [deviceId, from, to, limit])
                .map { GravitySample(ts: $0["ts"], x: $0["x"], y: $0["y"], z: $0["z"]) }
        }
    }

    /// Max HR sample timestamp for a device, or nil if there are none. The biometric "data frontier"
    /// used by the stuck-strap watchdog (advances iff the strap is actually logging + offloading).
    public func latestHRSampleTs(deviceId: String) async throws -> Int? {
        try syncRead { db in
            try Int.fetchOne(db,
                sql: "SELECT MAX(ts) FROM hrSample WHERE deviceId = ?", arguments: [deviceId])
        }
    }

    /// Aggregate storage footprint: total decoded rows, raw batch count, total raw byteSize.
    public func storageStats() async throws -> (decodedRows: Int, rawBatches: Int, rawBytes: Int) {
        try syncRead { db in
            let hr   = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM hrSample") ?? 0
            let rr   = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM rrInterval") ?? 0
            let ev   = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM event") ?? 0
            let bat  = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM battery") ?? 0
            let spo2 = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM spo2Sample") ?? 0
            let skin = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM skinTempSample") ?? 0
            let resp = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM respSample") ?? 0
            let grav = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM gravitySample") ?? 0
            let batches = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM rawBatch") ?? 0
            let bytes   = try Int.fetchOne(db,
                sql: "SELECT COALESCE(SUM(byteSize), 0) FROM rawBatch") ?? 0
            return (hr + rr + ev + bat + spo2 + skin + resp + grav, batches, bytes)
        }
    }

    public func latestRawBatchCapturedAt() async throws -> Int? {
        try syncRead { db in
            try Int.fetchOne(db, sql: "SELECT MAX(capturedAt) FROM rawBatch")
        }
    }

    /// Per-table counts and latest-timestamp snapshots for a single device. Used by
    /// the developer diagnostics UI to localise pipeline breaks (collected-but-not-uploaded
    /// vs collected-and-uploaded vs never-collected). nil `latestTs` means the table has
    /// no rows for this device yet.
    ///
    /// Single SQL round-trip per table; the 8 SELECTs share one read transaction so the
    /// snapshot is consistent. Table names come from the hardcoded migration definitions
    /// (no user input → no injection risk).
    public func localCountsAndLatestTs(deviceId: String) async throws -> LocalStoreSnapshot {
        try syncRead { db -> LocalStoreSnapshot in
            func count(_ table: String) throws -> Int {
                try Int.fetchOne(db,
                    sql: "SELECT COUNT(*) FROM \(table) WHERE deviceId = ?",
                    arguments: [deviceId]) ?? 0
            }
            func latest(_ table: String) throws -> Int? {
                try Int.fetchOne(db,
                    sql: "SELECT MAX(ts) FROM \(table) WHERE deviceId = ?",
                    arguments: [deviceId])
            }
            func countByDay(_ table: String) throws -> Int {
                try Int.fetchOne(db,
                                 sql: "SELECT COUNT(*) FROM \(table) WHERE deviceId = ?",
                                 arguments: [deviceId]) ?? 0
            }
            func latestDay(_ table: String) throws -> Int? {
                guard let day: String = try String.fetchOne(db,
                                                            sql: "SELECT MAX(day) FROM \(table) WHERE deviceId = ?",
                                                            arguments: [deviceId]) else {
                    return nil
                }
                let formatter = DateFormatter()
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.timeZone = TimeZone(identifier: "UTC")
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter.date(from: day).map { Int($0.timeIntervalSince1970) }
            }
            return LocalStoreSnapshot(
                hr:       StreamStat(count: try count("hrSample"),       latestTs: try latest("hrSample")),
                rr:       StreamStat(count: try count("rrInterval"),     latestTs: try latest("rrInterval")),
                events:   StreamStat(count: try count("event"),          latestTs: try latest("event")),
                battery:  StreamStat(count: try count("battery"),        latestTs: try latest("battery")),
                spo2:     StreamStat(count: try count("spo2Sample"),     latestTs: try latest("spo2Sample")),
                skinTemp: StreamStat(count: try count("skinTempSample"), latestTs: try latest("skinTempSample")),
                resp:     StreamStat(count: try count("respSample"),     latestTs: try latest("respSample")),
                gravity:  StreamStat(count: try count("gravitySample"),  latestTs: try latest("gravitySample")),
                raw:      StreamStat(count: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM rawBatch") ?? 0,
                                     latestTs: try Int.fetchOne(db, sql: "SELECT MAX(capturedAt) FROM rawBatch")),
                dailyMetrics: StreamStat(count: try countByDay("dailyMetric"), latestTs: try latestDay("dailyMetric")),
                sleepSessions: StreamStat(count: try countByDay("sleepSession"), latestTs: try Int.fetchOne(db, sql: "SELECT MAX(endTs) FROM sleepSession WHERE deviceId = ?", arguments: [deviceId])),
                workouts: StreamStat(count: try countByDay("workoutSession"), latestTs: (try Double.fetchOne(db, sql: "SELECT MAX(startTime) FROM workoutSession WHERE deviceId = ?", arguments: [deviceId])).map { Int($0) }),
                recoveryMetrics: StreamStat(count: try countByDay("recoveryMetric"), latestTs: try latestDay("recoveryMetric")),
                strainMetrics: StreamStat(count: try countByDay("strainMetric"), latestTs: try latestDay("strainMetric"))
            )
        }
    }
}

/// Per-stream row count + latest row ts (nil = no rows for this device yet).
/// Lives next to its only call site (`localCountsAndLatestTs`) so the diagnostics
/// type stays a pure value-type in the store package.
public struct StreamStat: Equatable, Sendable {
    public let count: Int
    public let latestTs: Int?
    public init(count: Int, latestTs: Int?) { self.count = count; self.latestTs = latestTs }
}

/// Snapshot of the local store's decoded tables for ONE device — the device id is
/// implied by the caller. Returned by `localCountsAndLatestTs(deviceId:)`.
public struct LocalStoreSnapshot: Equatable, Sendable {
    public let hr: StreamStat
    public let rr: StreamStat
    public let events: StreamStat
    public let battery: StreamStat
    public let spo2: StreamStat
    public let skinTemp: StreamStat
    public let resp: StreamStat
    public let gravity: StreamStat
    public let raw: StreamStat
    public let dailyMetrics: StreamStat
    public let sleepSessions: StreamStat
    public let workouts: StreamStat
    public let recoveryMetrics: StreamStat
    public let strainMetrics: StreamStat
}
