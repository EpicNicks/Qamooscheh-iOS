import XCTest
@testable import QDomain

/// A small seedable generator so sessions repeat.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(_ seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class LettersPracticeTests: XCTestCase {
    private func letter(_ glyph: String) -> AbjadLetter { abjadLetters.first { $0.letter == glyph }! }

    private func wrongOptions(_ q: LetterQuestion) -> [String] {
        q.options.enumerated().filter { $0.offset != q.answerIndex }.map { $0.element }
    }

    private let everyQuestion: [LetterQuestion] = {
        var all: [LetterQuestion] = []
        for seed in 0..<8 {
            var random = SeededGenerator(UInt64(seed))
            for l in abjadLetters {
                for kind in LetterQuestionKind.allCases { all.append(letterQuestion(kind, l, using: &random)) }
            }
        }
        return all
    }()

    func testEveryQuestionHasFourDistinctOptionsWithTheAnswerAmongThem() {
        for q in everyQuestion {
            XCTAssertEqual(q.options.count, letterOptionCount, q.key)
            XCTAssertEqual(Set(q.options).count, q.options.count, q.key)
            XCTAssertTrue(q.options.indices.contains(q.answerIndex), q.key)
        }
    }

    func testAnswersAreWhatEachKindAsksFor() {
        for q in everyQuestion {
            let expected: String
            switch q.kind {
            case .letterToSound: expected = soundOf(q.letter.sound).label
            case .soundToLetter, .formToLetter: expected = q.letter.letter
            case .letterToForm: expected = letterInForm(q.letter, q.form)
            }
            XCTAssertEqual(q.answer, expected, q.key)
        }
    }

    func testNoDistractorIsAlsoARightAnswer() {
        for q in everyQuestion where q.kind == .letterToSound {
            XCTAssertFalse(wrongOptions(q).contains(soundOf(q.letter.sound).label), q.key)
        }
    }

    func testContextualFormsShowAJoinedShapeNeverTheIsolatedOne() {
        for q in everyQuestion where q.kind == .formToLetter || q.kind == .letterToForm {
            XCTAssertNotEqual(q.form, .isolated, q.key)
            XCTAssertNotEqual(letterInForm(q.letter, q.form), q.letter.letter, q.key)
        }
    }

    func testNonJoinersAreNeverAskedForAnInitialForm() {
        for q in everyQuestion where !q.letter.joinsNext && q.kind == .formToLetter {
            XCTAssertNotEqual(q.form, .initial, q.key)
        }
    }

    func testLookalikes() {
        XCTAssertEqual(lookalikes(letter("ب")).map { $0.letter }, ["پ", "ت", "ث", "ن", "ی"])
        XCTAssertTrue(lookalikes(letter("ل")).isEmpty)
        var random = SeededGenerator(1)
        let q = letterQuestion(.formToLetter, letter("ب"), using: &random)
        let family = ["پ", "ت", "ث", "ن", "ی"]
        XCTAssertGreaterThanOrEqual(wrongOptions(q).filter { family.contains($0) }.count, 2)
    }

    func testSoundToLetterOffersOtherSpellingsOfTheSameSound() {
        var random = SeededGenerator(3)
        let q = letterQuestion(.soundToLetter, letter("س"), using: &random)
        let pool = ["ث", "ص", "ش"]
        XCTAssertGreaterThanOrEqual(q.options.filter { pool.contains($0) }.count, 2)
        XCTAssertNil(q.promptGlyph)
    }

    func testASessionAsksAboutTenDifferentLettersAcrossEveryKind() {
        var random = SeededGenerator(42)
        let session = lettersSession(using: &random)
        XCTAssertEqual(session.totalCount, lettersSessionSize)
        XCTAssertEqual(Set(session.queue.map { $0.letter.letter }).count, lettersSessionSize)
        XCTAssertEqual(Set(session.queue.map { "\($0.kind)" }).count, LetterQuestionKind.allCases.count)
        XCTAssertEqual(Set(session.queue.map { $0.key }).count, session.queue.count)
    }

    func testTheSameSeedGivesTheSameSession() {
        var a = SeededGenerator(9)
        var b = SeededGenerator(9)
        var c = SeededGenerator(10)
        XCTAssertEqual(lettersSession(using: &a), lettersSession(using: &b))
        var a2 = SeededGenerator(9)
        XCTAssertNotEqual(lettersSession(using: &a2), lettersSession(using: &c))
    }

    func testAMissComesBackThreeQuestionsLaterOnce() {
        var random = SeededGenerator(5)
        var session = lettersSession(using: &random)
        let missed = session.current!
        let wrong = (missed.answerIndex + 1) % letterOptionCount
        let first = session.answer(wrong)!
        XCTAssertFalse(first.correct)
        XCTAssertTrue(first.requeued)
        session = first.session
        XCTAssertEqual(session.queue.count, lettersSessionSize)
        XCTAssertEqual(session.completedCount, 0)
        var retry = missed
        retry.attempt = 1
        XCTAssertEqual(session.queue[3], retry)

        for _ in 0..<3 { session = session.answer(session.current!.answerIndex)!.session }
        XCTAssertEqual(session.current!.key, missed.key)
        let second = session.answer(wrong)!
        XCTAssertFalse(second.requeued)
        XCTAssertEqual(second.session.queue.count, lettersSessionSize - 4)
    }

    func testTheScoreCountsFirstTriesOnly() {
        var random = SeededGenerator(5)
        var session = lettersSession(using: &random)
        let first = session.current!
        session = session.answer((first.answerIndex + 1) % letterOptionCount)!.session
        while !session.finished { session = session.answer(session.current!.answerIndex)!.session }
        XCTAssertEqual(session.firstTryCorrect, lettersSessionSize - 1)
        XCTAssertEqual(session.score, 0.9, accuracy: 1e-9)
        XCTAssertEqual(session.completedCount, lettersSessionSize)
        XCTAssertNil(session.answer(0))
    }
}
