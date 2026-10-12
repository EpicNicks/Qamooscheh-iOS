import XCTest
import QModel
@testable import QDomain

/// A Grader that answers from a script, for tests of the code around the real one.
private final class FakeGrader: Grader {
    var requests: [GraderRequest] = []
    private let reply: (GraderRequest) -> GraderResponse

    init(_ reply: @escaping (GraderRequest) -> GraderResponse) { self.reply = reply }

    func gradeEnvelope(_ request: GraderRequest) -> GraderResponse {
        requests.append(request)
        return reply(request)
    }

    func xp(verdict: String, attempt: Int, usedHint: Bool, retype: Bool, retypeNumber: Int?) -> Int { return 0 }
}

private func correctReply(_ matched: String, xp: Int = 10) -> GraderResponse {
    return GraderResponse(verdict: "Correct", matchedAnswer: matched, correct: true, xp: xp)
}

private func acceptedReply(_ matched: String, _ reasons: [String], xp: Int = 7, edits: [SeparatorEdit]? = nil) -> GraderResponse {
    return GraderResponse(verdict: "AcceptedWithCorrection", matchedAnswer: matched, correct: true, acceptedWithCorrection: true, reasons: reasons, separatorEdits: edits, xp: xp)
}

final class AnswerFeedbackTests: XCTestCase {
    private let zw = "\u{200C}"

    /// Strips the bidi isolates the note wraps a Persian word in.
    private func plain(_ note: String?) -> String? {
        return note?.replacingOccurrences(of: "\u{2068}", with: "").replacingOccurrences(of: "\u{2069}", with: "")
    }

    private func exercise(_ type: ExerciseType, _ answer: [String], romanized: Bool = false, alternatives: [[String]]? = nil) -> GradedExercise {
        return GradedExercise(type: type, scriptMode: romanized ? .romanized : .native, answer: answer, alternativeAnswers: alternatives)
    }

    private func check(_ grader: Grader?, _ course: String?, _ ex: GradedExercise, _ submitted: String, _ context: AnswerContext = AnswerContext()) -> AnswerFeedback {
        return checkAnswer(grader, courseCode: course, exercise: ex, submittedText: submitted, context: context)
    }

    // checkAnswer's request

    func testRequestUsesGradersSpellingAndXpInputs() {
        let grader = FakeGrader { _ in correctReply("x") }
        _ = check(grader, "fa", exercise(.typeIn, ["man ketab daram"], romanized: true), "man ketab daram", AnswerContext(attempt: 2, usedHint: true))
        _ = check(grader, "fa", exercise(.speak, ["سلام"]), "سلام")
        XCTAssertEqual(grader.requests, [
            GraderRequest(exerciseType: "TypeIn", scriptMode: "Romanized", submitted: "man ketab daram", acceptedAnswers: ["man ketab daram"], attempt: 2, usedHint: true),
            GraderRequest(exerciseType: "Speak", scriptMode: "Native", submitted: "سلام", acceptedAnswers: ["سلام"]),
        ])
    }

    func testRequestHandsSelectionItsTilesAndAlternatives() {
        let grader = FakeGrader { _ in correctReply("x") }
        let wordBank = exercise(.wordBank, ["من", "کتاب", "دارم"], alternatives: [["کتاب", "دارم"]])
        _ = check(grader, "fa", wordBank, "من کتاب دارم")
        XCTAssertEqual(grader.requests[0].exerciseType, "WordBank")
        XCTAssertEqual(grader.requests[0].acceptedAnswers, ["من", "کتاب", "دارم"])
        XCTAssertEqual(grader.requests[0].alternativeAnswers, [["کتاب", "دارم"]])
    }

    func testRequestPassesRetypeInputsThrough() {
        let grader = FakeGrader { _ in correctReply("x", xp: 2) }
        let feedback = check(grader, "fa", exercise(.typeIn, ["x"]), "x", AnswerContext(attempt: 1, usedHint: false, retype: true, retypeNumber: 2))
        XCTAssertEqual(grader.requests[0].retype, true)
        XCTAssertEqual(grader.requests[0].retypeNumber, 2)
        XCTAssertEqual(feedback.xp, 2)
    }

    // checkAnswer's verdict and XP

    func testVerdictAndXpComeFromGrader() {
        let typeIn = exercise(.typeIn, ["x"])
        XCTAssertEqual(check(FakeGrader { _ in correctReply("x", xp: 10) }, "fa", typeIn, "x"),
                       AnswerFeedback(verdict: .correct, note: nil, xp: 10, separators: nil))
        let acc = check(FakeGrader { _ in acceptedReply("x", []) }, "fa", typeIn, "x")
        XCTAssertEqual(acc.verdict, .acceptedWithCorrection)
        XCTAssertEqual(acc.xp, 7)
        XCTAssertEqual(check(FakeGrader { _ in GraderResponse() }, "fa", typeIn, "y"),
                       AnswerFeedback(verdict: .incorrect, note: nil, xp: 0, separators: nil))
    }

    func testPendingWithoutGrader() {
        let pending = AnswerFeedback(verdict: .pending, note: nil, xp: 0, separators: nil)
        XCTAssertEqual(check(nil, "fa", exercise(.typeIn, ["x"]), " X "), pending)
        XCTAssertEqual(check(nil, "fa", exercise(.typeIn, ["x"]), "y"), pending)
        let wordBank = exercise(.wordBank, ["من", "کتاب"], alternatives: [["کتاب", "من"]])
        XCTAssertEqual(check(nil, "fa", wordBank, "کتاب من"), pending)
    }

    func testPendingWhenGraderCannotInterpretRequest() {
        let grader = FakeGrader { _ in GraderResponse(verdict: nil, error: "unknown exerciseType 'Nope'.") }
        XCTAssertEqual(check(grader, "fa", exercise(.typeIn, ["x"]), "x"), AnswerFeedback(verdict: .pending, note: nil, xp: 0, separators: nil))
    }

    // checkAnswer's spacing hint (issue #39)

    private var matched: String { return "من می\(zw)خرم" }
    private let missingZwnj = SeparatorEdit(kind: .missingZwnj, index: 5, length: 1)

    private func withEdits(_ edits: [SeparatorEdit]) -> FakeGrader {
        let m = matched
        return FakeGrader { _ in acceptedReply(m, ["ZwnjOrSpacing"], edits: edits) }
    }

    func testMissingHalfSpaceHintNamesWhereItGoes() {
        let feedback = check(withEdits([missingZwnj]), "fa", exercise(.typeIn, [matched]), "من میخرم")
        XCTAssertEqual(feedback.verdict, .acceptedWithCorrection)
        XCTAssertEqual(feedback.xp, 7)
        XCTAssertEqual(plain(feedback.note), "Close \u{2014} the half-space (ZWNJ) was off: needs a half-space after می.")
        XCTAssertEqual(feedback.separators, SeparatorMarks(matchedAnswer: matched, edits: [missingZwnj]))
    }

    func testWordsEachKindOfEdit() {
        let typeIn = exercise(.typeIn, [matched])
        func note(_ edits: [SeparatorEdit]) -> String? { return plain(check(withEdits(edits), "fa", typeIn, "x").note) }
        let lead = "Close \u{2014} the half-space (ZWNJ) was off: needs "
        XCTAssertEqual(note([SeparatorEdit(kind: .spaceForZwnj, index: 5, length: 1)]), lead + "a half-space, not a space, after می.")
        XCTAssertEqual(note([SeparatorEdit(kind: .missingSpace, index: 2, length: 1)]), lead + "a space after من.")
        XCTAssertEqual(note([SeparatorEdit(kind: .extraZwnj, index: 2, length: 0)]), lead + "no half-space after من.")
        XCTAssertEqual(note([SeparatorEdit(kind: .missingSpace, index: 2, length: 1), missingZwnj]), lead + "a space after من; a half-space after می.")
    }

    func testNamesWordAfterEditAtWordStart() {
        let feedback = check(withEdits([SeparatorEdit(kind: .extraSpace, index: 0, length: 0)]), "fa", exercise(.typeIn, [matched]), "x")
        XCTAssertEqual(plain(feedback.note), "Close \u{2014} the half-space (ZWNJ) was off: needs no space before من.")
    }

    func testFallsBackToReasonAloneWithoutEdits() {
        let feedback = check(withEdits([]), "fa", exercise(.typeIn, [matched]), "من میخرم")
        XCTAssertEqual(feedback.note, "Close \u{2014} the half-space (ZWNJ) was off.")
        XCTAssertNil(feedback.separators)
    }

    func testWrongAnswerGetsNoSpacingNote() {
        let feedback = check(FakeGrader { _ in GraderResponse() }, "fa", exercise(.typeIn, [matched]), "من میخرم")
        XCTAssertEqual(feedback.verdict, .incorrect)
        XCTAssertNil(feedback.note)
        XCTAssertNil(feedback.separators)
    }

    // checkAnswer's reason notes

    func testArabicLetterReason() {
        let grader = FakeGrader { _ in acceptedReply("کتاب", ["CodepointSubstitution"]) }
        XCTAssertEqual(check(grader, "fa", exercise(.typeIn, ["کتاب"]), "\u{0643}\u{062A}\u{0627}\u{0628}").note,
                       "Close \u{2014} used the Arabic form of a letter instead of the Persian one.")
    }

    func testSaysNothingForReasonWithoutWording() {
        let grader = FakeGrader { _ in acceptedReply("かな", ["VariantFormSubstitution"]) }
        XCTAssertNil(check(grader, "ja", exercise(.typeIn, ["かな"]), "かな").note)
    }

    // checkAnswer's typo note (issue #42)

    func testNamesWordOfForgivenTypo() {
        let grader = FakeGrader { _ in acceptedReply("من کتاب دارم", ["EditDistanceTypo"]) }
        let feedback = check(grader, "fa", exercise(.typeIn, ["من کتاب دارم"]), "من کتاو دارم")
        XCTAssertEqual(feedback.verdict, .acceptedWithCorrection)
        XCTAssertEqual(plain(feedback.note), "Close \u{2014} a small typo: کتاب, not کتاو.")
    }

    func testIgnoresReadingAidsNamingTheWord() {
        // کِتابِ مَن with kasra on the ke and be, fatha on the mim.
        let withAids = "\u{06A9}\u{0650}\u{062A}\u{0627}\u{0628}\u{0650} \u{0645}\u{064E}\u{0646}"
        let grader = FakeGrader { _ in acceptedReply(withAids, ["EditDistanceTypo"]) }
        XCTAssertEqual(plain(check(grader, "fa", exercise(.typeIn, [withAids]), "کتاو من").note), "Close \u{2014} a small typo: کتاب, not کتاو.")
    }

    func testNamesRomanizedTypoWordInGraderOrder() {
        let grader = FakeGrader { _ in acceptedReply("man ketab daram", ["EditDistanceTypo", "LatinizationVariance"]) }
        let ex = exercise(.typeIn, ["man ketab daram"], romanized: true)
        XCTAssertEqual(plain(check(grader, "fa", ex, "man ketob daram").note), "Close \u{2014} a small typo: ketab, not ketob, romanization spelling.")
    }

    func testGivesWholeAnswerWhenRomanizedTypoMovedASpace() {
        let grader = FakeGrader { _ in acceptedReply("man ketab daram", ["EditDistanceTypo", "LatinizationVariance"]) }
        let ex = exercise(.typeIn, ["man ketab daram"], romanized: true)
        XCTAssertEqual(plain(check(grader, "fa", ex, "man ketabdaram").note), "Close \u{2014} a small typo: it's man ketab daram, romanization spelling.")
    }

    // closestAnswerFirst (issue #42)

    func testPutsNearestAnswerFirst() {
        XCTAssertEqual(closestAnswerFirst("I have a book", ["I've got a book", "I have a book.", "I own a book"]),
                       ["I have a book.", "I own a book", "I've got a book"])
    }

    func testKeepsAuthoredOrderForTiesAndEmptySubmission() {
        XCTAssertEqual(closestAnswerFirst("", ["b", "a"]), ["b", "a"])
        XCTAssertEqual(closestAnswerFirst("c", ["b", "a"]), ["b", "a"])
    }

    // TextMatch (web lib/textMatch)

    func testLooksCorrectIgnoresCaseAndWhitespace() {
        XCTAssertTrue(TextMatch.looksCorrect("  Hello   World ", ["hello world"]))
        XCTAssertFalse(TextMatch.looksCorrect("hello", ["hello world"]))
        XCTAssertFalse(TextMatch.looksCorrect("x", []))
    }
}
