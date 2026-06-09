import Foundation
import GRDB

extension WhoopStore {
    @discardableResult
    public func upsertWorkoutSessions(_ sessions: [LocalWorkoutSession], deviceId: String) async throws -> Int {
        try syncWrite { db in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            var changed = 0
            for session in sessions {
                let hr = try String(decoding: encoder.encode(session.heartRateSamples), as: UTF8.self)
                let accel = try String(decoding: encoder.encode(session.accelerometerSamples), as: UTF8.self)
                let gyro = try String(decoding: encoder.encode(session.gyroscopeSamples), as: UTF8.self)
                let zones = try String(decoding: encoder.encode(session.zoneBreakdown), as: UTF8.self)
                try db.execute(sql: """
                    INSERT INTO workoutSession
                        (deviceId, sessionId, type, startTime, endTime, duration, status,
                         heartRateSamplesJSON, accelerometerSamplesJSON, gyroscopeSamplesJSON,
                         averageHeartRate, maxHeartRate, cardioLoad, muscularLoad, dailyStressLoad,
                         totalLoad, strainScore, userIntensity, muscularConfidence,
                         recoveryAdjustment, baselineStrain, zoneBreakdownJSON, updatedAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(deviceId, sessionId) DO UPDATE SET
                        type = excluded.type,
                        startTime = excluded.startTime,
                        endTime = excluded.endTime,
                        duration = excluded.duration,
                        status = excluded.status,
                        heartRateSamplesJSON = excluded.heartRateSamplesJSON,
                        accelerometerSamplesJSON = excluded.accelerometerSamplesJSON,
                        gyroscopeSamplesJSON = excluded.gyroscopeSamplesJSON,
                        averageHeartRate = excluded.averageHeartRate,
                        maxHeartRate = excluded.maxHeartRate,
                        cardioLoad = excluded.cardioLoad,
                        muscularLoad = excluded.muscularLoad,
                        dailyStressLoad = excluded.dailyStressLoad,
                        totalLoad = excluded.totalLoad,
                        strainScore = excluded.strainScore,
                        userIntensity = excluded.userIntensity,
                        muscularConfidence = excluded.muscularConfidence,
                        recoveryAdjustment = excluded.recoveryAdjustment,
                        baselineStrain = excluded.baselineStrain,
                        zoneBreakdownJSON = excluded.zoneBreakdownJSON,
                        updatedAt = excluded.updatedAt
                    """, arguments: [
                        deviceId,
                        session.id.uuidString,
                        session.type.rawValue,
                        session.startTime.timeIntervalSince1970,
                        session.endTime?.timeIntervalSince1970,
                        session.duration,
                        session.status.rawValue,
                        hr,
                        accel,
                        gyro,
                        session.averageHeartRate,
                        session.maxHeartRate,
                        session.cardioLoad,
                        session.muscularLoad,
                        session.dailyStressLoad,
                        session.totalLoad,
                        session.strainScore,
                        session.userIntensity,
                        session.muscularConfidence,
                        session.recoveryAdjustment,
                        session.baselineStrain,
                        zones,
                        Int(Date().timeIntervalSince1970),
                    ])
                changed += db.changesCount
            }
            return changed
        }
    }

    public func workoutSessions(deviceId: String) async throws -> [LocalWorkoutSession] {
        try syncRead { db in
            let decoder = JSONDecoder()
            return try Row.fetchAll(db, sql: """
                SELECT sessionId, type, startTime, endTime, duration, status,
                       heartRateSamplesJSON, accelerometerSamplesJSON, gyroscopeSamplesJSON,
                       averageHeartRate, maxHeartRate, cardioLoad, muscularLoad, dailyStressLoad,
                       totalLoad, strainScore, userIntensity, muscularConfidence,
                       recoveryAdjustment, baselineStrain, zoneBreakdownJSON
                FROM workoutSession
                WHERE deviceId = ?
                ORDER BY startTime DESC
                """, arguments: [deviceId]).compactMap { row in
                    guard let id = UUID(uuidString: row["sessionId"]),
                          let typeRaw: String = row["type"],
                          let type = LocalWorkoutType(rawValue: typeRaw),
                          let statusRaw: String = row["status"],
                          let status = LocalWorkoutStatus(rawValue: statusRaw),
                          let hrJSON: String = row["heartRateSamplesJSON"],
                          let accelJSON: String = row["accelerometerSamplesJSON"],
                          let gyroJSON: String = row["gyroscopeSamplesJSON"],
                          let zonesJSON: String = row["zoneBreakdownJSON"] else { return nil }
                    let hr = (try? decoder.decode([LocalWorkoutHeartRateSample].self, from: Data(hrJSON.utf8))) ?? []
                    let accel = (try? decoder.decode([LocalMotionSample].self, from: Data(accelJSON.utf8))) ?? []
                    let gyro = (try? decoder.decode([LocalMotionSample].self, from: Data(gyroJSON.utf8))) ?? []
                    let zones = (try? decoder.decode(LocalWorkoutZoneBreakdown.self, from: Data(zonesJSON.utf8)))
                        ?? LocalWorkoutZoneBreakdown(percentages: [:], currentZone: nil)
                    return LocalWorkoutSession(
                        id: id,
                        type: type,
                        startTime: Date(timeIntervalSince1970: row["startTime"]),
                        endTime: (row["endTime"] as Double?).map(Date.init(timeIntervalSince1970:)),
                        duration: row["duration"],
                        status: status,
                        heartRateSamples: hr,
                        accelerometerSamples: accel,
                        gyroscopeSamples: gyro,
                        averageHeartRate: row["averageHeartRate"],
                        maxHeartRate: row["maxHeartRate"],
                        cardioLoad: row["cardioLoad"],
                        muscularLoad: row["muscularLoad"],
                        dailyStressLoad: row["dailyStressLoad"],
                        totalLoad: row["totalLoad"],
                        strainScore: row["strainScore"],
                        userIntensity: row["userIntensity"],
                        muscularConfidence: row["muscularConfidence"],
                        recoveryAdjustment: row["recoveryAdjustment"],
                        baselineStrain: row["baselineStrain"],
                        zoneBreakdown: zones
                    )
                }
        }
    }

    public func workoutSessionCount(deviceId: String) async throws -> Int {
        try syncRead { db in
            try Int.fetchOne(db,
                             sql: "SELECT COUNT(*) FROM workoutSession WHERE deviceId = ?",
                             arguments: [deviceId]) ?? 0
        }
    }

    public func importLegacyWorkoutSessionsIfNeeded(deviceId: String, from url: URL) async throws -> Int {
        if try await workoutSessionCount(deviceId: deviceId) > 0 { return 0 }
        guard let data = try? Data(contentsOf: url) else { return 0 }
        let sessions = (try? JSONDecoder().decode([LocalWorkoutSession].self, from: data)) ?? []
        guard !sessions.isEmpty else { return 0 }
        return try await upsertWorkoutSessions(sessions, deviceId: deviceId)
    }
}
