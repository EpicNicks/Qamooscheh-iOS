import XCTest
import QModel
import QDomain
@testable import QFeatures

final class LessonFeedbackLogicTests: XCTestCase {
    private func instance(type: ExerciseType = .typeIn, unit: String? = "u1", answers: [String] = ["salam", "salaam"]) -> ExerciseInstance {
        let exercise = ExerciseArtifact(type: type, scriptMode: .native, prompt: "Hello", tiles: type == .wordBank ? ["salam", "x"] : nil, answer: answers, tags: ["salam"])
        return ExerciseInstance(key: "k", unitKey: unit, skillKey: "greetings", ordinal: 3, exercise: exercise, renderType: type)
    }

    func testFeedbackKindAcceptedCountsAsCorrect() {
        XCTAssertEqual(feedbackKind(.acceptedWithCorrection), .correct)
        XCTAssertEqual(feedbackKind(.correct), .correct)
        XCTAssertEqual(feedbackKind(.incorrect), .incorrect)
        XCTAssertEqual(feedbackKind(.pending), .pending)
    }

    func testProgressFraction() {
        XCTAssertEqual(sessionProgressFraction(completed: 0, total: 0), 0)
        XCTAssertEqual(sessionProgressFraction(completed: 1, total: 4), 0.25)
        XCTAssertEqual(sessionProgressFraction(completed: 9, total: 4), 1)
    }

    func testScorePercent() {
        XCTAssertEqual(scorePercent(0.755), 76)
        XCTAssertEqual(scorePercent(0), 0)
        XCTAssertEqual(scorePercent(1), 100)
    }

    func testRevealedLinesTypeInKeepsAllAnswers() {
        let lines = revealedAnswerLines(instance().exercise, submittedText: "salaam")
        XCTAssertEqual(Set(lines), Set(["salam", "salaam"]))
        XCTAssertEqual(lines.count, 2)
    }

    func testRevealedLinesWordBankIsOneLine() {
        let lines = revealedAnswerLines(instance(type: .wordBank, answers: ["a", "b"]).exercise, submittedText: "")
        XCTAssertEqual(lines.count, 1)
    }

    func testYourAnswerLine() {
        XCTAssertEqual(yourAnswerLine(""), "Your answer: (nothing submitted)")
        XCTAssertEqual(yourAnswerLine("hi"), "Your answer: hi")
        XCTAssertTrue(showsYourAnswer(.match))
        XCTAssertTrue(showsYourAnswer(.speak))
        XCTAssertFalse(showsYourAnswer(.typeIn))
    }

    func testCanSendReport() {
        XCTAssertFalse(canSendReport(reasons: [], details: ""))
        XCTAssertTrue(canSendReport(reasons: [.audioWrong], details: ""))
        XCTAssertFalse(canSendReport(reasons: [.other], details: "   "))
        XCTAssertTrue(canSendReport(reasons: [.other], details: "why"))
    }

    func testReportRequestWithLocation() {
        let request = exerciseReportRequest(instance: instance(), submittedText: "x", reasons: [.other, .audioWrong], details: "  more  ", courseVersion: 7, audioFiles: ["a.mp3", "a.mp3", "b.mp3"])
        XCTAssertEqual(request.reasons, [.audioWrong, .other])
        XCTAssertEqual(request.details, "more")
        XCTAssertEqual(request.submittedAnswer, "x")
        XCTAssertEqual(request.courseVersion, 7)
        XCTAssertEqual(request.unitKey, "u1")
        XCTAssertEqual(request.skillKey, "greetings")
        XCTAssertEqual(request.exerciseOrdinal, 3)
        XCTAssertEqual(request.audioFiles, ["a.mp3", "b.mp3"])
        XCTAssertEqual(request.renderType, .typeIn)
    }

    func testReportRequestWithoutVersionHasNoLocationAndDetailsOnlyForOther() {
        let request = exerciseReportRequest(instance: instance(unit: nil), submittedText: " ", reasons: [.audioWrong], details: "ignored", courseVersion: 0, audioFiles: [])
        XCTAssertNil(request.courseVersion)
        XCTAssertNil(request.unitKey)
        XCTAssertNil(request.skillKey)
        XCTAssertNil(request.exerciseOrdinal)
        XCTAssertNil(request.details)
        XCTAssertNil(request.submittedAnswer)
        XCTAssertNil(request.audioFiles)
    }

    @MainActor
    func testReportModelSendsAndReportsFailure() async {
        let inst = instance()
        let box = ReportBox()
        let model = ReportIssueModel(
            build: { reasons, details in exerciseReportRequest(instance: inst, submittedText: "x", reasons: reasons, details: details, courseVersion: 1, audioFiles: []) },
            submit: { request in
                if await box.shouldFail { throw URLError(.notConnectedToInternet) }
                await box.add(request)
            }
        )
        XCTAssertFalse(model.canSend)
        model.toggle(.audioWrong)
        XCTAssertTrue(model.canSend)
        let first = await model.send()
        XCTAssertFalse(first)
        XCTAssertEqual(model.status, .failed)
        XCTAssertEqual(model.statusMessage, "Couldn't send that \u{2014} try again?")
        await box.setFail(false)
        let second = await model.send()
        XCTAssertTrue(second)
        XCTAssertEqual(model.status, .sent)
        let count = await box.sent.count
        XCTAssertEqual(count, 1)
        XCTAssertFalse(model.canSend)
    }

    func testResultsCopy() {
        let done = lessonResultsCopy(end: .saved(completed: true, alreadyRecorded: false))
        XCTAssertEqual(done.title, "Lesson complete!")
        XCTAssertEqual(done.body, "The next lesson is unlocked.")
        XCTAssertEqual(done.passMark, lessonPassThreshold)
        let failed = lessonResultsCopy(end: .saved(completed: false, alreadyRecorded: false))
        XCTAssertEqual(failed.title, "Not passed yet")
        XCTAssertTrue(failed.body.contains("75%"))
        XCTAssertFalse(failed.passed)
        let practice = lessonResultsCopy(end: .practice)
        XCTAssertTrue(practice.body.contains("Practice round"))
        XCTAssertNil(practice.passMark)
        let queued = lessonResultsCopy(end: .queued(completed: nil))
        XCTAssertTrue(queued.body.contains("offline"))
        let rejected = lessonResultsCopy(end: .rejected(partial: true, reason: nil))
        XCTAssertEqual(rejected.title, "Only part of this lesson was saved")
        let savedWords = lessonResultsCopy(end: .queued(completed: nil), savedPractice: true)
        XCTAssertEqual(savedWords.title, "Saved words practised!")
        XCTAssertFalse(lessonResultsCopy(end: .saving).showsScore)
    }

    func testStreakAndGoalLines() {
        XCTAssertEqual(streakLine(days: 1), "1 day streak")
        XCTAssertEqual(streakLine(days: 5), "5 day streak")
        XCTAssertEqual(goalCelebrationLine(xpToday: 50, goalXp: 50), "50 of 50 XP today. Nice work.")
    }
}

private actor ReportBox {
    var shouldFail = true
    var sent: [SubmitExerciseReportRequest] = []
    func add(_ request: SubmitExerciseReportRequest) { sent.append(request) }
    func setFail(_ value: Bool) { shouldFail = value }
}
