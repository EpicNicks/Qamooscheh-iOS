import XCTest
@testable import QDomain

/// Loads the bundled glossary.json (generated from web glossaryContent.ts) and walks it.
final class GlossaryTests: XCTestCase {
    private let glossary = loadGlossary()
    private var fa: [GlossaryEntry] { glossary.forCourse("fa") }

    private func find(_ path: String...) -> GlossaryEntry? { findGlossaryEntry(fa, path: path) }

    func testPersianCourseHasTopLevelEntriesInOrder() {
        XCTAssertEqual(fa.map { $0.id }, ["abjad", "counting", "time", "colors", "ezafe"])
        XCTAssertEqual(fa.map { $0.title }, ["Persian Letters (Abjad)", "Counting", "Time", "Colors", "Ezafe - Word Glue"])
    }

    func testFoldersNestTheirLeaves() {
        XCTAssertEqual(find("counting")?.children.map { $0.id }, ["cardinal", "ordinal", "terms"])
        XCTAssertEqual(find("time")?.children.map { $0.id }, ["hours-minutes", "time-expressions", "relative-time"])
        XCTAssertEqual(find("counting")?.isFolder, true)
        XCTAssertEqual(find("colors")?.isFolder, false)
    }

    func testAbjadEntryIsAViewNotATable() {
        let abjad = find("abjad")
        XCTAssertEqual(abjad?.view, .abjad)
        XCTAssertEqual(abjad?.terms, [])
    }

    func testCardinalCollapsesEachCompoundRunIntoOnePatternRow() {
        let terms = find("counting", "cardinal")?.terms ?? []
        XCTAssertEqual(terms.count, 11 + 9 + 16 + 1 + 13)
        XCTAssertEqual(terms.first, GlossaryTerm(term: "\u{0635}\u{0641}\u{0631}", romanization: "sefr", definition: "zero"))
        guard let twenties = terms.first(where: { $0.definition.hasSuffix("(21-29)") }) else {
            return XCTFail("missing 21-29 row")
        }
        XCTAssertEqual(twenties.romanization, "bist-o-yek, bist-o-do, ..., bist-o-noh")
        XCTAssertEqual(twenties.definition, "twenty-one, twenty-two, ..., twenty-nine (21-29)")
        XCTAssertEqual(terms.first(where: { $0.definition.hasSuffix("(91-99)") })?.definition, "ninety-one, ninety-two, ..., ninety-nine (91-99)")
        XCTAssertEqual(terms.last?.romanization, "dodesilyon")
        XCTAssertEqual(terms.last?.definition, "one duodecillion (10^39)")
    }

    func testOrdinalKeepsNoteAndRomanizationlessEllipsisRow() {
        let ordinal = find("counting", "ordinal")
        XCTAssertTrue((ordinal?.note ?? "").hasPrefix("Other than \"first\" ("))
        XCTAssertEqual(ordinal?.terms.last, GlossaryTerm(term: "...", romanization: nil, definition: ""))
    }

    func testPersianTextKeepsZwnjAndDiacritics() {
        let last = find("counting", "terms")?.terms.last
        XCTAssertEqual(last?.term, "\u{0628}\u{06CC}\u{200C}\u{0646}\u{0647}\u{0627}\u{06CC}\u{062A}")
        XCTAssertEqual(last?.romanization, "bi-nah\u{0101}yat")
        XCTAssertEqual(last?.definition, "infinity")
        XCTAssertEqual(find("ezafe")?.terms[2].term, "\u{062E}\u{0627}\u{0646}\u{0647}\u{0654} \u{0645}\u{0646}")
    }

    func testFindReturnsNilForEmptyUnknownOrTooDeepPath() {
        XCTAssertNil(findGlossaryEntry(fa, path: []))
        XCTAssertNil(find("nope"))
        XCTAssertNil(find("counting", "nope"))
        XCTAssertNil(find("colors", "anything"))
        XCTAssertNotNil(find("time", "relative-time"))
    }

    func testCourseWithoutGlossaryGetsEmptyTree() {
        XCTAssertEqual(glossary.forCourse("ja"), [])
        XCTAssertEqual(glossary.forCourse(nil), [])
        XCTAssertEqual(glossary.forCourse(""), [])
    }

    func testParsesOptionalFieldsAndRejectsUnknownView() throws {
        let parsed = try parseGlossary(#"{"courses":{"x":[{"id":"a","title":"A","terms":[{"term":"t","definition":"d"}],"note":"n"}]}}"#)
        XCTAssertEqual(
            parsed.forCourse("x"),
            [GlossaryEntry(id: "a", title: "A", terms: [GlossaryTerm(term: "t", romanization: nil, definition: "d")], note: "n")]
        )
        XCTAssertThrowsError(try parseGlossary(#"{"courses":{"x":[{"id":"a","title":"A","view":"other"}]}}"#))
    }
}
