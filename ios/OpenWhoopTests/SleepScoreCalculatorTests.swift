import XCTest
@testable import OpenWhoop

final class SleepScoreCalculatorTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func date(_ day: Int, hour: Int, minute: Int = 0) -> Date {
        DateComponents(calendar: calendar,
                       timeZone: calendar.timeZone,
                       year: 2026,
                       month: 5,
                       day: day,
                       hour: hour,
                       minute: minute).date!
    }

    private func night(
        day: Int,
        asleep: Double = 480,
        inBed: Double = 510,
        wake: Double = 20,
        events: Int = 1,
        hrv: Double? = 70,
        hr: Double? = 50,
        deep: Double? = 90,
        rem: Double? = 110,
        startHour: Int = 23,
        startMinute: Int = 0
    ) -> SleepScoreNight {
        let start = date(day, hour: startHour, minute: startMinute)
        return SleepScoreNight(
            sleepStart: start,
            sleepEnd: start.addingTimeInterval(inBed * 60),
            timeAsleepMinutes: asleep,
            timeInBedMinutes: inBed,
            wakeAfterSleepOnsetMinutes: wake,
            wakeEventCount: events,
            deepSleepMinutes: deep,
            remSleepMinutes: rem,
            averageSleepingHR: hr,
            averageHRV: hrv,
            respiratoryRate: 14.5,
            spo2: 97,
            skinTemperatureDeviationC: 0.1,
            restlessnessRatio: nil
        )
    }

    func testFewerThanSevenValidNightsReturnsBuildingBaseline() {
        let history = (1...3).map { night(day: $0) }

        let result = SleepScoreCalculator.calculate(for: history.last,
                                                    history: history,
                                                    calendar: calendar)

        XCTAssertNil(result.score)
        XCTAssertEqual(result.status, .buildingBaseline)
        XCTAssertEqual(result.baselineProgress, 3)
        XCTAssertEqual(result.requiredBaselineNights, 7)
        XCTAssertEqual(result.explanation, "Building baseline")
    }

    func testExactlySevenValidNightsReturnsReadyScore() throws {
        let history = (1...7).map { night(day: $0) }

        let result = SleepScoreCalculator.calculate(for: history.last,
                                                    history: history,
                                                    calendar: calendar)

        XCTAssertEqual(result.status, .ready)
        XCTAssertNotNil(result.score)
        XCTAssertNotNil(result.components)
    }

    func testPerfectSleepReturnsHighScore() throws {
        let history = (1...7).map { night(day: $0, asleep: 520, inBed: 560, wake: 10) }

        let result = SleepScoreCalculator.calculate(for: history.last,
                                                    history: history,
                                                    calendar: calendar)

        XCTAssertGreaterThanOrEqual(try XCTUnwrap(result.score), 90)
    }

    func testShortSleepReturnsLowerScore() throws {
        var history = (1...6).map { night(day: $0, asleep: 480, inBed: 510) }
        history.append(night(day: 7, asleep: 250, inBed: 300, wake: 50))

        let result = SleepScoreCalculator.calculate(for: history.last,
                                                    history: history,
                                                    calendar: calendar)

        XCTAssertLessThan(try XCTUnwrap(result.score), 80)
    }

    func testPoorEfficiencyLowersScore() throws {
        var history = (1...6).map { night(day: $0, asleep: 480, inBed: 510) }
        history.append(night(day: 7, asleep: 360, inBed: 600, wake: 180, events: 1))

        let result = SleepScoreCalculator.calculate(for: history.last,
                                                    history: history,
                                                    calendar: calendar)

        XCTAssertLessThan(try XCTUnwrap(result.components?.sleepEfficiency), 10)
    }

    func testManyWakeEventsLowersDisturbanceComponent() throws {
        var history = (1...6).map { night(day: $0) }
        history.append(night(day: 7, wake: 70, events: 8))

        let result = SleepScoreCalculator.calculate(for: history.last,
                                                    history: history,
                                                    calendar: calendar)

        XCTAssertLessThan(try XCTUnwrap(result.components?.disturbances), 5)
    }

    func testMissingHRVDoesNotCrash() throws {
        let history = (1...7).map { night(day: $0, hrv: nil, hr: 50) }

        let result = SleepScoreCalculator.calculate(for: history.last,
                                                    history: history,
                                                    calendar: calendar)

        XCTAssertEqual(result.status, .ready)
        XCTAssertNotNil(result.score)
        XCTAssertGreaterThan(try XCTUnwrap(result.components?.recovery), 0)
    }

    func testMissingREMDeepDoesNotCrashAndUsesNeutralArchitecture() throws {
        let history = (1...7).map { night(day: $0, deep: nil, rem: nil) }

        let result = SleepScoreCalculator.calculate(for: history.last,
                                                    history: history,
                                                    calendar: calendar)

        XCTAssertEqual(result.status, .ready)
        XCTAssertNotNil(result.score)
        XCTAssertEqual(try XCTUnwrap(result.components?.architecture), 3, accuracy: 0.001)
    }

    func testScoreAlwaysClampsBetweenZeroAndOneHundred() throws {
        let history = (1...7).map {
            night(day: $0, asleep: 1_200, inBed: 1, wake: 0, events: 0, hrv: 1_000, hr: 10)
        }

        let result = SleepScoreCalculator.calculate(for: history.last,
                                                    history: history,
                                                    calendar: calendar)

        let score = try XCTUnwrap(result.score)
        XCTAssertGreaterThanOrEqual(score, 0)
        XCTAssertLessThanOrEqual(score, 100)
    }

    func testCircularBedtimeDifferenceWorksAroundMidnight() {
        XCTAssertEqual(SleepScoreCalculator.circularDifferenceMinutes(23 * 60 + 50, 10),
                       20,
                       accuracy: 0.001)
    }
}
