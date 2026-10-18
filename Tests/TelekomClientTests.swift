import Foundation
import XCTest
@testable import DatenblickCore

final class TelekomClientTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func decode(_ json: String) throws -> UsageSnapshot {
        try TelekomClient.decode(Data(json.utf8), now: now)
    }

    func testNumericStatusAndRemainingSeconds() throws {
        let snapshot = try decode(#"{"usedVolume":12500000000,"initialVolume":40000000000,"remainingSeconds":172800}"#)
        XCTAssertEqual(snapshot.source, .telekom)
        XCTAssertEqual(snapshot.usedBytes, 12_500_000_000)
        XCTAssertEqual(snapshot.totalBytes, 40_000_000_000)
        XCTAssertEqual(snapshot.cycleEnd, now.addingTimeInterval(172_800))
        XCTAssertNil(snapshot.cycleStart, "The API does not establish a cycle start.")
        XCTAssertEqual(snapshot.fetchedAt, now)
    }

    func testNumericStringsAndWrappedData() throws {
        let snapshot = try decode(#"{"data":{"usedVolume":"1200","initialVolume":"4000","remainingSeconds":"60"}}"#)
        XCTAssertEqual(snapshot.usedBytes, 1_200)
        XCTAssertEqual(snapshot.remainingBytes, 2_800)
        XCTAssertEqual(snapshot.cycleEnd, now.addingTimeInterval(60))
    }

    func testMillisecondsAreConvertedOnlyForTimestamps() throws {
        let snapshot = try decode(#"{"usedVolume":100,"initialVolume":200,"cycleEnd":1800000060000,"cycleStart":"2027-01-01T00:00:00Z"}"#)
        XCTAssertEqual(snapshot.cycleEnd, Date(timeIntervalSince1970: 1_800_000_060))
        XCTAssertNotNil(snapshot.cycleStart)
    }

    func testExplicitUnlimitedFlagWithoutTotal() throws {
        let snapshot = try decode(#"{"usedVolume":"1234","isUnlimited":true}"#)
        XCTAssertTrue(snapshot.isUnlimited)
        XCTAssertNil(snapshot.totalBytes)
        XCTAssertNil(snapshot.remainingBytes)
    }

    func testZeroTotalDoesNotMeanUnlimited() throws {
        let snapshot = try decode(#"{"usedVolume":0,"initialVolume":0}"#)
        XCTAssertFalse(snapshot.isUnlimited)
        XCTAssertEqual(snapshot.totalBytes, 0)
    }

    func testMissingCountdownDoesNotInventCycle() throws {
        let snapshot = try decode(#"{"usedVolume":100,"initialVolume":200}"#)
        XCTAssertNil(snapshot.cycleEnd)
    }

    func testLegacyPassNameIsUsedWhenPlanNameMissingOrEmpty() throws {
        let legacy = try decode(#"{"usedVolume":100,"initialVolume":200,"passName":"MagentaMobil"}"#)
        XCTAssertEqual(legacy.planName, "MagentaMobil")
        let blank = try decode(#"{"usedVolume":100,"initialVolume":200,"planName":"  ","passName":"Datenpass"}"#)
        XCTAssertEqual(blank.planName, "Datenpass")
    }

    func testHTMLAndLoginJSONAreRejected() {
        for input in ["<!doctype html><html>Bitte anmelden</html>", #"{"loginRequired":true}"#, "[]", "null"] {
            XCTAssertThrowsError(try decode(input))
        }
    }

    func testInvalidVolumesAndBooleanNumbersAreRejected() {
        let invalid = [
            #"{"usedVolume":-1,"initialVolume":200}"#,
            #"{"usedVolume":100,"initialVolume":-200}"#,
            #"{"usedVolume":true,"initialVolume":200}"#,
            #"{"usedVolume":"NaN","initialVolume":200}"#,
            #"{"usedVolume":100,"initialVolume":"Infinity"}"#,
            #"{"usedVolume":100}"#,
            #"{"initialVolume":200}"#,
            #"{"usedVolume":"12 GB","initialVolume":"40 GB"}"#
        ]
        for input in invalid { XCTAssertThrowsError(try decode(input), input) }
    }

    func testErrorsProvideGermanRecoveryText() {
        XCTAssertTrue(TelekomError.unavailable.localizedDescription.contains("Mobilfunknetz"))
        XCTAssertTrue(TelekomError.httpStatus(503).localizedDescription.contains("503"))
    }
}
