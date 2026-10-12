import XCTest
import QModel
@testable import QDomain

final class AnswerRegisterTests: XCTestCase {
    private func hint(_ register: Register?) -> WordHint {
        return WordHint(translation: "", romanization: nil, ruby: nil, register: register)
    }

    private lazy var hintMap: [String: WordHint] = [
        "خونه": hint(.spoken),
        "خانه": hint(.written),
        "من": hint(.both),
        "رفتم": hint(nil),
    ]

    // answerRegister

    func testSpokenWhenAnyWordIsSpokenEvenBesideAWrittenOne() {
        XCTAssertEqual(answerRegister("خانه خونه", hintMap: hintMap), .spoken)
    }

    func testWrittenWhenTheMostMarkedWordIsWritten() {
        XCTAssertEqual(answerRegister("من خانه رفتم", hintMap: hintMap), .written)
    }

    func testNilWhenNoWordIsSpecificToARegister() {
        XCTAssertNil(answerRegister("من رفتم", hintMap: hintMap))
        XCTAssertNil(answerRegister("unknown words", hintMap: hintMap))
    }

    func testLooksWordsUpPastSurroundingPunctuation() {
        XCTAssertEqual(answerRegister("خونه؟", hintMap: hintMap), .spoken)
    }

    // describeAnswerRegister

    private func typed(_ answer: [String]) -> GradedExercise {
        return GradedExercise(type: .typeIn, scriptMode: .native, answer: answer)
    }

    func testLabelsTheAnswerNearestTheSubmissionAndListsOthersInAnotherRegister() {
        let note = describeAnswerRegister(typed(["من خانه", "من خونه", "من رفتم"]), submittedText: "من خونه", hintMap: hintMap)
        XCTAssertEqual(note, AnswerRegisterNote(label: "informal", alternatives: [AnswerRegisterAlternative(answer: "من خانه", label: "formal")]))
    }

    func testCapsTheAlternativesAtTwo() {
        let many = typed(["خونه", "خانه", "من خانه", "خانه من"])
        XCTAssertEqual(describeAnswerRegister(many, submittedText: "خونه", hintMap: hintMap)?.alternatives.count, 2)
    }

    func testNilWhenNothingIsSpecificToARegister() {
        XCTAssertNil(describeAnswerRegister(typed(["من رفتم"]), submittedText: "من رفتم", hintMap: hintMap))
    }

    func testReadsAWordBanksAcceptedTileOrders() {
        let bank = GradedExercise(type: .wordBank, scriptMode: .native, answer: ["من", "خونه"], alternativeAnswers: [["خانه", "من"]])
        let note = describeAnswerRegister(bank, submittedText: "من خونه", hintMap: hintMap)
        XCTAssertEqual(note, AnswerRegisterNote(label: "informal", alternatives: [AnswerRegisterAlternative(answer: "خانه من", label: "formal")]))
    }
}
