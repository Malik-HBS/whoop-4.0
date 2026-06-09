import XCTest
import WhoopProtocol
import WhoopStore
@testable import WhoopMetrics

final class OnDeviceMetricsEngineTests: XCTestCase {
    func testHRVComputerUsesRMSSDOnCleanRR() {
        let day = "2026-06-07"
        let start = Int(utcDate(fromDay: day)!.timeIntervalSince1970)
        let rr = [
            RRInterval(ts: start + 10, rrMs: 800),
            RRInterval(ts: start + 20, rrMs: 820),
            RRInterval(ts: start + 30, rrMs: 790),
            RRInterval(ts: start + 40, rrMs: 810),
            RRInterval(ts: start + 50, rrMs: 805),
            RRInterval(ts: start + 60, rrMs: 798),
            RRInterval(ts: start + 70, rrMs: 802),
            RRInterval(ts: start + 80, rrMs: 799),
            RRInterval(ts: start + 90, rrMs: 801),
            RRInterval(ts: start + 100, rrMs: 804),
            RRInterval(ts: start + 110, rrMs: 806),
            RRInterval(ts: start + 120, rrMs: 803),
            RRInterval(ts: start + 130, rrMs: 799),
            RRInterval(ts: start + 140, rrMs: 801),
            RRInterval(ts: start + 150, rrMs: 805),
            RRInterval(ts: start + 160, rrMs: 807),
            RRInterval(ts: start + 170, rrMs: 804),
            RRInterval(ts: start + 180, rrMs: 800),
            RRInterval(ts: start + 190, rrMs: 799),
            RRInterval(ts: start + 200, rrMs: 802),
            RRInterval(ts: start + 210, rrMs: 804),
        ]

        let result = LocalHRVComputer.compute(day: day, rr: rr, sleepSession: nil)

        XCTAssertNotNil(result.rmssd)
        XCTAssertGreaterThan(result.sampleCount, 19)
        XCTAssertNil(result.reason)
    }

    func testRecoveryComputerBuildsBaselineBeforeSevenNights() {
        let history = (0..<5).map { index in
            DailyMetric(day: "2026-06-0\(index + 1)",
                        totalSleepMin: 430,
                        efficiency: 0.88,
                        deepMin: 80,
                        remMin: 95,
                        lightMin: 255,
                        disturbances: 1,
                        restingHr: 54,
                        avgHrv: 58,
                        recovery: nil,
                        strain: 10,
                        exerciseCount: 1,
                        source: .onDevice,
                        confidence: 0.8,
                        status: .ready,
                        unavailableReason: nil,
                        recomputedAt: nil)
        }
        let current = DailyMetric(day: "2026-06-07",
                                  totalSleepMin: 440,
                                  efficiency: 0.9,
                                  deepMin: 85,
                                  remMin: 100,
                                  lightMin: 255,
                                  disturbances: 1,
                                  restingHr: 52,
                                  avgHrv: 60,
                                  recovery: nil,
                                  strain: 9,
                                  exerciseCount: 0,
                                  source: .onDevice,
                                  confidence: 0.85,
                                  status: .ready,
                                  unavailableReason: nil,
                                  recomputedAt: nil)

        let result = LocalRecoveryComputer.compute(day: "2026-06-07", current: current, history: history, baselineDays: 7)

        XCTAssertEqual(result.metric.status, .buildingBaseline)
        XCTAssertNil(result.metric.score)
        XCTAssertEqual(result.metric.explanation, "Building baseline")
    }

    func testSleepDetectorUsesFallbackWhenGravityMissing() {
        let day = "2026-06-07"
        let dayStart = Int(utcDate(fromDay: day)!.timeIntervalSince1970)
        let fallbackWindowStart = dayStart - 6 * 3600
        let hr = (0..<220).map { HRSample(ts: fallbackWindowStart + ($0 * 60), bpm: 58) }
        let rr = (0..<40).map { RRInterval(ts: fallbackWindowStart + ($0 * 120), rrMs: 820) }

        let result = LocalSleepDetector.detect(forDay: day, hr: hr, rr: rr, gravity: [])

        XCTAssertNotNil(result.session)
        XCTAssertEqual(result.reason, "motion data unavailable")
        XCTAssertEqual(result.session?.source, .onDevice)
    }

    func testDailyMetricCanBeBuiltFromHRAndRRWithoutSleep() {
        let day = "2026-06-07"
        let start = Int(utcDate(fromDay: day)!.timeIntervalSince1970)
        let hr = (0..<60).map { HRSample(ts: start + ($0 * 60), bpm: 60 + ($0 % 5)) }
        let rr = (0..<60).map { RRInterval(ts: start + ($0 * 60), rrMs: 820) }

        let hrv = LocalHRVComputer.compute(day: day, rr: rr, sleepSession: nil)
        let rhr = LocalRestingHRComputer.compute(day: day, hr: hr, gravity: [], sleepSession: nil)
        let strain = LocalStrainComputer.compute(day: day,
                                                 dayStart: start,
                                                 dayEnd: start + 86_399,
                                                 hr: hr,
                                                 workouts: [],
                                                 restingHeartRate: Double(rhr.bpm ?? 60))
        let metric = DailyMetricsAssembler.makeDailyMetric(day: day,
                                                           hr: hr,
                                                           rr: rr,
                                                           sleepSession: nil,
                                                           hrv: hrv,
                                                           restingHR: rhr,
                                                           strain: strain,
                                                           spo2: [],
                                                           skinTemp: [],
                                                           resp: [])

        XCTAssertEqual(metric.status, .ready)
        XCTAssertEqual(metric.source, .onDevice)
        XCTAssertTrue(metric.unavailableReason?.contains("Sleep pending") == true)
    }
}
