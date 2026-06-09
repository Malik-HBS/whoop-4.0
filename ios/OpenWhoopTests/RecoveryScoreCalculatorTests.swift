import XCTest
@testable import OpenWhoop

final class RecoveryScoreCalculatorTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func date(_ day: Int) -> Date {
        DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 5, day: day).date!
    }

    private func night(
        day: Int,
        hrv: Double? = 70,
        rhr: Double? = 50,
        sleep: Double? = 86,
        duration: Double? = 480,
        resp: Double? = 14,
        temp: Double? = 0,
        spo2: Double? = 97,
        strain: Double? = 8
    ) -> RecoveryNight {
        RecoveryNight(
            date: date(day),
            hasMainSleepSession: true,
            sleepDurationMinutes: duration,
            hrvRmssd: hrv,
            sleepingRHR: rhr,
            sleepScore: sleep,
            sleepEfficiency: 0.88,
            respiratoryRate: resp,
            skinTemp: temp,
            spo2: spo2,
            previousDayStrain: strain,
            hasEnoughCleanHRData: hrv != nil && rhr != nil,
            isManuallyInvalid: false,
            sensorQuality: 0.9
        )
    }

    private func input(
        day: Int = 8,
        hrv: Double? = 70,
        rhr: Double? = 50,
        sleep: Double? = 86,
        duration: Double? = 480,
        efficiency: Double? = 0.88,
        resp: Double? = 14,
        temp: Double? = 0,
        spo2: Double? = 97,
        strain: Double? = 8
    ) -> RecoveryInput {
        RecoveryInput(
            date: date(day),
            hrvRmssd: hrv,
            sleepingRHR: rhr,
            sleepScore: sleep,
            sleepDurationMinutes: duration,
            sleepEfficiency: efficiency,
            respiratoryRate: resp,
            skinTemp: temp,
            spo2: spo2,
            previousDayStrain: strain,
            sensorQuality: 0.9
        )
    }

    private var readyBaseline: RecoveryBaseline {
        RecoveryBaseline(
            hrvBaseline: 70,
            rhrBaseline: 50,
            respiratoryRateBaseline: 14,
            skinTempBaseline: 0,
            spo2Baseline: 97,
            sleepScoreBaseline: 86,
            strainBaseline: 8,
            validNightCount: 7,
            baselineWindowDays: 7
        )
    }

    func testFewerThanSevenValidNightsReturnsBuildingBaseline() {
        let nights = (1...3).map { night(day: $0) }
        let baseline = RecoveryBaselineService.getBaseline(for: date(8), nights: nights)

        let result = RecoveryScoreCalculator.calculateRecovery(input: input(), baseline: baseline)

        XCTAssertNil(result.score)
        XCTAssertEqual(result.zone, .buildingBaseline)
        XCTAssertEqual(result.statusText, "Building baseline")
        XCTAssertEqual(result.baselineStatus.message, "Day 3 of 7")
    }

    func testExactlySevenValidNightsCalculatesScore() {
        let nights = (1...7).map { night(day: $0) }
        let baseline = RecoveryBaselineService.getBaseline(for: date(8), nights: nights)

        let result = RecoveryScoreCalculator.calculateRecovery(input: input(), baseline: baseline)

        XCTAssertNotNil(result.score)
        XCTAssertNotEqual(result.zone, .buildingBaseline)
    }

    func testHRVTwentyPercentBelowBaselineDecreasesRecovery() throws {
        let result = RecoveryScoreCalculator.calculateRecovery(input: input(hrv: 56), baseline: readyBaseline)

        XCTAssertLessThan(try XCTUnwrap(result.components.hrvScore), 60)
        XCTAssertLessThan(try XCTUnwrap(result.score), 80)
    }

    func testRHREightBpmAboveBaselineDecreasesRecovery() throws {
        let result = RecoveryScoreCalculator.calculateRecovery(input: input(rhr: 58), baseline: readyBaseline)

        XCTAssertLessThan(try XCTUnwrap(result.components.rhrScore), 40)
        XCTAssertLessThan(try XCTUnwrap(result.score), 80)
    }

    func testSleepUnderFourHoursCapsAtFortyFive() throws {
        let result = RecoveryScoreCalculator.calculateRecovery(input: input(duration: 210), baseline: readyBaseline)

        XCTAssertLessThanOrEqual(try XCTUnwrap(result.score), 45)
        XCTAssertTrue(result.components.appliedCaps.contains("Sleep duration under 4 hours capped recovery at 45"))
    }

    func testRHRTenPlusAboveBaselineCapsAtForty() throws {
        let result = RecoveryScoreCalculator.calculateRecovery(input: input(rhr: 61), baseline: readyBaseline)

        XCTAssertLessThanOrEqual(try XCTUnwrap(result.score), 40)
        XCTAssertTrue(result.components.appliedCaps.contains("Resting heart rate was 10+ bpm above baseline"))
    }

    func testRespiratoryRateTwoPlusAboveBaselineCapsAtFifty() throws {
        let result = RecoveryScoreCalculator.calculateRecovery(input: input(resp: 16.2), baseline: readyBaseline)

        XCTAssertLessThanOrEqual(try XCTUnwrap(result.score), 50)
        XCTAssertTrue(result.components.appliedCaps.contains("Respiratory rate was 2+ above baseline"))
    }

    func testMissingOptionalSignalsStillCalculates() throws {
        let result = RecoveryScoreCalculator.calculateRecovery(input: input(resp: nil, temp: nil, spo2: nil), baseline: readyBaseline)

        XCTAssertNotNil(result.score)
        XCTAssertEqual(result.components.stabilityScore, 85)
        XCTAssertTrue(result.explanation.contains("Limited recovery inputs available."))
    }

    func testMissingHRVReturnsNotEnoughData() {
        let result = RecoveryScoreCalculator.calculateRecovery(input: input(hrv: nil), baseline: readyBaseline)

        XCTAssertNil(result.score)
        XCTAssertNil(result.zone)
        XCTAssertEqual(result.statusText, "Not enough data")
        XCTAssertTrue(result.explanation.first?.contains("HRV") == true)
    }

    func testZoneBoundaries() {
        XCTAssertEqual(RecoveryScoreCalculator.zone(for: 33), .red)
        XCTAssertEqual(RecoveryScoreCalculator.zone(for: 34), .yellow)
        XCTAssertEqual(RecoveryScoreCalculator.zone(for: 66), .yellow)
        XCTAssertEqual(RecoveryScoreCalculator.zone(for: 67), .green)
    }
}
