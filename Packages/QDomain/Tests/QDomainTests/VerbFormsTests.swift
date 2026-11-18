import XCTest
import QModel
@testable import QDomain

// verbForms.ts has no web suite: these cover its documented behaviour.
final class VerbFormsTests: XCTestCase {
    private func cell(_ written: String, spoken: String? = nil, negative: String, negativeSpoken: String? = nil) -> VerbFormCell {
        return VerbFormCell(written: written, spoken: spoken, negative: negative, negativeSpoken: negativeSpoken)
    }

    private func entry(_ table: [String: [String: VerbFormCell]]) -> VerbIndexEntry {
        return VerbIndexEntry(infinitive: "خریدن", presentStem: "خر", pastStem: "خرید", principalParts: [], table: table)
    }

    func testListsOnlyTensesWithATableInTeachingOrder() {
        let e = entry([
            "future": ["1s": cell("a", negative: "b")],
            "present": ["1s": cell("a", negative: "b")],
            "simplePast": [:],
        ])
        XCTAssertEqual(availableTenses(e).map { $0.tense }, ["present", "future"])
        XCTAssertEqual(availableTenses(e).map { $0.label }, ["Present", "Future"])
    }

    func testRowsFollowPersonOrderAndSkipMissingPersons() {
        let e = entry(["imperative": [
            "2p": cell("c", negative: "d"),
            "2s": cell("a", negative: "b"),
        ]])
        let rows = verbRows(e, tense: "imperative", negative: false)
        XCTAssertEqual(rows.map { $0.person }, ["2s", "2p"])
        XCTAssertEqual(rows.map { $0.label }, ["you", "you (pl.)"])
        XCTAssertEqual(rows.map { $0.written }, ["a", "c"])
    }

    func testNegativeRowsUseTheNegativeCells() {
        let e = entry(["present": ["1s": cell("w", spoken: "s", negative: "nw", negativeSpoken: "ns")]])
        XCTAssertEqual(verbRows(e, tense: "present", negative: false), [VerbRow(person: "1s", label: "I", written: "w", spoken: "s")])
        XCTAssertEqual(verbRows(e, tense: "present", negative: true), [VerbRow(person: "1s", label: "I", written: "nw", spoken: "ns")])
    }

    func testPastPerfectIsListedRightAfterPresentPerfect() {
        let keys = verbTenses.map { $0.tense }
        guard let i = keys.firstIndex(of: "presentPerfect") else { return XCTFail("no presentPerfect") }
        XCTAssertEqual(keys[i + 1], "pastPerfect")
        XCTAssertEqual(verbTenses[i + 1].label, "Past perfect")
        let e = entry(["pastPerfect": ["1s": cell("a", negative: "b")], "presentPerfect": ["1s": cell("a", negative: "b")]])
        XCTAssertEqual(availableTenses(e).map { $0.tense }, ["presentPerfect", "pastPerfect"])
    }

    func testRowsCarryTheMatchingRomanizations() {
        let c = VerbFormCell(
            written: "w", spoken: "s", negative: "nw", negativeSpoken: "ns",
            writtenRomanization: "wr", spokenRomanization: "sr",
            negativeRomanization: "nwr", negativeSpokenRomanization: "nsr"
        )
        let e = entry(["present": ["1s": c, "2s": cell("x", negative: "nx")]])
        let pos = verbRows(e, tense: "present", negative: false)
        XCTAssertEqual(pos[0].writtenRomanization, "wr")
        XCTAssertEqual(pos[0].spokenRomanization, "sr")
        XCTAssertNil(pos[1].writtenRomanization)
        XCTAssertNil(pos[1].spokenRomanization)
        let neg = verbRows(e, tense: "present", negative: true)
        XCTAssertEqual(neg[0], VerbRow(person: "1s", label: "I", written: "nw", spoken: "ns", writtenRomanization: "nwr", spokenRomanization: "nsr"))
        XCTAssertNil(neg[1].writtenRomanization)
        XCTAssertNil(neg[1].spokenRomanization)
    }

    func testAMissingTenseHasNoRows() {
        XCTAssertEqual(verbRows(entry([:]), tense: "present", negative: false), [])
    }

    func testSpokenColumnShowsWhenAnyRowHasOne() {
        let none = [VerbRow(person: "1s", label: "I", written: "a", spoken: nil)]
        let some = none + [VerbRow(person: "2s", label: "you", written: "b", spoken: "c")]
        XCTAssertFalse(hasSpokenColumn(none))
        XCTAssertTrue(hasSpokenColumn(some))
        XCTAssertFalse(hasSpokenColumn([]))
    }
}
