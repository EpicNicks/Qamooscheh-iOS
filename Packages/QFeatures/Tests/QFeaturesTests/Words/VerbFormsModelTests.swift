import XCTest
import QModel
import QDomain
@testable import QFeatures

final class VerbFormsModelTests: XCTestCase {
    private let fatha = "\u{064E}"
    private let kh = "\u{062E}"

    /// Present and imperative only (simplePast lists before the imperative in teaching order, but is absent).
    private func entry(gloss: String? = "to buy") -> VerbIndexEntry {
        let marked = kh + fatha + "\u{0631}"
        return VerbIndexEntry(
            infinitive: marked + "\u{06CC}\u{062F}\u{0646}", presentStem: marked, pastStem: marked + "\u{06CC}\u{062F}",
            principalParts: [marked + "\u{06CC}\u{062F}\u{0646}", marked + "\u{06CC}\u{062F}"],
            table: [
                "imperative": [
                    "2s": VerbFormCell(written: "b" + marked, negative: "n" + marked, writtenRomanization: "bekhar", negativeRomanization: "nakhar"),
                    "2p": VerbFormCell(written: "bp" + marked, negative: "np" + marked),
                ],
                "present": [
                    "3s": VerbFormCell(
                        written: "w3" + marked, spoken: "s3" + marked, negative: "nw3" + marked, negativeSpoken: "ns3" + marked,
                        writtenRomanization: "mikharad", spokenRomanization: "mikhare",
                        negativeRomanization: "nemikharad", negativeSpokenRomanization: "nemikhare"),
                    "1s": VerbFormCell(written: "w1" + marked, negative: "nw1" + marked),
                ],
                "future": [:],
            ],
            gloss: gloss)
    }

    func testDefaultsToTheFirstAvailableTense() {
        let table = VerbFormsTable(entry: entry(), requestedTense: nil, negative: false, vowelMarks: true)
        XCTAssertEqual(table.tenses.map { $0.tense }, ["present", "imperative"])
        XCTAssertEqual(table.tense, "present")
        XCTAssertEqual(table.rows.map { $0.person }, ["1s", "3s"])
        XCTAssertEqual(table.gloss, "to buy")
    }

    func testKeepsARequestedTenseAndFallsBackFromAMissingOne() {
        XCTAssertEqual(VerbFormsTable(entry: entry(), requestedTense: "imperative", negative: false, vowelMarks: true).tense, "imperative")
        XCTAssertEqual(VerbFormsTable(entry: entry(), requestedTense: "future", negative: false, vowelMarks: true).tense, "present")
        XCTAssertEqual(VerbFormsTable(entry: entry(), requestedTense: "simplePast", negative: false, vowelMarks: true).tense, "present")
    }

    func testNegativeShowsNegativeFormsAndRomanizations() {
        let table = VerbFormsTable(entry: entry(), requestedTense: "present", negative: true, vowelMarks: true)
        let row = table.rows[1]
        XCTAssertEqual(row.written, "nw3" + kh + fatha + "\u{0631}")
        XCTAssertEqual(row.spoken, "ns3" + kh + fatha + "\u{0631}")
        XCTAssertEqual(row.writtenRomanization, "nemikharad")
        XCTAssertEqual(row.spokenRomanization, "nemikhare")
        XCTAssertTrue(table.negative)
    }

    func testSpokenColumnOnlyWhenARowHasOne() {
        XCTAssertTrue(VerbFormsTable(entry: entry(), requestedTense: "present", negative: false, vowelMarks: true).showsSpoken)
        XCTAssertFalse(VerbFormsTable(entry: entry(), requestedTense: "imperative", negative: false, vowelMarks: true).showsSpoken)
    }

    func testVowelMarksOffStripsEveryPersianString() {
        let table = VerbFormsTable(entry: entry(), requestedTense: "present", negative: false, vowelMarks: false)
        XCTAssertFalse(table.infinitive.contains(fatha))
        XCTAssertEqual(table.infinitive, kh + "\u{0631}\u{06CC}\u{062F}\u{0646}")
        XCTAssertFalse(table.principalParts.contains { $0.contains(fatha) })
        XCTAssertFalse(table.rows.contains { $0.written.contains(fatha) || ($0.spoken ?? "").contains(fatha) })
        XCTAssertEqual(table.rows[1].spoken, "s3" + kh + "\u{0631}")
        // Romanizations are left alone.
        XCTAssertEqual(table.rows[1].writtenRomanization, "mikharad")
    }

    func testVowelMarksOnKeepsThem() {
        let table = VerbFormsTable(entry: entry(), requestedTense: "present", negative: false, vowelMarks: true)
        XCTAssertTrue(table.infinitive.contains(fatha))
        XCTAssertTrue(table.rows[0].written.contains(fatha))
    }

    func testBlankGlossIsNil() {
        XCTAssertNil(VerbFormsTable(entry: entry(gloss: "  "), requestedTense: nil, negative: false, vowelMarks: true).gloss)
        XCTAssertNil(VerbFormsTable(entry: entry(gloss: nil), requestedTense: nil, negative: false, vowelMarks: true).gloss)
    }

    func testNoTablesMeansNoTense() {
        var empty = entry()
        empty.table = [:]
        let table = VerbFormsTable(entry: empty, requestedTense: "present", negative: false, vowelMarks: true)
        XCTAssertNil(table.tense)
        XCTAssertTrue(table.rows.isEmpty)
        XCTAssertFalse(table.showsSpoken)
    }

    func testSampleHasPresentWithSpokenAndPastWithout() {
        let present = VerbFormsTable(entry: VerbFormsSample.entry, requestedTense: nil, negative: false, vowelMarks: true)
        XCTAssertEqual(present.tense, "present")
        XCTAssertEqual(present.rows.count, 6)
        XCTAssertTrue(present.showsSpoken)
        XCTAssertFalse(VerbFormsTable(entry: VerbFormsSample.entry, requestedTense: "simplePast", negative: false, vowelMarks: true).showsSpoken)
    }
}

@MainActor
final class VocabularyVowelMarksTests: XCTestCase {
    func testLoadsTheLessonSettingAndDefaultsOn() async {
        let store = VocabularyStore(source: nil)
        let plain = SkillVocabularyModel(store: store, unitKey: "u1", skillKey: nil)
        await plain.loadVowelMarks()
        XCTAssertTrue(plain.vowelMarks)
        let off = SkillVocabularyModel(store: store, unitKey: "u1", skillKey: nil, vowelMarks: { false })
        XCTAssertTrue(off.vowelMarks)
        await off.loadVowelMarks()
        XCTAssertFalse(off.vowelMarks)
    }
}
