import XCTest
@testable import DatenblickCore

final class TelekomHTMLParserTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // Synthetic fixtures for the experimental website adapter, not captured
    // Telekom account responses. The actual authenticated page needs device QA.
    private func page(remaining: String = "7,23 GB", total: String = "20 GB", extra: String = "", lang: String = "de") -> String {
        """
        <html lang="\(lang)"><body><h1>Ihr Datenvolumen</h1>
        <div class="remaining-volume"><div data-label="a>b" class="large remaining-volume-value">\(remaining)</div></div>
        <div class='start-volume'>\(total)</div>\(extra)</body></html>
        """
    }

    func testGermanVolumesUseSIUnitsAndExplicitCountdown() throws {
        let time = "<b class='days'>8</b><b class='hours'>14</b><b class='mins'>5</b><b class='secs'>10</b>"
        let result = try TelekomHTMLParser.decode(page(extra: time), now: now)
        XCTAssertEqual(result.totalBytes!, 20_000_000_000, accuracy: 0.001)
        XCTAssertEqual(result.usedBytes, 12_770_000_000, accuracy: 0.001)
        XCTAssertEqual(result.cycleEnd!.timeIntervalSince(now), 8 * 86_400 + 14 * 3_600 + 5 * 60 + 10, accuracy: 0.001)
        XCTAssertEqual(result.fetchedAt, now)
    }

    func testNestedTextEntitiesAndDifferentUnits() throws {
        let result = try TelekomHTMLParser.decode(page(remaining: "<span>512</span>&#160;MB", total: "2&nbsp;GB"), now: now)
        XCTAssertEqual(result.usedBytes, 1_488_000_000, accuracy: 0.001)
        XCTAssertNil(result.cycleEnd)
    }

    func testUnitInImmediateSiblingInsideParent() throws {
        let html = """
        <html lang="de"><body><h1>Ihr Datenvolumen</h1>
        <div><div class='remaining-volume-value'>7,23</div><span class='remaining-volume-unit'>GB</span></div>
        <div class='start-volume'>20 GB</div></body></html>
        """
        let result = try TelekomHTMLParser.decode(html, now: now)
        XCTAssertEqual(result.usedBytes, 12_770_000_000, accuracy: 0.001)
    }

    func testEnglishDecimalAndGermanGrouping() throws {
        let english = try TelekomHTMLParser.decode(page(remaining: "1.5 GB", total: "2 GB", lang: "en"), now: now)
        XCTAssertEqual(english.usedBytes, 500_000_000, accuracy: 0.001)
        let german = try TelekomHTMLParser.decode(page(remaining: "1.234,5 MB", total: "2 GB"), now: now)
        XCTAssertEqual(german.usedBytes, 765_500_000, accuracy: 0.001)
    }

    func testBinaryUnitIsNeverSilentlyTreatedAsDecimal() throws {
        let result = try TelekomHTMLParser.decode(page(remaining: "1 GiB", total: "2 GiB"), now: now)
        XCTAssertEqual(result.usedBytes, 1_073_741_824, accuracy: 0.001)
    }

    func testAuthenticationAndScriptOnlyMarkupAreRejected() {
        XCTAssertThrowsError(try TelekomHTMLParser.decode("<h1>Information</h1><p>Bitte Mobilfunknetz oder SMS Login nutzen.</p>"))
        let script = "<script>const sample = '<h1>Ihr Datenvolumen</h1><div class=\"remaining-volume-value\">1 GB</div><div class=\"start-volume\">2 GB</div>';</script>"
        XCTAssertThrowsError(try TelekomHTMLParser.decode(script))
    }

    func testInvalidOrAmbiguousDataNeverCreatesSnapshot() {
        for html in [
            page(remaining: "21 GB"), page(remaining: "-1 GB"),
            page(remaining: "NaN GB"), page(remaining: "7,23"),
            page(total: "0 GB"), page(total: "Unbegrenzt"),
            page(remaining: "1,2,3 GB"), page(remaining: "7,23 Mbit/s"),
            page(remaining: "1 2 GB"), page(remaining: "1.2.3 GB"),
            page(extra: "<div class='remaining-volume-value'>2 GB</div>")
        ] {
            XCTAssertThrowsError(try TelekomHTMLParser.decode(html))
        }
    }

    func testMissingOrInvalidCountdownDoesNotInventCycleEnd() throws {
        for extra in ["", "<b class='days'>8</b>", "<b class='days'>8</b><b class='hours'>99</b><b class='mins'>0</b><b class='secs'>0</b>"] {
            let result = try TelekomHTMLParser.decode(page(extra: extra), now: now)
            XCTAssertNil(result.cycleEnd)
        }
    }

    func testClassTokenLookalikesAreRejected() {
        XCTAssertThrowsError(try TelekomHTMLParser.decode(page().replacingOccurrences(of: "large remaining-volume-value", with: "large fake-remaining-volume-value")))
    }
}
