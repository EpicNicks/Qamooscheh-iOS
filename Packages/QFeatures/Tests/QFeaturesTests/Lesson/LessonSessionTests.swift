import XCTest
import QModel
import QDomain
import QData
@testable import QFeatures

private final class ScriptedGrader: Grader {
    func gradeEnvelope(_ request: GraderRequest) -> GraderResponse {
        let right = request.acceptedAnswers.contains(request.submitted)
        return GraderResponse(verdict: right ? "Correct" : "Incorrect", matchedAnswer: right ? request.submitted : nil, correct: right, xp: 0)
    }

    func xp(verdict: String, attempt: Int, usedHint: Bool, retype: Bool, retypeNumber: Int?) -> Int { 0 }
}

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [SubmittedSession] = []
    var sessions: [SubmittedSession] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func add(_ session: SubmittedSession) {
        lock.lock()
        stored.append(session)
        lock.unlock()
    }
}

private final class EventLog {
    var events: [FeedbackEvent] = []
    func add(_ event: FeedbackEvent) { events.append(event) }
}

private struct Boom: Error {}

final class LessonSessionTests: XCTestCase {
    private func instance(_ ordinal: Int, _ type: ExerciseType, answer: String) -> ExerciseInstance {
        let exercise = ExerciseArtifact(type: type, scriptMode: .native, prompt: "p\(ordinal)", tiles: type == .wordBank ? [answer] : nil, answer: [answer], tags: ["t\(ordinal)"])
        return ExerciseInstance(key: "u/s/\(ordinal)", unitKey: "u", skillKey: "s", ordinal: ordinal, exercise: exercise, renderType: type)
    }

    private func makeSession(grading: Bool = true, practice: Bool = false, recorder: Recorder = Recorder(), events: EventLog = EventLog()) -> LessonSession {
        let setup = LessonSetup(
            courseCode: "fa", courseVersion: 3,
            instances: [instance(0, .wordBank, answer: "a"), instance(1, .typeIn, answer: "b")],
            exerciseCountBySkill: ["s": 2], practice: practice
        )
        let grader: Grader? = grading ? ScriptedGrader() : nil
        let deps = LessonDependencies(
            grader: grader,
            gradingOnDevice: grading,
            submit: { session in
                recorder.add(session)
                return LessonSubmitResult.queued
            },
            onFeedback: { events.add($0) }
        )
        return LessonSession(setup: setup, dependencies: deps)
    }

    func testCheckNeedsAnAnswer() {
        let session = makeSession()
        session.check()
        XCTAssertNil(session.review)
        XCTAssertEqual(session.state.completedCount, 0)
    }

    func testCorrectTileAnswerShowsReviewThenAdvances() {
        let events = EventLog()
        let session = makeSession(events: events)
        session.setTileAnswer("a")
        XCTAssertTrue(session.canCheck(keyboardPending: nil))
        session.check()
        XCTAssertEqual(session.review?.feedback.verdict, .correct)
        XCTAssertEqual(events.events, [.tilePlaced, .correct])
        session.continueOn()
        XCTAssertNil(session.review)
        XCTAssertEqual(session.instance?.ordinal, 1)
        XCTAssertNil(session.tileAnswer)
        XCTAssertEqual(session.state.completedCount, 1)
    }

    func testWrongAnswerRequeuesAndResetsTyping() {
        let session = makeSession()
        session.setTileAnswer("zzz")
        session.check()
        XCTAssertEqual(session.review?.feedback.verdict, .incorrect)
        session.continueOn()
        // The miss comes back later, the next exercise is on screen now.
        XCTAssertEqual(session.instance?.ordinal, 1)
        XCTAssertEqual(session.state.queue.count, 2)
        XCTAssertEqual(session.typed, "")
    }

    func testTypedBlankIsNotSubmitted() {
        let session = makeSession()
        session.setTileAnswer("a")
        session.check()
        session.continueOn()
        session.setTyped("   ")
        session.check()
        XCTAssertNil(session.review)
        session.setTyped("b")
        XCTAssertEqual(session.caret, 1)
        session.check()
        XCTAssertEqual(session.review?.feedback.verdict, .correct)
    }

    func testNoGraderMakesEveryAnswerPendingAndShowsTheSyncNote() {
        let session = makeSession(grading: false)
        XCTAssertTrue(session.showsSyncNote)
        session.setTileAnswer("zzz")
        session.check()
        XCTAssertEqual(session.review?.feedback.verdict, .pending)
        session.continueOn()
        // Pending answers are not requeued: the server decides.
        XCTAssertEqual(session.state.queue.count, 1)
    }

    func testFinishSubmitsOneSessionPerSkillAndEndsQueued() async throws {
        let recorder = Recorder()
        let session = makeSession(recorder: recorder)
        session.setTileAnswer("a")
        session.check()
        session.continueOn()
        session.setTyped("b")
        session.check()
        session.continueOn()
        XCTAssertEqual(session.phase, .saving)
        try await waitUntilEnded(session)
        XCTAssertEqual(recorder.sessions.count, 1)
        XCTAssertEqual(recorder.sessions[0].courseCode, "fa")
        XCTAssertEqual(recorder.sessions[0].courseVersion, 3)
        XCTAssertEqual(recorder.sessions[0].items.count, 2)
        XCTAssertEqual(session.phase, .ended(.queued(completed: true)))
        XCTAssertEqual(session.stats?.correct, 2)
        XCTAssertEqual(session.stats?.total, 2)
    }

    func testPracticeSubmitsNothing() async throws {
        let recorder = Recorder()
        let session = makeSession(practice: true, recorder: recorder)
        session.setTileAnswer("a")
        session.check()
        session.continueOn()
        session.setTyped("b")
        session.check()
        session.continueOn()
        try await waitUntilEnded(session)
        XCTAssertEqual(recorder.sessions.count, 0)
        XCTAssertEqual(session.phase, .ended(.practice))
    }

    func testPracticeAgainDoesNotCountAndTryAgainDoes() async throws {
        let session = makeSession()
        session.setTileAnswer("a")
        session.check()
        session.continueOn()
        session.setTyped("b")
        session.check()
        session.continueOn()
        try await waitUntilEnded(session)
        session.practiceAgain()
        XCTAssertEqual(session.phase, .active)
        XCTAssertEqual(session.state.queue.count, 2)
        XCTAssertTrue(session.state.practice)
        session.tryAgain()
        XCTAssertFalse(session.state.practice)
        XCTAssertEqual(session.state.completedCount, 0)
    }

    func testSubmitFailureEndsRejectedWithAMessage() async throws {
        let setup = LessonSetup(courseCode: "fa", courseVersion: 1, instances: [instance(0, .wordBank, answer: "a")])
        let grader: Grader? = ScriptedGrader()
        let deps = LessonDependencies(grader: grader, gradingOnDevice: true, submit: { _ in throw Boom() })
        let session = LessonSession(setup: setup, dependencies: deps)
        session.setTileAnswer("a")
        session.check()
        session.continueOn()
        try await waitUntilEnded(session)
        if case .ended(.rejected(let partial, let reason)) = session.phase {
            XCTAssertFalse(partial)
            XCTAssertNotNil(reason)
        } else {
            XCTFail("expected rejected, got \(session.phase)")
        }
    }

    func testPrefsChangeIsSavedAndRebuildsTheKeyboard() {
        var saved: [LocalPrefs] = []
        let setup = LessonSetup(courseCode: "fa", courseVersion: 1, instances: [instance(0, .typeIn, answer: "b")])
        let deps = LessonDependencies(submit: { _ in .queued }, savePrefs: { saved.append($0) })
        let session = LessonSession(setup: setup, dependencies: deps)
        XCTAssertNotNil(session.keyboard)
        XCTAssertTrue(session.inAppKeyboard)
        session.updatePrefs { $0.deviceInputEnabled = true }
        XCTAssertFalse(session.inAppKeyboard)
        XCTAssertEqual(saved.count, 1)
        session.updatePrefs { $0.deviceInputEnabled = true }
        XCTAssertEqual(saved.count, 1, "no change, no save")
    }

    func testScriptModeChangeIsReported() {
        var modes: [ScriptMode] = []
        let setup = LessonSetup(courseCode: "fa", courseVersion: 1, instances: [instance(0, .wordBank, answer: "a")])
        let deps = LessonDependencies(submit: { _ in .queued }, saveScriptMode: { modes.append($0) })
        let session = LessonSession(setup: setup, dependencies: deps)
        session.setScriptMode(.both)
        session.setScriptMode(.both)
        XCTAssertEqual(modes, [.both])
        XCTAssertEqual(session.textLook.settings.display, .both)
    }

    private func waitUntilEnded(_ session: LessonSession) async throws {
        for _ in 0..<200 {
            if case .ended = session.phase { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("lesson never ended")
    }
}
