import Foundation
import GRDB

extension WhoopStore {
    @discardableResult
    public func upsertRecoveryMetrics(_ metrics: [RecoveryMetric], deviceId: String) async throws -> Int {
        try syncWrite { db in
            var changed = 0
            for metric in metrics {
                try db.execute(sql: """
                    INSERT INTO recoveryMetric
                        (deviceId, day, score, status, category, source, confidence,
                         baselineProgress, explanation, recomputedAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(deviceId, day) DO UPDATE SET
                        score = excluded.score,
                        status = excluded.status,
                        category = excluded.category,
                        source = excluded.source,
                        confidence = excluded.confidence,
                        baselineProgress = excluded.baselineProgress,
                        explanation = excluded.explanation,
                        recomputedAt = excluded.recomputedAt
                    """, arguments: [
                        deviceId,
                        metric.day,
                        metric.score,
                        metric.status.rawValue,
                        metric.category,
                        metric.source.rawValue,
                        metric.confidence,
                        metric.baselineProgress,
                        metric.explanation,
                        metric.recomputedAt,
                    ])
                changed += db.changesCount
            }
            return changed
        }
    }

    public func recoveryMetrics(deviceId: String, from: String, to: String) async throws -> [RecoveryMetric] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT day, score, status, category, source, confidence, baselineProgress, explanation, recomputedAt
                FROM recoveryMetric
                WHERE deviceId = ? AND day >= ? AND day <= ?
                ORDER BY day ASC
                """, arguments: [deviceId, from, to]).compactMap { row in
                    guard let statusRaw: String = row["status"],
                          let status = MetricAvailabilityStatus(rawValue: statusRaw),
                          let sourceRaw: String = row["source"],
                          let source = MetricValueSource(rawValue: sourceRaw) else { return nil }
                    return RecoveryMetric(day: row["day"],
                                          score: row["score"],
                                          status: status,
                                          category: row["category"],
                                          source: source,
                                          confidence: row["confidence"],
                                          baselineProgress: row["baselineProgress"],
                                          explanation: row["explanation"],
                                          recomputedAt: row["recomputedAt"])
                }
        }
    }

    @discardableResult
    public func upsertStrainMetrics(_ metrics: [StrainMetric], deviceId: String) async throws -> Int {
        try syncWrite { db in
            var changed = 0
            for metric in metrics {
                try db.execute(sql: """
                    INSERT INTO strainMetric
                        (deviceId, day, score, status, source, confidence, explanation, recomputedAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(deviceId, day) DO UPDATE SET
                        score = excluded.score,
                        status = excluded.status,
                        source = excluded.source,
                        confidence = excluded.confidence,
                        explanation = excluded.explanation,
                        recomputedAt = excluded.recomputedAt
                    """, arguments: [
                        deviceId,
                        metric.day,
                        metric.score,
                        metric.status.rawValue,
                        metric.source.rawValue,
                        metric.confidence,
                        metric.explanation,
                        metric.recomputedAt,
                    ])
                changed += db.changesCount
            }
            return changed
        }
    }

    @discardableResult
    public func replaceMetricBaselines(_ baselines: [MetricBaseline], deviceId: String) async throws -> Int {
        try syncWrite { db in
            try db.execute(sql: "DELETE FROM metricBaseline WHERE deviceId = ?", arguments: [deviceId])
            var changed = 0
            for baseline in baselines {
                try db.execute(sql: """
                    INSERT INTO metricBaseline
                        (deviceId, metric, day, value, sampleCount, confidence, status, reason, recomputedAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        deviceId,
                        baseline.metric,
                        baseline.day,
                        baseline.value,
                        baseline.sampleCount,
                        baseline.confidence,
                        baseline.status.rawValue,
                        baseline.reason,
                        baseline.recomputedAt,
                    ])
                changed += db.changesCount
            }
            return changed
        }
    }

    @discardableResult
    public func replaceMetricDiagnostics(_ entries: [MetricDiagnosticEntry], deviceId: String) async throws -> Int {
        try syncWrite { db in
            try db.execute(sql: "DELETE FROM metricDiagnostics WHERE deviceId = ?", arguments: [deviceId])
            var changed = 0
            for entry in entries {
                try db.execute(sql: """
                    INSERT INTO metricDiagnostics (deviceId, key, value, updatedAt)
                    VALUES (?, ?, ?, ?)
                    """, arguments: [deviceId, entry.key, entry.value, entry.updatedAt])
                changed += db.changesCount
            }
            return changed
        }
    }

    public func metricDiagnosticEntries(deviceId: String) async throws -> [MetricDiagnosticEntry] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT key, value, updatedAt
                FROM metricDiagnostics
                WHERE deviceId = ?
                ORDER BY key ASC
                """, arguments: [deviceId]).map {
                    MetricDiagnosticEntry(key: $0["key"], value: $0["value"], updatedAt: $0["updatedAt"])
                }
        }
    }
}
