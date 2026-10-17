import XCTest
import QDomain
@testable import QFeatures

@MainActor
final class AbjadGlossaryModelTests: XCTestCase {
    private func model() -> AbjadGlossaryModel {
        AbjadGlossaryModel(shuffle: { n in Array((0..<n).reversed()) })
    }

    func testNoSearchShowsEveryGroupAndLetter() {
        let m = model()
        XCTAssertEqual(m.groups.flatMap { $0.shown }.count, abjadLetters.count)
        XCTAssertEqual(m.deck.count, abjadLetters.count)
        XCTAssertNil(m.status)
    }

    func testSearchNarrowsGroupsKeepsPartialEnclosureAndStatus() {
        let m = model()
        m.onSearchInput("\u{062B}")
        XCTAssertEqual(m.groups.count, 1)
        let g = m.groups[0]
        XCTAssertEqual(g.sound, .s)
        XCTAssertEqual(g.shown.map { $0.letter }, ["\u{062B}"])
        XCTAssertGreaterThan(g.letters.count, g.shown.count)
        XCTAssertEqual(m.deck.count, 1)
        XCTAssertEqual(m.status, "Showing 1 of \(abjadLetters.count) letters")
        m.clearSearch()
        XCTAssertNil(m.status)
        XCTAssertEqual(m.deck.count, abjadLetters.count)
    }

    func testRemoveLastTokenAndByKey() {
        let m = model()
        m.onSearchInput("\u{062B}\u{0628}")
        XCTAssertEqual(m.tokens.count, 2)
        m.removeLastToken()
        XCTAssertEqual(m.tokens.count, 1)
        m.removeToken(m.tokens[0].key)
        XCTAssertTrue(m.tokens.isEmpty)
    }

    func testPendingCWaitsForH() {
        let m = model()
        m.onSearchInput("c")
        XCTAssertEqual(m.pending, "c")
        XCTAssertTrue(m.tokens.isEmpty)
    }

    func testMoveCardWrapsAndStartsFaceUp() {
        let m = model()
        m.flipCard()
        XCTAssertTrue(m.deckState.flipped)
        m.moveCard(-1)
        XCTAssertEqual(m.deckState.position, abjadLetters.count - 1)
        XCTAssertFalse(m.deckState.flipped)
        m.moveCard(1)
        XCTAssertEqual(m.deckState.position, 0)
    }

    func testShuffleToggleAndCardThroughOrder() {
        let m = model()
        m.toggleShuffle()
        XCTAssertNotNil(m.deckState.order)
        XCTAssertEqual(m.card?.letter, abjadLetters.last?.letter)
        m.toggleShuffle()
        XCTAssertNil(m.deckState.order)
        XCTAssertEqual(m.card?.letter, abjadLetters.first?.letter)
    }

    func testChangingDeckResetsPlace() {
        let m = model()
        m.moveCard(3)
        m.toggleShuffle()
        m.onSearchInput("\u{062B}")
        XCTAssertEqual(m.deckState, DeckState())
    }

    func testShuffledOrderIsPermutation() {
        var g = SystemRandomNumberGenerator()
        let order = shuffledOrder(length: 10, using: &g)
        XCTAssertEqual(order.sorted(), Array(0..<10))
        XCTAssertEqual(shuffledOrder(length: 0, using: &g), [])
    }

    func testSplitPersianRuns() {
        let segs = splitPersianRuns("Like \u{0622} (\u{062E}\u{0627}\u{0646}\u{0647} \u{0645}\u{0646}), ok")
        XCTAssertEqual(segs.map { $0.isPersian }, [false, true, false, true, false])
        XCTAssertEqual(segs[0].text, "Like ")
        XCTAssertEqual(segs[3].text, "\u{062E}\u{0627}\u{0646}\u{0647} \u{0645}\u{0646}")
        XCTAssertEqual(segs[4].text, "), ok")
        XCTAssertEqual(splitPersianRuns("plain"), [NoteSegment(text: "plain", isPersian: false)])
        XCTAssertEqual(splitPersianRuns(""), [])
    }
}
