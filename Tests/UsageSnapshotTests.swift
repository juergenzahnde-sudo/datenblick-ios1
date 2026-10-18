import Foundation
import XCTest
@testable import DatenblickCore

final class UsageSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRemainingAndFractionUseActualByteCounts() {
        let snapshot = UsageSnapshot(usedBytes: 12_400_000_000, totalBytes: 40_000_000_000, source: .telekom)
        XCTAssertEqual(snapshot.remainingBytes, 27_600_000_000)
        XCTAssertEqual(snapshot.usedFraction, 0.31, accuracy: 0.0001)
    }

    func testOverageClampsVisualFractionAndRemaining() {
        let snapshot = UsageSnapshot(usedBytes: 55, totalBytes: 40, source: .manual)
        XCTAssertEqual(snapshot.remainingBytes, 0)
        XCTAssertEqual(snapshot.usedFraction, 1)
        XCTAssertEqual(snapshot.usedBytes, 55, "Preserve the real reading even when the ring is capped.")
    }

    func testUnlimitedDoesNotInventRemainingQuota() {
        let snapshot = UsageSnapshot(usedBytes: 800, totalBytes: 0, source: .telekom, isUnlimited: true)
        XCTAssertNil(snapshot.remainingBytes)
        XCTAssertEqual(snapshot.usedFraction, 0)
    }

    func testZeroAllocationIsNotUnlimited() {
        let snapshot = UsageSnapshot(usedBytes: 0, totalBytes: 0, source: .telekom)
        XCTAssertFalse(snapshot.isUnlimited)
        XCTAssertEqual(snapshot.remainingBytes, 0)
        XCTAssertEqual(snapshot.usedFraction, 0)
    }

    func testUnknownCycleRemainsUnknownAndExpiredCycleIsZero() {
        let unknown = UsageSnapshot(usedBytes: 0, source: .telekom)
        XCTAssertNil(unknown.daysRemaining(asOf: now))
        let expired = UsageSnapshot(usedBytes: 0, cycleEnd: now.addingTimeInterval(-1), source: .telekom)
        XCTAssertEqual(expired.daysRemaining(asOf: now), 0)
        let partialDay = UsageSnapshot(usedBytes: 0, cycleEnd: now.addingTimeInterval(86_401), source: .telekom)
        XCTAssertEqual(partialDay.daysRemaining(asOf: now), 2)
    }

    func testStalenessUsesTwoHourBoundary() {
        let snapshot = UsageSnapshot(usedBytes: 0, fetchedAt: now, source: .telekom)
        XCTAssertFalse(snapshot.isStale(asOf: now.addingTimeInterval(7_200)))
        XCTAssertTrue(snapshot.isStale(asOf: now.addingTimeInterval(7_201)))
    }

    func testDemoAlwaysHasDemoProvenance() {
        let snapshot = UsageSnapshot.demo(now: now)
        XCTAssertEqual(snapshot.source, .demo)
        XCTAssertEqual(snapshot.fetchedAt, now)
        XCTAssertNotNil(snapshot.cycleStart)
        XCTAssertNotNil(snapshot.cycleEnd)
    }
}
