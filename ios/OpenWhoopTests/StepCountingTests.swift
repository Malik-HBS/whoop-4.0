import XCTest
import WhoopProtocol
@testable import OpenWhoop

final class StepCountingTests: XCTestCase {
    func testSyntheticWalkingCountsAboutExpectedSteps() async {
        let samples = makeRhythmicSamples(cadenceSpm: 100, duration: 60)
        let count = await countSteps(samples)
        XCTAssertGreaterThanOrEqual(count, 90)
        XCTAssertLessThanOrEqual(count, 110)
    }

    func testStillnessCountsZeroSteps() async {
        let samples = stride(from: 0.0, to: 30.0, by: 0.02).map {
            AccelerometerSample(timestamp: Date(timeIntervalSince1970: $0), x: 0, y: 0, z: 1)
        }
        let count = await countSteps(samples)
        XCTAssertEqual(count, 0)
    }

    func testRandomLowNoiseIsRejected() async {
        let samples = stride(from: 0.0, to: 30.0, by: 0.02).map { t in
            let noise = 0.005 * sin(t * 19.0) + 0.003 * cos(t * 7.0)
            return AccelerometerSample(timestamp: Date(timeIntervalSince1970: t), x: noise, y: 0, z: 1 + noise)
        }
        let count = await countSteps(samples)
        XCTAssertLessThanOrEqual(count, 2)
    }

    func testShakingCadenceIsRejected() async {
        let samples = makeRhythmicSamples(cadenceSpm: 300, duration: 20, amplitude: 0.18)
        let count = await countSteps(samples)
        XCTAssertEqual(count, 0)
    }

    func testSlowWalkingCountsSteps() async {
        let samples = makeRhythmicSamples(cadenceSpm: 60, duration: 60)
        let count = await countSteps(samples)
        XCTAssertGreaterThanOrEqual(count, 52)
        XCTAssertLessThanOrEqual(count, 68)
    }

    func testRunningCountsSteps() async {
        let samples = makeRhythmicSamples(cadenceSpm: 170, duration: 60, amplitude: 0.16)
        let count = await countSteps(samples)
        XCTAssertGreaterThanOrEqual(count, 150)
        XCTAssertLessThanOrEqual(count, 188)
    }

    func testOverlappingWindowsDoNotDoubleCount() async {
        let samples = makeRhythmicSamples(cadenceSpm: 100, duration: 12)
        let processor = StepCountingProcessorActor()
        var total = 0
        for chunkStart in stride(from: 0, to: samples.count, by: 25) {
            let chunk = Array(samples[chunkStart..<min(chunkStart + 25, samples.count)])
            let results = await processor.ingest(chunk)
            total += results.reduce(0) { $0 + $1.newSteps }
        }
        XCTAssertGreaterThanOrEqual(total, 16)
        XCTAssertLessThanOrEqual(total, 24)
    }

    func testDailyStoreResetsAtLocalMidnightAndPreservesPreviousDay() {
        let suite = "StepCountingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let store = StepCountStore(defaults: defaults, keyPrefix: "testSteps", calendar: calendar)

        let dayOne = Date(timeIntervalSince1970: 1_704_067_140) // 2023-12-31 23:59 UTC
        let dayTwo = Date(timeIntervalSince1970: 1_704_067_260) // 2024-01-01 00:01 UTC

        let previous = store.add(steps: 4, at: dayOne)
        XCTAssertEqual(previous.totalSteps, 4)

        let current = store.loadSummary(for: dayTwo)
        XCTAssertEqual(current.totalSteps, 0)
        XCTAssertEqual(store.loadSummary(for: dayOne).totalSteps, 4)
    }

    @MainActor
    func testDailyGoalPersistsAcrossServices() {
        let suite = "StepCountingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let firstStore = StepCountStore(defaults: defaults, keyPrefix: "testSteps")
        let firstService = StepCountingService(store: firstStore)
        firstService.setDailyGoal(12_500)

        let secondStore = StepCountStore(defaults: defaults, keyPrefix: "testSteps")
        let secondService = StepCountingService(store: secondStore)

        XCTAssertEqual(secondService.state.dailyGoal, 12_500)
    }

    private func countSteps(_ samples: [AccelerometerSample]) async -> Int {
        let processor = StepCountingProcessorActor()
        let results = await processor.ingest(samples)
        return results.reduce(0) { $0 + $1.newSteps }
    }

    private func makeRhythmicSamples(cadenceSpm: Double,
                                     duration: TimeInterval,
                                     amplitude: Double = 0.12,
                                     sampleRate: Double = 50) -> [AccelerometerSample] {
        let frequency = cadenceSpm / 60.0
        let interval = 1.0 / sampleRate
        return stride(from: 0.0, to: duration, by: interval).map { t in
            let wave = sin(2 * Double.pi * frequency * t)
            let lateral = 0.015 * sin(2 * Double.pi * frequency * t + .pi / 4)
            return AccelerometerSample(timestamp: Date(timeIntervalSince1970: t),
                                       x: lateral,
                                       y: 0,
                                       z: 1 + amplitude * wave,
                                       unit: "g")
        }
    }
}
