import XCTest
import QModel
import QDomain
import QData
@testable import QFeatures

private final class FinishingPlayer: RecordingPlaying {
    var end: PlayEnd = .completed
    func play(keys: [String], rate: Double, onEnd: @escaping (PlayEnd) -> Void) { onEnd(end) }
    func stop() {}
}

private final class RightGrader: Grader {
    func gradeEnvelope(_ request: GraderRequest) -> GraderResponse {
        let right = request.acceptedAnswers.contains(request.submitted)
        return GraderResponse(verdict: right ? "Correct" : "Incorrect", matchedAnswer: right ? request.submitted : nil, correct: right, xp: 0)
    }

    func xp(verdict: String, attempt: Int, usedHint: Bool, retype: Bool, retypeNumber: Int?) -> Int { 0 }
}

/// Mirrors Android ExerciseReportTest: the report sent for an exercise, asked or answered.
final class LessonExerciseReportTests: XCTestCase {
    private let exercise = ExerciseArtifact(type: .wordBank, scriptMode: .native, prompt: "Hello", answer: ["سلام"], tags: ["سلام<interj>"])
    private var instance: ExerciseInstance {
        ExerciseInstance(key: "k", unitKey: "u1", skillKey: "a", ordinal: 3, exercise: exercise, renderType: .typeIn)
    }
    private let take = "../../../audio/" + String(repeating: "a", count: 64) + ".mp3"

    func testCarriesTheExerciseWhatWasGradedHowItWasShownAndWhereItLives() {
        let report = exerciseReportRequest(instance: instance, submittedText: "salam ", reasons: [.answerShouldBeAccepted], details: "", courseVersion: 6, audioFiles: [take, take])
        XCTAssertEqual(report.exercisePrompt, "Hello")
        XCTAssertEqual(report.exerciseTags, ["سلام<interj>"])
        XCTAssertEqual(report.reasons, [.answerShouldBeAccepted])
        XCTAssertEqual(report.submittedAnswer, "salam ", "graded text, untrimmed")
        XCTAssertEqual(report.renderType, .typeIn)
        XCTAssertEqual(report.courseVersion, 6)
        XCTAssertEqual(report.unitKey, "u1")
        XCTAssertEqual(report.skillKey, "a")
        XCTAssertEqual(report.exerciseOrdinal, 3)
        XCTAssertEqual(report.audioFiles, [take], "each take once")
        XCTAssertNil(report.details, "no details without Something else")
    }

    func testReasonsGoInTheFormsOrderAndDetailsOnlyWithSomethingElse() {
        let report = exerciseReportRequest(instance: instance, submittedText: "x", reasons: [.other, .audioWrong], details: "  the audio cuts off ", courseVersion: 6, audioFiles: [])
        XCTAssertEqual(report.reasons, [.audioWrong, .other])
        XCTAssertEqual(report.details, "the audio cuts off")
        XCTAssertNil(report.audioFiles, "text-to-speech played: no files")
    }

    func testWithoutACourseVersionTheLocationIsLeftOutEntirely() {
        let report = exerciseReportRequest(instance: instance, submittedText: "x", reasons: [.audioWrong], details: "", courseVersion: 0, audioFiles: [])
        XCTAssertNil(report.courseVersion)
        XCTAssertNil(report.unitKey)
        XCTAssertNil(report.skillKey)
        XCTAssertNil(report.exerciseOrdinal)
    }

    func testTheFormNeedsAReasonAndWordsForSomethingElse() {
        XCTAssertFalse(canSendReport(reasons: [], details: ""))
        XCTAssertTrue(canSendReport(reasons: [.audioWrong], details: ""))
        XCTAssertFalse(canSendReport(reasons: [.other], details: "  "))
        XCTAssertTrue(canSendReport(reasons: [.other], details: "it's wrong"))
    }

    func testOnlyAWrongAnswerOffersThatItShouldBeAccepted() {
        XCTAssertEqual(reportReasonsFor(.incorrect).map { $0.value }, [.audioWrong, .answerShouldBeAccepted, .other])
        XCTAssertEqual(reportReasonsFor(.correct).map { $0.value }, [.audioWrong, .other])
        XCTAssertEqual(reportReasonsFor(.unanswered).map { $0.value }, [.audioWrong, .other])
        XCTAssertEqual(reportReasonsFor(.pending).map { $0.value }, [.audioWrong, .other])
    }

    func testAnExerciseReportedBeforeItsAnsweredCitesNoAnswer() {
        let report = exerciseReportRequest(instance: instance, submittedText: nil, reasons: [.audioWrong], details: "", courseVersion: 6, audioFiles: [take])
        XCTAssertNil(report.submittedAnswer)
        XCTAssertEqual(report.courseVersion, 6)
        XCTAssertEqual(report.unitKey, "u1")
        XCTAssertEqual(report.skillKey, "a")
        XCTAssertEqual(report.exerciseOrdinal, 3)
        XCTAssertEqual(report.audioFiles, [take])
    }

    func testAPendingAnswerReportsAsPendingAndAWrongOneAsIncorrect() {
        XCTAssertEqual(reportStage(.pending), .pending)
        XCTAssertEqual(reportStage(.correct), .correct)
        XCTAssertEqual(reportStage(.incorrect), .incorrect)
    }

    @MainActor
    func testTheFormListsTheStagesReasons() {
        let asked = ReportIssueModel(stage: .unanswered, build: { _, _ in SubmitExerciseReportRequest(exercisePrompt: "", exerciseTags: [], reasons: []) }, submit: { _ in })
        XCTAssertEqual(asked.reasonOptions.map { $0.value }, [.audioWrong, .other])
        let wrong = ReportIssueModel(stage: .incorrect, build: { _, _ in SubmitExerciseReportRequest(exercisePrompt: "", exerciseTags: [], reasons: []) }, submit: { _ in })
        XCTAssertEqual(wrong.reasonOptions.map { $0.value }, [.audioWrong, .answerShouldBeAccepted, .other])
    }

    // MARK: From a lesson

    private func listeningSession(grading: Bool = true, tags: [String] = ["a"], player: RecordingPlaying = FinishingPlayer(), report: Bool = true) -> LessonSession {
        let exercise = ExerciseArtifact(type: .listenType, scriptMode: .native, prompt: "p", answer: ["a"], tags: tags, promptAudio: ["v": [take]])
        let listened = ExerciseInstance(key: "u/s/0", unitKey: "u", skillKey: "s", ordinal: 0, exercise: exercise, renderType: .listenType)
        let setup = LessonSetup(courseCode: "fa", courseVersion: 4, instances: [listened])
        let deps = LessonDependencies(
            grader: grading ? RightGrader() : nil,
            gradingOnDevice: grading,
            submit: { _ in LessonSubmitResult.queued },
            sendReport: report ? { _ in } : nil,
            recordings: player
        )
        return LessonSession(setup: setup, dependencies: deps)
    }

    func testWhileAskedItReportsUnansweredWithThePromptsPlayedTake() throws {
        let session = listeningSession()
        session.playListening(slow: false)
        let form = try XCTUnwrap(session.askedReportForm)
        XCTAssertEqual(form.stage, .unanswered)
        XCTAssertNil(session.reportForm)
        let request = form.build([.audioWrong], "")
        XCTAssertNil(request.submittedAnswer)
        XCTAssertEqual(request.audioFiles, [take])
        XCTAssertEqual(request.courseVersion, 4)
    }

    func testAnUnplayedPromptCitesNoAudio() throws {
        let session = listeningSession()
        let request = try XCTUnwrap(session.askedReportForm).build([.audioWrong], "")
        XCTAssertNil(request.audioFiles)
    }

    func testAFailedPlayIsNotCited() throws {
        let player = FinishingPlayer()
        player.end = .failed
        let session = listeningSession(player: player)
        session.playListening(slow: false)
        XCTAssertNil(try XCTUnwrap(session.askedReportForm).build([.audioWrong], "").audioFiles)
    }

    func testOnceAnsweredItReportsTheVerdictsStageWithTheAnswer() throws {
        let right = listeningSession()
        right.playListening(slow: false)
        right.setTyped("a")
        right.check()
        XCTAssertNil(right.askedReportForm)
        let form = try XCTUnwrap(right.reportForm)
        XCTAssertEqual(form.stage, .correct)
        let request = form.build([.audioWrong], "")
        XCTAssertEqual(request.submittedAnswer, "a")
        XCTAssertEqual(request.audioFiles, [take])

        let wrong = listeningSession()
        wrong.setTyped("zz")
        wrong.check()
        XCTAssertEqual(try XCTUnwrap(wrong.reportForm).stage, .incorrect)

        let pending = listeningSession(grading: false)
        pending.setTyped("a")
        pending.check()
        XCTAssertEqual(try XCTUnwrap(pending.reportForm).stage, .pending)
    }

    func testNoReportWithoutTagsOrAChannel() {
        XCTAssertNil(listeningSession(tags: []).askedReportForm)
        XCTAssertNil(listeningSession(report: false).askedReportForm)
    }
}
