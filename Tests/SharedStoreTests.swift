import Foundation
import XCTest
@testable import DatenblickCore

final class SharedStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: SharedStore!

    override func setUp() {
        super.setUp()
        suiteName = "DatenblickCoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = SharedStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        super.tearDown()
    }

    func testModeSwitchNeverReturnsDemoAsLiveReading() {
        store.settings.mode = .demo
        store.save(.demo())
        XCTAssertEqual(store.snapshot?.source, .demo)
        store.settings.mode = .telekom
        XCTAssertNil(store.snapshot)
        XCTAssertTrue(store.history.isEmpty)
        store.save(UsageSnapshot(usedBytes: 2, totalBytes: 10, source: .telekom))
        XCTAssertEqual(store.snapshot?.source, .telekom)
        store.settings.mode = .demo
        XCTAssertEqual(store.snapshot?.source, .demo)
    }

    func testManualSaveCannotOverwriteLiveSnapshot() {
        store.save(UsageSnapshot(usedBytes: 2, totalBytes: 10, source: .telekom))
        store.save(UsageSnapshot(usedBytes: 9, totalBytes: 10, source: .manual))
        XCTAssertEqual(store.snapshot?.usedBytes, 2)
        store.settings.mode = .manual
        XCTAssertEqual(store.snapshot?.usedBytes, 9)
    }

    func testHistoryIsBoundedAndDuplicateReadingIsReplaced() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        for index in 0..<100 {
            store.save(UsageSnapshot(usedBytes: Double(index), totalBytes: 100,
                                     fetchedAt: date.addingTimeInterval(Double(index)), source: .telekom))
        }
        XCTAssertEqual(store.history.count, 90)
        XCTAssertEqual(store.history.first?.usedBytes, 10)
        store.save(UsageSnapshot(usedBytes: 99, totalBytes: 100,
                                 fetchedAt: date.addingTimeInterval(99), source: .telekom))
        XCTAssertEqual(store.history.count, 90)
    }

    func testInvalidSettingsAreNormalizedAndMissingKeysHaveDefaults() throws {
        store.settings = AppSettings(monthlyLimitGB: -.infinity, cycleStartDay: 99,
                                     warningThreshold: -1, planName: "   ")
        XCTAssertEqual(store.settings.monthlyLimitGB, 40)
        XCTAssertEqual(store.settings.cycleStartDay, 31)
        XCTAssertEqual(store.settings.warningThreshold, 1)
        XCTAssertEqual(store.settings.planName, "Mein Telekom-Tarif")
        let migrated = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"mode":"manual"}"#.utf8))
        XCTAssertEqual(migrated.mode, .manual)
        XCTAssertEqual(migrated.monthlyLimitGB, 40)
    }

    func testInvalidSnapshotCannotReplaceGoodReading() {
        store.save(UsageSnapshot(usedBytes: 2, totalBytes: 10, source: .telekom))
        store.save(UsageSnapshot(usedBytes: .nan, totalBytes: 10, source: .telekom))
        XCTAssertEqual(store.snapshot?.usedBytes, 2)
    }

    func testOlderResponseCannotRegressLatestSnapshotOrHistory() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        store.save(UsageSnapshot(usedBytes: 8, totalBytes: 10, fetchedAt: date, source: .telekom))
        store.save(UsageSnapshot(usedBytes: 2, totalBytes: 10,
                                 fetchedAt: date.addingTimeInterval(-60), source: .telekom))
        XCTAssertEqual(store.snapshot?.usedBytes, 8)
        XCTAssertEqual(store.history.count, 1)
    }

    func testWidgetCacheDoesNotMutateHistoryAndAppCanRecordSameReading() {
        let snapshot = UsageSnapshot(usedBytes: 8, totalBytes: 10, source: .telekom)
        store.save(snapshot, recordHistory: false)
        XCTAssertEqual(store.snapshot, snapshot)
        XCTAssertTrue(store.history.isEmpty)
        store.save(snapshot)
        store.save(snapshot)
        XCTAssertEqual(store.history, [snapshot])
    }

    func testSnapshotAgeCheckIsIsolatedPerSource() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        store.save(UsageSnapshot(usedBytes: 8, totalBytes: 10, fetchedAt: date, source: .telekom))
        store.save(UsageSnapshot(usedBytes: 2, totalBytes: 10,
                                 fetchedAt: date.addingTimeInterval(-60), source: .manual))
        store.settings.mode = .manual
        XCTAssertEqual(store.snapshot?.usedBytes, 2)
    }

    func testSecondStoreReadsSameDataAndClearRemovesAllSources() {
        store.save(UsageSnapshot(usedBytes: 2, totalBytes: 10, source: .telekom))
        let secondStore = SharedStore(defaults: defaults)
        XCTAssertEqual(secondStore.snapshot, store.snapshot)
        store.settings.mode = .demo
        store.save(.demo())
        store.clear()
        XCTAssertEqual(store.settings, AppSettings())
        XCTAssertNil(store.snapshot)
        store.settings.mode = .demo
        XCTAssertNil(store.snapshot)
        XCTAssertTrue(store.history.isEmpty)
    }

    func testClearInvalidatesRunningWidgetRequestGeneration() {
        let secondStore = SharedStore(defaults: defaults)
        let before = secondStore.generation
        store.clear()
        XCTAssertNotEqual(secondStore.generation, before)
        XCTAssertEqual(store.generation, secondStore.generation)
    }
}
