import XCTest
@testable import QDomain

final class PersianNormalizeTests: XCTestCase {
    private let kasra = "\u{0650}"
    private let fatha = "\u{064E}"
    private let hamza = "\u{0654}"

    func testConstants() {
        XCTAssertEqual(ZWNJ.unicodeScalars.map { $0.value }, [0x200C])
        XCTAssertEqual(KASRA.unicodeScalars.map { $0.value }, [0x0650])
        XCTAssertEqual(HAMZA_ABOVE.unicodeScalars.map { $0.value }, [0x0654])
    }

    func testStripReadingAidsRemovesShortVowels() {
        XCTAssertEqual(PersianNormalize.stripReadingAids("ک\(kasra)تا\(kasra)ب"), "کتاب")
        XCTAssertEqual(PersianNormalize.stripReadingAids("م\(fatha)ن"), "من")
    }

    func testStripReadingAidsHamzaOnlyAfterHeh() {
        // After a heh the hamza is an ezafe aid: stripped.
        XCTAssertEqual(PersianNormalize.stripReadingAids("خانه\(hamza) من"), "خانه من")
        // Elsewhere it is part of the letter: kept.
        XCTAssertEqual(PersianNormalize.stripReadingAids("ا\(hamza)"), "ا\(hamza)")
    }

    func testStripReadingAidsLeavesTanvin() {
        XCTAssertEqual(PersianNormalize.stripReadingAids("لطفاً"), "لطفاً")
    }

    func testNormalizeStrictFoldsDigits() {
        XCTAssertEqual(PersianNormalize.normalizeStrict("\u{0660}\u{0661}\u{0669}"), "019")
        XCTAssertEqual(PersianNormalize.normalizeStrict("\u{06F0}\u{06F5}\u{06F9}"), "059")
    }

    func testNormalizeStrictCollapsesAndTrimsWhitespace() {
        XCTAssertEqual(PersianNormalize.normalizeStrict("  من   رفتم \n"), "من رفتم")
        XCTAssertEqual(PersianNormalize.normalizeStrict("   "), "")
    }

    func testNormalizeStrictDropsVowelMarks() {
        XCTAssertEqual(PersianNormalize.normalizeStrict("ک\(kasra)تاب"), "کتاب")
    }

    func testNormalizeStrictComposesHehWithHamzaToHehGoal() {
        // NFC composes heh + hamza above into U+06C0 before reading aids are looked at.
        XCTAssertEqual(PersianNormalize.normalizeStrict("خانه\(hamza)"), "خان\u{06C0}")
    }

    func testNormalizeStrictKeepsZwnjAndAlefMadda() {
        XCTAssertEqual(PersianNormalize.normalizeStrict("می\(ZWNJ)خرم آب"), "می\(ZWNJ)خرم آب")
    }

    func testFoldCodepointsArabicToPersian() {
        XCTAssertEqual(PersianNormalize.foldCodepoints("\u{064A}"), "\u{06CC}")
        XCTAssertEqual(PersianNormalize.foldCodepoints("\u{0643}"), "\u{06A9}")
        XCTAssertEqual(PersianNormalize.foldCodepoints("\u{0629}"), "\u{0647}")
        XCTAssertEqual(PersianNormalize.foldCodepoints("\u{0623}\u{0625}"), "\u{0627}\u{0627}")
    }

    func testFoldCodepointsExpandsHehGoalAndKeepsAlefMadda() {
        XCTAssertEqual(PersianNormalize.foldCodepoints("خان\u{06C0}"), "خانه\(ZWNJ)ی")
        XCTAssertEqual(PersianNormalize.foldCodepoints("آب"), "آب")
    }

    func testDetectArabicVariantsFindsEachWithPersianForm() {
        let hits = PersianNormalize.detectArabicVariants("\u{0643}\u{062A}\u{0627}\u{0628} \u{0639}\u{0644}\u{064A} \u{0645}\u{062F}\u{0631}\u{0633}\u{0629} \u{0623}\u{0628}")
        XCTAssertEqual(hits.map { $0.found }, ["\u{0643}", "\u{064A}", "\u{0629}", "\u{0623}"])
        XCTAssertEqual(hits.map { $0.suggested }, ["\u{06A9}", "\u{06CC}", "\u{0647}", "\u{0627}"])
        XCTAssertEqual(hits.first?.index, 0)
    }

    func testDetectArabicVariantsPersianInputIsClean() {
        XCTAssertEqual(PersianNormalize.detectArabicVariants("کتاب علی مدرسه"), [])
    }

    func testDetectArabicVariantsIndexIsUtf16() {
        // The emoji is two UTF-16 units, so the hit after it sits at offset 2.
        let hits = PersianNormalize.detectArabicVariants("\u{1F600}\u{064A}")
        XCTAssertEqual(hits.first?.index, 2)
    }
}
