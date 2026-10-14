import XCTest
import QDomain
@testable import QFeatures

@MainActor
final class GlossaryModelTests: XCTestCase {
    private func glossary() -> Glossary {
        let leaf = GlossaryEntry(id: "greet", title: "Greetings", terms: [GlossaryTerm(term: "سلام", romanization: "salam", definition: "hello")])
        let folder = GlossaryEntry(id: "basics", title: "Basics", children: [leaf])
        let abjad = GlossaryEntry(id: "abjad", title: "Abjad", view: .abjad)
        return Glossary(courses: ["fa": [folder, abjad], "ja": [GlossaryEntry(id: "k", title: "Kana")]])
    }

    func testTermTableColumnsAre30_30_40() {
        let w = GlossaryColumns.widths(available: 344, spacing: 12)
        XCTAssertEqual(w.count, 3)
        XCTAssertEqual(w[0], 96, accuracy: 0.001)
        XCTAssertEqual(w[1], 96, accuracy: 0.001)
        XCTAssertEqual(w[2], 128, accuracy: 0.001)
        XCTAssertEqual(GlossaryColumns.widths(available: 0, spacing: 12), [0, 0, 0])
    }

    func testStartsOnTree() {
        let m = GlossaryModel(courseCode: "fa", glossary: glossary())
        guard case .tree(let e) = m.page else { return XCTFail("expected tree") }
        XCTAssertEqual(e.map { $0.id }, ["basics", "abjad"])
        XCTAssertFalse(m.isOnLeaf)
    }

    func testOpenLeafAndUp() {
        let m = GlossaryModel(courseCode: "fa", glossary: glossary())
        m.open(["basics", "greet"])
        guard case .leaf(_, let entry) = m.page else { return XCTFail("expected leaf") }
        XCTAssertEqual(entry.title, "Greetings")
        XCTAssertTrue(m.isOnLeaf)
        m.up()
        XCTAssertEqual(m.page, .tree(m.entries))
    }

    func testStalePathIsNotFound() {
        let m = GlossaryModel(courseCode: "fa", glossary: glossary())
        m.open(["basics", "nope"])
        XCTAssertEqual(m.page, .notFound)
        m.open(["basics"])
        XCTAssertEqual(m.page, .notFound, "a folder path is not a page")
    }

    func testUnknownCourseIsEmptyTree() {
        let m = GlossaryModel(courseCode: nil, glossary: glossary())
        XCTAssertEqual(m.page, .tree([]))
    }

    func testFoldersStartOpenAndToggle() {
        let m = GlossaryModel(courseCode: "fa", glossary: glossary())
        XCTAssertTrue(m.isOpen(["basics"]))
        m.toggle(["basics"])
        XCTAssertFalse(m.isOpen(["basics"]))
        XCTAssertTrue(m.isOpen(["basics", "greet"]))
        m.toggle(["basics"])
        XCTAssertTrue(m.isOpen(["basics"]))
    }

    func testRtlOnlyForNativeScriptInRtlCourse() {
        let fa = GlossaryModel(courseCode: "fa", glossary: glossary())
        XCTAssertTrue(fa.isRtl("سلام"))
        XCTAssertFalse(fa.isRtl("salam"))
        let ja = GlossaryModel(courseCode: "ja", glossary: glossary())
        XCTAssertFalse(ja.isRtl("こんにちは"))
    }
}
