import XCTest
@testable import QFeatures

final class HelpAboutTests: XCTestCase {
    func testFaqIdsUniqueAndNonEmpty() {
        XCTAssertEqual(Set(helpFaq.map { $0.id }).count, helpFaq.count)
        XCTAssertEqual(helpFaq.count, 8)
        for e in helpFaq { XCTAssertFalse(e.paragraphs.isEmpty) }
    }

    func testBulletsPlacement() {
        let tts = helpFaq.first { $0.id == "tts-voice" }!
        XCTAssertEqual(tts.blocks.count, 4)
        if case .bullets = tts.blocks[2] {} else { XCTFail("bullets after two paragraphs") }
        let saved = helpFaq.first { $0.id == "saved-words" }!
        if case .bullets = saved.blocks[1] {} else { XCTFail("bullets after one paragraph") }
        let hints = helpFaq.first { $0.id == "word-hints" }!
        XCTAssertEqual(hints.blocks.count, 3)
        let trailing = FaqEntry(id: "x", question: "q", paragraphs: ["a", "b"], bullets: ["c"])
        if case .bullets = trailing.blocks[2] {} else { XCTFail("trailing bullets") }
    }

    func testOpenState() {
        XCTAssertEqual(initialOpenIds(nil), [])
        XCTAssertEqual(initialOpenIds("nope"), [])
        XCTAssertEqual(initialOpenIds("xp"), ["xp"])
        XCTAssertEqual(toggled(["xp"], "fonts"), ["xp", "fonts"])
        XCTAssertEqual(toggled(["xp"], "xp"), [])
    }

    func testVersionLine() {
        XCTAssertEqual(AboutContent.versionLine(short: "1.2", build: "34"), "Version 1.2 (34)")
        XCTAssertEqual(AboutContent.versionLine(short: "1.2", build: "1.2"), "Version 1.2 (1.2)")
        XCTAssertEqual(AboutContent.versionLine(short: "1.2", build: nil), "Version 1.2")
        XCTAssertEqual(AboutContent.versionLine(short: nil, build: "7"), "Version 7")
        XCTAssertNil(AboutContent.versionLine(short: " ", build: ""))
    }
}
