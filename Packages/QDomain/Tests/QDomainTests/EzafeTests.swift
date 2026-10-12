import XCTest
@testable import QDomain

// Ezafe has no web test: covers its documented readings (see also the ezafe
// section of AttachedEndingsTests, which goes through the lexeme hint map).
final class EzafeTests: XCTestCase {
    private func hint(_ romanization: String) -> WordHint {
        return WordHint(translation: romanization, romanization: romanization, ruby: romanization)
    }

    func testAKasraOnAConsonantIsMinusE() {
        XCTAssertEqual(ezafeReadings("کتاب" + KASRA), [EzafeReading(base: "کتاب", ezafe: .e)])
    }

    func testAHamzaAboveASilentHehIsMinusYe() {
        XCTAssertEqual(ezafeReadings("خانه" + HAMZA_ABOVE), [EzafeReading(base: "خانه", ezafe: .ye)])
    }

    func testAnUnmarkedWordHasNoReadings() {
        XCTAssertEqual(ezafeReadings("کتاب"), [])
        XCTAssertEqual(ezafeReadings(""), [])
    }

    func testOrdersAFinalYehsTwoReadingsByWhatPrecedesIt() {
        XCTAssertEqual(
            ezafeReadings("هوای" + KASRA),
            [EzafeReading(base: "هوا", ezafe: .ye), EzafeReading(base: "هوای", ezafe: .e)]
        )
        XCTAssertEqual(
            ezafeReadings("ماهی" + KASRA),
            [EzafeReading(base: "ماهی", ezafe: .e), EzafeReading(base: "ماه", ezafe: .ye)]
        )
    }

    func testALinkingYehAfterAHalfSpaceIsAlwaysMinusYe() {
        XCTAssertEqual(
            ezafeReadings("خانه" + ZWNJ + "ی" + KASRA),
            [EzafeReading(base: "خانه", ezafe: .ye)]
        )
    }

    func testFindsAnEzafeHiddenBehindAShadda() {
        XCTAssertEqual(ezafeReadings("حق" + KASRA + "\u{0651}"), [EzafeReading(base: "حق", ezafe: .e)])
    }

    func testEzafeHintCarriesTheEzafeBesideTheBareWordsHint() {
        let lookup: (String) -> WordHint? = { $0 == "کتاب" ? self.hint("ketāb") : nil }
        var expected = hint("ketāb")
        expected.ezafe = .e
        XCTAssertEqual(ezafeHint("ک" + KASRA + "تاب" + KASRA, lookup: lookup), expected)
    }

    func testEzafeHintIsNilWithNoMarkOrNoKnownReading() {
        let lookup: (String) -> WordHint? = { $0 == "کتاب" ? self.hint("ketāb") : nil }
        XCTAssertNil(ezafeHint("کتاب", lookup: lookup))
        XCTAssertNil(ezafeHint("میز" + KASRA, lookup: lookup))
    }

    func testEzafeHintTriesTheSecondReadingWhenTheFirstIsUnknown() {
        // هوایِ: the lexicon has the bare word هوا, not هوای.
        let lookup: (String) -> WordHint? = { $0 == "هوا" ? self.hint("havā") : nil }
        XCTAssertEqual(ezafeHint("هوای" + KASRA, lookup: lookup)?.ezafe, .ye)
        let own: (String) -> WordHint? = { $0 == "چای" ? self.hint("chāy") : nil }
        XCTAssertEqual(ezafeHint("چای" + KASRA, lookup: own)?.ezafe, .e)
    }
}
