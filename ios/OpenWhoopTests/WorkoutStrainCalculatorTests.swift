import XCTest
@testable import OpenWhoop

final class WorkoutStrainCalculatorTests: XCTestCase {
    func testStrengthIntensityRaisesMuscularLoadAndStrain() {
        let baseSession = WorkoutSession(
            id: UUID(),
            type: .strengthTraining,
            startTime: Date(),
            endTime: Date().addingTimeInterval(45 * 60),
            duration: 45 * 60,
            status: .ended,
            heartRateSamples: stride(from: 0, to: 900, by: 30).map {
                WorkoutHeartRateSample(timestamp: Date().addingTimeInterval(TimeInterval($0)), bpm: 124)
            },
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
            muscularConfidence: 0.55,
            recoveryAdjustment: 1,
            baselineStrain: 10,
            zoneBreakdown: WorkoutZoneBreakdown(percentages: [:], currentZone: nil)
        )

        let context = WorkoutStrainContext(
            restingHeartRate: 56,
            age: 32,
            sex: "male",
            recoveryScore: 68,
            sleepEfficiency: 0.91,
            baselineStrain: 10,
            currentDayLoad: 30
        )

        var easy = baseSession
        easy.userIntensity = 3
        var hard = baseSession
        hard.userIntensity = 9

        let easyResult = WorkoutStrainCalculator.calculate(session: easy, context: context)
        let hardResult = WorkoutStrainCalculator.calculate(session: hard, context: context)

        XCTAssertGreaterThan(hardResult.muscularLoad, easyResult.muscularLoad)
        XCTAssertGreaterThan(hardResult.strainScore, easyResult.strainScore)
    }

    func testDailyStressLoadUsesExistingDayLoad() {
        let session = WorkoutSession(
            id: UUID(),
            type: .outsideRun,
            startTime: Date(),
            endTime: Date().addingTimeInterval(30 * 60),
            duration: 30 * 60,
            status: .ended,
            heartRateSamples: stride(from: 0, to: 1800, by: 60).map {
                WorkoutHeartRateSample(timestamp: Date().addingTimeInterval(TimeInterval($0)), bpm: 152)
            },
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
            muscularConfidence: 0.9,
            recoveryAdjustment: 1,
            baselineStrain: 12,
            zoneBreakdown: WorkoutZoneBreakdown(percentages: [:], currentZone: nil)
        )

        let freshContext = WorkoutStrainContext(
            restingHeartRate: 54,
            age: 29,
            sex: "female",
            recoveryScore: 75,
            sleepEfficiency: 0.94,
            baselineStrain: 12,
            currentDayLoad: 0
        )
        let loadedContext = WorkoutStrainContext(
            restingHeartRate: 54,
            age: 29,
            sex: "female",
            recoveryScore: 75,
            sleepEfficiency: 0.94,
            baselineStrain: 12,
            currentDayLoad: 80
        )

        let freshResult = WorkoutStrainCalculator.calculate(session: session, context: freshContext)
        let loadedResult = WorkoutStrainCalculator.calculate(session: session, context: loadedContext)

        XCTAssertEqual(freshResult.dailyStressLoad, 0, accuracy: 0.01)
        XCTAssertGreaterThan(loadedResult.dailyStressLoad, freshResult.dailyStressLoad)
        XCTAssertGreaterThan(loadedResult.totalLoad, freshResult.totalLoad)
    }
}
