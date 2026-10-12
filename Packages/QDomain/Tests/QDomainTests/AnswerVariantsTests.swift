import XCTest
import QModel
@testable import QDomain

final class AnswerVariantsTests: XCTestCase {
    private let a0: AudioMap = ["setareh": ["a0.mp3"]]
    private let a2: AudioMap = ["setareh": ["a2.mp3"], "hooman": ["h2.mp3"]]

    private let typeIn = ExerciseArtifact(type: .typeIn, scriptMode: .native, prompt: "p", answer: ["سلام", "درود", "های"])

    // shownAnswerVariant

    func testShowsVariantClosestToSubmissionByIndexInAnswer() {
        XCTAssertEqual(shownAnswerVariant(typeIn, submittedText: "های"), AnswerVariant(index: 2, text: "های"))
        XCTAssertEqual(shownAnswerVariant(typeIn, submittedText: "درود"), AnswerVariant(index: 1, text: "درود"))
    }

    func testKeepsFirstAnswerWithNoSubmission() {
        XCTAssertEqual(shownAnswerVariant(typeIn, submittedText: nil), AnswerVariant(index: 0, text: "سلام"))
    }

    func testIndexesWordBankAlternativeOrdersAfterThePrimaryOne() {
        let bank = ExerciseArtifact(type: .wordBank, scriptMode: .native, prompt: "p", tiles: ["a", "b", "c"], answer: ["a", "b"], alternativeAnswers: [["b", "a"], ["c", "a"]])
        XCTAssertEqual(shownAnswerVariant(bank, submittedText: "a b"), AnswerVariant(index: 0, text: "a b"))
        XCTAssertEqual(shownAnswerVariant(bank, submittedText: "b a"), AnswerVariant(index: 1, text: "b a"))
        XCTAssertEqual(shownAnswerVariant(bank, submittedText: "c a"), AnswerVariant(index: 2, text: "c a"))
    }

    // variantAudio

    func testUsesTheShownVariantsRecording() {
        XCTAssertEqual(variantAudio(answerAudio: a0, answerVariantAudio: [a0, nil, a2], index: 2), a2)
    }

    func testFallsBackToAnswerAudioWhenFieldIsMissing() {
        XCTAssertEqual(variantAudio(answerAudio: a0, answerVariantAudio: nil, index: 1), a0)
    }

    func testFallsBackToAnswerAudioForNilEmptyOrAbsentEntry() {
        let variants: [AudioMap?] = [a0, nil, [:], ["setareh": []]]
        for index in [1, 2, 3, 9] {
            XCTAssertEqual(variantAudio(answerAudio: a0, answerVariantAudio: variants, index: index), a0)
        }
    }

    func testIsNilWhenNothingAtAllIsRecorded() {
        XCTAssertNil(variantAudio(answerAudio: nil, answerVariantAudio: [nil, nil], index: 1))
        XCTAssertNil(variantAudio(answerAudio: nil, answerVariantAudio: nil, index: 0))
    }

    func testKeepsTheVariantsOwnVoiceMap() {
        let audio = variantAudio(answerAudio: a0, answerVariantAudio: [a0, a2], index: 1)
        XCTAssertEqual(audio?["hooman"], ["h2.mp3"])
        XCTAssertEqual(audio?["setareh"], ["a2.mp3"])
    }

    func testExerciseOverloadReadsItsOwnFields() {
        var ex = typeIn
        ex.answerAudio = a0
        ex.answerVariantAudio = [a0, a2]
        XCTAssertEqual(variantAudio(ex, index: 1), a2)
    }
}
