import XCTest
import QModel
@testable import QDomain

final class ExerciseReportTests: XCTestCase {
    private let item = ReportableItem(prompt: "How are you?", tags: ["خوب<adj>"], renderType: .typeIn, unitKey: "01-greetings", skillKey: "02-how-are-you", ordinal: 4)

    func testCitesFullLocationGradedTextAndEachPlayedTakeOnce() {
        let context = reportContextFor(item, submittedText: " khubam ", courseVersion: 3, playedPaths: ["../../../audio/a.mp3", nil, "../../../audio/a.mp3"])
        XCTAssertEqual(context, ExerciseReportContext(
            prompt: "How are you?",
            exerciseTags: ["خوب<adj>"],
            submittedText: " khubam ",
            renderType: .typeIn,
            location: ExerciseReportLocation(courseVersion: 3, unitKey: "01-greetings", skillKey: "02-how-are-you", exerciseOrdinal: 4),
            audioFiles: ["../../../audio/a.mp3"]
        ))
    }

    func testLeavesOutSubmittedTextBeforeAnAnswer() {
        let context = reportContextFor(item, submittedText: nil, courseVersion: 3, playedPaths: ["../../../audio/a.mp3"])
        XCTAssertNil(context.submittedText)
        XCTAssertEqual(context.audioFiles, ["../../../audio/a.mp3"])
    }

    func testKeepsThemeLessonNilUnit() {
        var themed = item
        themed.unitKey = nil
        let context = reportContextFor(themed, submittedText: "x", courseVersion: 3, playedPaths: [])
        XCTAssertEqual(context.location, ExerciseReportLocation(courseVersion: 3, unitKey: nil, skillKey: "02-how-are-you", exerciseOrdinal: 4))
    }

    func testSendsNoLocationRatherThanHalfOfOne() {
        XCTAssertNil(reportContextFor(item, submittedText: "x", courseVersion: nil, playedPaths: []).location)
        var noSkill = item
        noSkill.skillKey = nil
        XCTAssertNil(reportContextFor(noSkill, submittedText: "x", courseVersion: 3, playedPaths: []).location)
        var noOrdinal = item
        noOrdinal.ordinal = nil
        XCTAssertNil(reportContextFor(noOrdinal, submittedText: "x", courseVersion: 3, playedPaths: []).location)
    }

    func testTreatsOrdinalZeroAsRealOrdinal() {
        var zero = item
        zero.ordinal = 0
        XCTAssertEqual(reportContextFor(zero, submittedText: "x", courseVersion: 3, playedPaths: []).location?.exerciseOrdinal, 0)
    }

    func testOffersEveryReasonAfterWrongAnswer() {
        XCTAssertEqual(reportReasonsFor(.incorrect).map { $0.value }, [.audioWrong, .answerShouldBeAccepted, .other])
    }

    func testOffersOnlyAudioAndOtherBeforeAnsweringAndAfterCorrect() {
        XCTAssertEqual(reportReasonsFor(.unanswered).map { $0.value }, [.audioWrong, .other])
        XCTAssertEqual(reportReasonsFor(.correct).map { $0.value }, [.audioWrong, .other])
    }
}
