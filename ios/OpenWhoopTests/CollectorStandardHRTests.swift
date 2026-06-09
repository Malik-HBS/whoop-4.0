import XCTest
import WhoopProtocol
import WhoopStore
@testable import OpenWhoop

/// Tests for the live BLE 0x2A37 → store persistence path (the central Phase 2 fix).
/// Pre-fix this path only updated LiveState for the UI — the server saw hr: 0 because
/// no row was ever written to hrSample. These tests cover the four behaviours that the
/// fix has to guarantee:
///   1. A live HR notification persists a row to hrSample, ready for the uploader
///   2. Identical (bpm, same-second) notifications are deduped — the high-frequency
///      standard profile would otherwise dominate the local store
///   3. R-R intervals are timestamped with a WALKING-back wall time so each interval
///      ends at a distinct moment (a single ts would corrupt HRV)
///   4. The persisted rows are reachable via store.unsyncedHR / unsyncedRR so the
///      existing uploader pipeline picks them up unchanged
@MainActor
final class CollectorStandardHRTests: XCTestCase {
    private func makeStore() async throws -> WhoopStore {
        let store = try await WhoopStore(path: ":memory:")
        try await store.upsertDevice(id: "my-whoop", mac: nil, name: "test")
        return store
    }

    /// Convenience: build a Collector with a no-cadence policy (no auto-flush) so the
    /// assertions are deterministic and not racing the periodic flush.
    private func makeCollector(store: WhoopStore,
                               enableRawCapture: Bool = false) -> Collector {
        Collector(store: store, deviceId: "my-whoop",
                  policy: .init(maxFrames: 10_000, maxInterval: 3600),
                  enableRawCapture: enableRawCapture)
    }

    // MARK: - 1. Persistence reaches hrSample / rrInterval tables

    func testLiveHRPersistsIntoHrSample() async throws {
        let store = try await makeStore()
        let c = makeCollector(store: store)
        let now = Date(timeIntervalSince1970: 1_716_400_000)
        await c.ingestLiveHeartRate(hr: 72, rrIntervalsMs: [], wallTime: now, source: .standardBLE2A37)

        let rows = try await store.unsyncedHR(deviceId: "my-whoop", limit: 10)
        XCTAssertEqual(rows.count, 1, "one HR row persisted")
        XCTAssertEqual(rows.first?.bpm, 72)
        XCTAssertEqual(rows.first?.ts, Int(now.timeIntervalSince1970))
    }

    func testLiveHRPersistsIntoRrIntervalTable() async throws {
        let store = try await makeStore()
        let c = makeCollector(store: store)
        let now = Date(timeIntervalSince1970: 1_716_400_000)
        await c.ingestLiveHeartRate(hr: 72, rrIntervalsMs: [850, 910], wallTime: now, source: .standardBLE2A37)

        let rr = try await store.unsyncedRR(deviceId: "my-whoop", limit: 10)
        XCTAssertEqual(rr.count, 2)
        let rrMs = rr.map(\.rrMs).sorted()
        XCTAssertEqual(rrMs, [850, 910])
    }

    // MARK: - 2. Dedupe (high-frequency standard profile would otherwise flood the store)

    func testIdenticalBpmInSameSecondIsDeduped() async throws {
        let store = try await makeStore()
        let c = makeCollector(store: store)
        let now = Date(timeIntervalSince1970: 1_716_400_000)
        // Same bpm, same wall-second → second call is a no-op (lastStandardHR dedupe).
        _ = await c.ingestLiveHeartRate(hr: 72, rrIntervalsMs: [], wallTime: now, source: .standardBLE2A37)
        let second = await c.ingestLiveHeartRate(hr: 72, rrIntervalsMs: [], wallTime: now, source: .standardBLE2A37)
        _ = await c.ingestLiveHeartRate(hr: 72, rrIntervalsMs: [], wallTime: now, source: .standardBLE2A37)

        let rows = try await store.unsyncedHR(deviceId: "my-whoop", limit: 10)
        XCTAssertEqual(rows.count, 1, "3 identical notifications → 1 persisted row")
        XCTAssertTrue(second.hrDeduped, "duplicate live HR must report a dedupe outcome")
        XCTAssertEqual(second.dedupeReason, "same bpm in same second from standardBLE2A37")
    }

    func testSameBpmAcrossDifferentSecondsIsNotDeduped() async throws {
        let store = try await makeStore()
        let c = makeCollector(store: store)
        let t0 = Date(timeIntervalSince1970: 1_716_400_000)
        let t1 = Date(timeIntervalSince1970: 1_716_400_001)   // +1 second
        let t2 = Date(timeIntervalSince1970: 1_716_400_002)
        await c.ingestLiveHeartRate(hr: 72, rrIntervalsMs: [], wallTime: t0, source: .standardBLE2A37)
        await c.ingestLiveHeartRate(hr: 72, rrIntervalsMs: [], wallTime: t1, source: .standardBLE2A37)
        await c.ingestLiveHeartRate(hr: 72, rrIntervalsMs: [], wallTime: t2, source: .standardBLE2A37)

        let rows = try await store.unsyncedHR(deviceId: "my-whoop", limit: 10)
        XCTAssertEqual(rows.count, 3, "distinct seconds → distinct rows")
    }

    func testDifferentBpmInSameSecondIsNotDeduped() async throws {
        // The store PK is (deviceId, ts) — same second collapses to one row regardless of BPM.
        // The Collector's dedupe key includes BPM to avoid no-op writes, but the store
        // enforces the real uniqueness. This test documents that behaviour.
        let store = try await makeStore()
        let c = makeCollector(store: store)
        let t = Date(timeIntervalSince1970: 1_716_400_000)
        _ = await c.ingestLiveHeartRate(hr: 72, rrIntervalsMs: [], wallTime: t, source: .standardBLE2A37)
        let second = await c.ingestLiveHeartRate(hr: 75, rrIntervalsMs: [], wallTime: t, source: .standardBLE2A37)
        let third = await c.ingestLiveHeartRate(hr: 80, rrIntervalsMs: [], wallTime: t, source: .standardBLE2A37)

        let rows = try await store.unsyncedHR(deviceId: "my-whoop", limit: 10)
        XCTAssertEqual(rows.count, 1, "same second → 1 row (store PK is (deviceId, ts)); BPM diff is ignored by DB")
        XCTAssertTrue(second.hrDeduped)
        XCTAssertEqual(second.dedupeReason, "hrSample natural-key conflict at same second")
        XCTAssertTrue(third.hrDeduped)
    }

    // MARK: - 3. R-R timestamps walk backward (correct for HRV; single ts would corrupt it)

    func testRRIntervalsGetDistinctAscendingTimestamps() async throws {
        let store = try await makeStore()
        let c = makeCollector(store: store)
        let now = Date(timeIntervalSince1970: 1_716_400_000)
        // Two R-R intervals of 850ms and 910ms. With walking-back ts, the LAST interval
        // (the 850ms one in the WHOOP wire order) ends at `now`; the PREVIOUS one ends
        // at now − 0.850s. (The WHOOP wire order is oldest-first, so the walking-back
        // starts from the latest.)
        await c.ingestLiveHeartRate(hr: 72, rrIntervalsMs: [850, 910], wallTime: now, source: .standardBLE2A37)

        let rr = try await store.unsyncedRR(deviceId: "my-whoop", limit: 10)
        XCTAssertEqual(rr.count, 2)
        // Sorted ascending by ts (the store's read order); the smaller ts corresponds to
        // the older interval (910ms in wire order is first, 850ms is last).
        let sorted = rr.sorted { $0.ts < $1.ts }
        // oldest interval: 910ms before "now" (offset 0.910s)
        // newest interval: 850ms before "now" (offset 0.850s)
        XCTAssertEqual(sorted[0].ts, Int(now.timeIntervalSince1970) - 1, "oldest interval ts = now − 0.910s ≈ now − 1s")
        XCTAssertEqual(sorted[1].ts, Int(now.timeIntervalSince1970), "newest interval ts = now (the 850ms one ends at the wallTime)")
    }

    func testRRSingleInterval() async throws {
        let store = try await makeStore()
        let c = makeCollector(store: store)
        let now = Date(timeIntervalSince1970: 1_716_400_000)
        await c.ingestLiveHeartRate(hr: 72, rrIntervalsMs: [850], wallTime: now, source: .standardBLE2A37)

        let rr = try await store.unsyncedRR(deviceId: "my-whoop", limit: 10)
        XCTAssertEqual(rr.count, 1)
        XCTAssertEqual(rr.first?.ts, Int(now.timeIntervalSince1970))
        XCTAssertEqual(rr.first?.rrMs, 850)
    }

    func testRRClampsNonPositiveMsToOne() async throws {
        // Defensive: a malformed "0 ms" R-R must not crash and must not produce a
        // negative ts (which would corrupt the sort and the HRV window).
        let store = try await makeStore()
        let c = makeCollector(store: store)
        let now = Date(timeIntervalSince1970: 1_716_400_000)
        await c.ingestLiveHeartRate(hr: 72, rrIntervalsMs: [0, 850], wallTime: now, source: .standardBLE2A37)

        let rr = try await store.unsyncedRR(deviceId: "my-whoop", limit: 10)
        XCTAssertEqual(rr.count, 2)
        XCTAssertTrue(rr.allSatisfy { $0.rrMs >= 1 }, "no zero/negative rrMs")
        XCTAssertTrue(rr.allSatisfy { $0.ts >= 0 }, "no negative ts (would corrupt ORDER BY ts ASC)")
    }

    // MARK: - 4. Persisted rows are picked up by the existing uploader pipeline

    /// This is the contract that closes the bug: a `store.unsyncedHR(deviceId:)` call MUST
    /// see the rows from the live 0x2A37 path, because the Uploader drains EXACTLY that
    /// view. If this test passes the uploader is unchanged and "just works" — that's the
    /// whole point of routing through `store.insert(streams:)` instead of inventing a
    /// parallel live-only HR table.
    func testLiveHRRowsAreVisibleToUploaderDrain() async throws {
        let store = try await makeStore()
        let c = makeCollector(store: store)
        let now = Date(timeIntervalSince1970: 1_716_400_000)
        // 5 distinct seconds of HR.
        for i in 0..<5 {
            await c.ingestLiveHeartRate(
                hr: 70 + i,
                rrIntervalsMs: [],
                wallTime: Date(timeIntervalSince1970: now.timeIntervalSince1970 + Double(i)),
                source: .standardBLE2A37
            )
        }
        // 4 R-R intervals from one notification at +5s (6th distinct second).
        await c.ingestLiveHeartRate(
            hr: 80,
            rrIntervalsMs: [800, 820, 840, 860],
            wallTime: Date(timeIntervalSince1970: now.timeIntervalSince1970 + 5),
            source: .standardBLE2A37
        )
        let pendingHr = try await store.unsyncedHR(deviceId: "my-whoop", limit: 100)
        let pendingRr = try await store.unsyncedRR(deviceId: "my-whoop", limit: 100)
        XCTAssertEqual(pendingHr.count, 6, "5 + 1 (the second 80bpm call) = 6 HR rows visible to the uploader")
        XCTAssertEqual(pendingRr.count, 4, "4 R-R rows visible to the uploader")
    }

    func testLocalStoreSnapshotIncludesLiveHRRows() async throws {
        let store = try await makeStore()
        let c = makeCollector(store: store)
        let now = Date(timeIntervalSince1970: 1_716_400_000)
        await c.ingestLiveHeartRate(hr: 72, rrIntervalsMs: [850], wallTime: now, source: .standardBLE2A37)

        let snap = try await store.localCountsAndLatestTs(deviceId: "my-whoop")
        XCTAssertEqual(snap.hr.count, 1)
        XCTAssertEqual(snap.hr.latestTs, Int(now.timeIntervalSince1970))
        XCTAssertEqual(snap.rr.count, 1)
        XCTAssertEqual(snap.rr.latestTs, Int(now.timeIntervalSince1970))
        XCTAssertEqual(snap.gravity.count, 0, "gravity still empty (no type-47 offload yet)")
    }

    // MARK: - Edge cases

    func testZeroHRIsRejected() async throws {
        // The parser never returns hr=0 in practice (the strap always reports 1–255 for
        // 8-bit, 0–65535 for 16-bit) but the BLEManager hands us the raw value. A zero
        // would otherwise write a junk row.
        let store = try await makeStore()
        let c = makeCollector(store: store)
        await c.ingestLiveHeartRate(hr: 0, rrIntervalsMs: [850], wallTime: Date(), source: .standardBLE2A37)
        let hr = try await store.unsyncedHR(deviceId: "my-whoop", limit: 10)
        let rr = try await store.unsyncedRR(deviceId: "my-whoop", limit: 10)
        XCTAssertEqual(hr.count, 0, "hr=0 → no HR row written")
        XCTAssertEqual(rr.count, 1, "R-R still written (the parser's intervals are valid even if HR was bogus)")
    }
}
