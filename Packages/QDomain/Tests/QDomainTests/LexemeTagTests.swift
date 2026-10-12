import XCTest
@testable import QDomain

// lexemeTag has no web test: covers its documented behaviour.
final class LexemeTagTests: XCTestCase {
    func testParsesATagIntoItsSurfaceAndAttributeMarkers() {
        XCTAssertEqual(
            parseLexemeTag("سلام<interj><spoken>"),
            ParsedLexemeTag(surface: "سلام", attributes: ["interj", "spoken"])
        )
    }

    func testATagWithNoMarkersIsJustItsSurface() {
        XCTAssertEqual(parseLexemeTag("سلام"), ParsedLexemeTag(surface: "سلام", attributes: []))
    }

    func testAnAttachedEndingKeepsItsLeadingTatweelInTheSurface() {
        XCTAssertEqual(
            parseLexemeTag("\u{0640}م<poss>"),
            ParsedLexemeTag(surface: "\u{0640}م", attributes: ["poss"])
        )
    }

    func testATagWithNoSurfaceHasAnEmptyOne() {
        XCTAssertEqual(parseLexemeTag("<n>"), ParsedLexemeTag(surface: "", attributes: ["n"]))
    }
}
