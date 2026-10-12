import XCTest
@testable import QDomain

final class AnswerDiffTests: XCTestCase {
    func testLevenshteinBasics() {
        XCTAssertEqual(AnswerDiff.levenshteinDistance("", ""), 0)
        XCTAssertEqual(AnswerDiff.levenshteinDistance("abc", ""), 3)
        XCTAssertEqual(AnswerDiff.levenshteinDistance("", "abc"), 3)
        XCTAssertEqual(AnswerDiff.levenshteinDistance("kitten", "sitting"), 3)
        XCTAssertEqual(AnswerDiff.levenshteinDistance("same", "same"), 0)
    }

    func testLevenshteinPersian() {
        XCTAssertEqual(AnswerDiff.levenshteinDistance("کتاب", "کتان"), 1)
    }

    func testLevenshteinCountsUtf16Units() {
        // An astral scalar is two UTF-16 units, as in JS string indexing.
        XCTAssertEqual(AnswerDiff.levenshteinDistance("\u{1F600}", ""), 2)
    }

    func testNormalizeCaseLowersAndCollapsesWhitespace() {
        XCTAssertEqual(AnswerDiff.normalizeCase("  Hello   WORLD \n"), "hello world")
        XCTAssertEqual(AnswerDiff.normalizeCase(""), "")
        XCTAssertEqual(AnswerDiff.normalizeCase("   "), "")
        XCTAssertEqual(AnswerDiff.normalizeCase("A\tB"), "a b")
    }

    func testFoldLatinVarianceDropsMarkersAndDoubledVowels() {
        XCTAssertEqual(AnswerDiff.foldLatinVariance("ma'ani"), "mani")
        XCTAssertEqual(AnswerDiff.foldLatinVariance("kaaba"), "kaba")
        XCTAssertEqual(AnswerDiff.foldLatinVariance("sa-lam"), "salam")
        XCTAssertEqual(AnswerDiff.foldLatinVariance("book"), "bok")
    }

    func testFoldLatinVarianceKeepsDoubledConsonants() {
        XCTAssertEqual(AnswerDiff.foldLatinVariance("mamnoon"), "mamnon")
        XCTAssertEqual(AnswerDiff.foldLatinVariance("rass"), "rass")
    }

    func testFoldLatinVarianceSeparatedVowelsStay() {
        // The marker is skipped without resetting the last-appended char, as on the web.
        XCTAssertEqual(AnswerDiff.foldLatinVariance("a'a"), "a")
        XCTAssertEqual(AnswerDiff.foldLatinVariance("aba"), "aba")
    }
}
