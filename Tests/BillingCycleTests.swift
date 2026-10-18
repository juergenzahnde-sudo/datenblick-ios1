import Foundation
import XCTest
@testable import DatenblickCore

final class BillingCycleTests: XCTestCase {
    private var berlin: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        berlin.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testFebruary31ClampsTo28AndResumes31InMarch() {
        let cycle = BillingCycle.dates(startDay: 31, now: date(2026, 2, 28), calendar: berlin)
        XCTAssertEqual(cycle.start, date(2026, 2, 28))
        XCTAssertEqual(cycle.end, date(2026, 3, 31))
        let before = BillingCycle.dates(startDay: 31, now: date(2026, 2, 15), calendar: berlin)
        XCTAssertEqual(before.start, date(2026, 1, 31))
        XCTAssertEqual(before.end, date(2026, 2, 28))
    }

    func testLeapYearUsesFebruary29() {
        let cycle = BillingCycle.dates(startDay: 31, now: date(2028, 2, 29), calendar: berlin)
        XCTAssertEqual(cycle.start, date(2028, 2, 29))
        XCTAssertEqual(cycle.end, date(2028, 3, 31))
    }

    func test31ClampsTo30InApril() {
        let cycle = BillingCycle.dates(startDay: 31, now: date(2026, 4, 30), calendar: berlin)
        XCTAssertEqual(cycle.start, date(2026, 4, 30))
        XCTAssertEqual(cycle.end, date(2026, 5, 31))
    }

    func testMidnightStartsNewCycleExactly() {
        let before = BillingCycle.dates(startDay: 1, now: date(2026, 2, 28, hour: 23, minute: 59), calendar: berlin)
        XCTAssertEqual(before.start, date(2026, 2, 1))
        XCTAssertEqual(before.end, date(2026, 3, 1))
        let after = BillingCycle.dates(startDay: 1, now: date(2026, 3, 1), calendar: berlin)
        XCTAssertEqual(after.start, date(2026, 3, 1))
        XCTAssertEqual(after.end, date(2026, 4, 1))
    }

    func testDaylightSavingRetainsLocalMidnightInsteadOfFixedSeconds() {
        let cycle = BillingCycle.dates(startDay: 29, now: date(2026, 3, 29), calendar: berlin)
        XCTAssertEqual(cycle.start, date(2026, 3, 29))
        XCTAssertEqual(cycle.end, date(2026, 4, 29))
        XCTAssertEqual(cycle.end.timeIntervalSince(cycle.start), 31 * 86_400 - 3_600, accuracy: 0.001)
    }

    func testOutOfRangeDaysAreClamped() {
        let first = BillingCycle.dates(startDay: -4, now: date(2026, 4, 15), calendar: berlin)
        XCTAssertEqual(first.start, date(2026, 4, 1))
        let last = BillingCycle.dates(startDay: 99, now: date(2026, 4, 30), calendar: berlin)
        XCTAssertEqual(last.start, date(2026, 4, 30))
    }
}
