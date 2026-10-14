import XCTest
import QModel
import QDomain
@testable import QFeatures

private final class FakeGrader: Grader {
    var verdicts: [String]
    var requests: [GraderRequest] = []
    var erroring = false
    init(_ verdicts: [String]) { self.verdicts = verdicts }

    func gradeEnvelope(_ request: GraderRequest) -> GraderResponse {
        requests.append(request)
        if erroring { return GraderResponse(verdict: nil, error: "boom") }
        let v = verdicts.isEmpty ? "Correct" : verdicts.removeFirst()
        return GraderResponse(verdict: v, matchedAnswer: request.acceptedAnswers.first, correct: v == "Correct", acceptedWithCorrection: v == "AcceptedWithCorrection", xp: 0)
    }

    func xp(verdict: String, attempt: Int, usedHint: Bool, retype: Bool, retypeNumber: Int?) -> Int { 0 }
}

final class LessonEngineTests: XCTestCase {
    private func exercise(_ answer: String) -> ExerciseArtifact {
        ExerciseArtifact(type: .typeIn, scriptMode: .native, prompt: "p", answer: [answer], tags: [answer])
    }

    private func engine(_ answers: [String], grader: Grader?) -> LessonEngine {
        let skill = SkillArtifact(id: "s", title: "S", exercises: answers.map { exercise($0) })
        let instances = buildInstances(skills: [(ref: SkillRef(unitKey: "u", skillKey: "s"), skill: skill)], cards: [:])
        return LessonEngine(state: LessonState(queue: instances), courseCode: "fa", grader: grader)
    }

    private func keys(_ e: LessonEngine) -> [String] { e.state.queue.map { $0.exercise.answer[0] } }

    func testBuildsOneInstancePerExerciseInOrder() {
        let e = engine(["a", "b", "c"], grader: nil)
        XCTAssertEqual(keys(e), ["a", "b", "c"])
        XCTAssertEqual(e.state.queue[1].key, "u/s/1")
        XCTAssertEqual(e.state.totalCount, 3)
    }

    func testCorrectMovesOnAndScoresTen() {
        var e = engine(["a", "b"], grader: FakeGrader(["Correct"]))
        let outcome = e.submit("a")
        XCTAssertEqual(outcome?.xpGained, 10)
        XCTAssertEqual(keys(e), ["b"])
        XCTAssertEqual(e.state.firstTryCorrect, 1)
        XCTAssertEqual(e.state.firstTryPoints, 1)
    }

    func testWrongAnswerComesBackThreeLaterAndRecorded() {
        var e = engine(["a", "b", "c", "d", "e"], grader: FakeGrader(["Incorrect"]))
        let outcome = e.submit("x")
        XCTAssertEqual(outcome?.requeued, true)
        XCTAssertEqual(keys(e), ["b", "c", "d", "a", "e"])
        XCTAssertEqual(e.state.queue[3].attempt, 1)
        XCTAssertEqual(e.state.items.count, 1)
        XCTAssertEqual(e.state.items[0].item.attempt, 1)
        XCTAssertEqual(e.state.firstTryPoints, 0)
        XCTAssertEqual(e.state.xp, 0)
    }

    func testNearTheEndARetryGoesLast() {
        var e = engine(["a", "b"], grader: FakeGrader(["Incorrect"]))
        e.submit("x")
        XCTAssertEqual(keys(e), ["b", "a"])
    }

    func testSecondWrongAttemptIsNotRequeued() {
        var e = engine(["a"], grader: FakeGrader(["Incorrect", "Incorrect"]))
        e.submit("x")
        let second = e.submit("y")
        XCTAssertEqual(second?.requeued, false)
        XCTAssertTrue(e.state.finished)
        XCTAssertEqual(e.state.items.map { $0.item.attempt }, [1, 2])
    }

    func testRetryCorrectEarnsFiveAndNoFirstTryCredit() {
        var e = engine(["a"], grader: FakeGrader(["Incorrect", "Correct"]))
        e.submit("x")
        let second = e.submit("a")
        XCTAssertEqual(second?.xpGained, 5)
        XCTAssertEqual(e.state.firstTryCorrect, 0)
    }

    func testCorrectedAnswerIsHalfPointAndSevenXpHintHalves() {
        var e = engine(["a", "b"], grader: FakeGrader(["AcceptedWithCorrection", "Correct"]))
        XCTAssertEqual(e.submit("a")?.xpGained, 7)
        XCTAssertEqual(e.submit("b", usedHint: true)?.xpGained, 5)
        XCTAssertEqual(e.state.firstTryPoints, 1.5)
        XCTAssertEqual(e.state.score, 0.75)
    }

    func testDeferredGradingWhenNoGrader() {
        var e = engine(["a", "b"], grader: nil)
        let outcome = e.submit("a")
        XCTAssertEqual(outcome?.feedback.verdict, .pending)
        XCTAssertEqual(outcome?.xpGained, 0)
        XCTAssertEqual(outcome?.requeued, false)
        XCTAssertEqual(e.state.uncheckedFirstTries, 1)
        XCTAssertEqual(keys(e), ["b"])
    }

    func testGraderErrorAndGradingOffAreDeferred() {
        let fake = FakeGrader([])
        fake.erroring = true
        var e = engine(["a"], grader: fake)
        XCTAssertEqual(e.submit("a")?.feedback.verdict, .pending)

        let ok = FakeGrader([])
        var off = engine(["a"], grader: ok)
        off.gradingOnDevice = false
        XCTAssertEqual(off.submit("a")?.feedback.verdict, .pending)
        XCTAssertTrue(ok.requests.isEmpty)
    }

    func testGraderReceivesGraderSpelling() {
        let fake = FakeGrader(["Correct"])
        var e = engine(["a"], grader: fake)
        e.submit("a")
        XCTAssertEqual(fake.requests.first?.exerciseType, "TypeIn")
        XCTAssertEqual(fake.requests.first?.scriptMode, "Native")
        XCTAssertEqual(fake.requests.first?.acceptedAnswers, ["a"])
    }

    func testCompletionPayloadAndPassMark() {
        var e = engine(["a", "b", "c", "d"], grader: FakeGrader(["Correct", "Correct", "Correct", "Incorrect", "Correct"]))
        // d is missed once, requeued, then answered again; first tries: 3 correct of 4.
        for text in ["a", "b", "c", "x", "d"] { e.submit(text) }
        XCTAssertTrue(e.state.finished)
        let when = Date(timeIntervalSince1970: 1_000)
        var n = 0
        guard let done = e.completion(courseCode: "fa", courseVersion: 7, occurredAt: when, exerciseCountBySkill: ["s": 4], newId: { n += 1; return "id\(n)" }) else { return XCTFail("finished lesson completes") }
        XCTAssertEqual(done.sessions.count, 1)
        let s = done.sessions[0]
        XCTAssertEqual(s.submissionId, "id1")
        XCTAssertEqual(s.courseCode, "fa")
        XCTAssertEqual(s.courseVersion, 7)
        XCTAssertEqual(s.unitKey, "u")
        XCTAssertEqual(s.skillKey, "s")
        XCTAssertEqual(s.occurredAt, when)
        XCTAssertTrue(s.completed)
        XCTAssertEqual(s.items.count, 5)
        XCTAssertEqual(done.locallyCompleted, true)
        XCTAssertEqual(done.score, 0.75)
    }

    func testBelowPassMarkAndUncheckedLeaveCompletion() {
        var low = engine(["a", "b"], grader: FakeGrader(["Incorrect", "Incorrect", "Incorrect", "Incorrect"]))
        for text in ["x", "y", "x", "y"] { low.submit(text) }
        XCTAssertEqual(low.state.localLessonCompleted(exerciseCountBySkill: ["s": 2]), false)

        var deferred = engine(["a"], grader: nil)
        deferred.submit("a")
        XCTAssertNil(deferred.state.localLessonCompleted(exerciseCountBySkill: ["s": 1]))
    }

    func testPracticeSubmitsNothing() {
        let skill = SkillArtifact(id: "s", title: "S", exercises: [exercise("a")])
        let instances = buildInstances(skills: [(ref: SkillRef(unitKey: nil, skillKey: "s"), skill: skill)], cards: [:])
        var e = LessonEngine(state: LessonState(queue: instances, practice: true), courseCode: "fa", grader: FakeGrader(["Correct"]))
        e.submit("a")
        let done = e.completion(courseCode: "fa", courseVersion: 1, occurredAt: Date(), exerciseCountBySkill: ["s": 1])
        XCTAssertTrue(done?.sessions.isEmpty ?? false)
        XCTAssertNil(done?.locallyCompleted)
    }

    func testRestartAfterPracticeAgainStillCountsOnRetake() {
        var e = engine(["a"], grader: FakeGrader(["Correct", "Correct", "Correct"]))
        let again = e.state.queue
        e.submit("a")
        e.restart(again, practice: true)
        XCTAssertTrue(e.state.practice)
        e.submit("a")
        e.restart(again, practice: false)
        XCTAssertFalse(e.state.practice)
        e.submit("a")
        XCTAssertEqual(e.completion(courseCode: "fa", courseVersion: 1, occurredAt: Date(), exerciseCountBySkill: ["s": 1])?.sessions.count, 1)
    }

    func testRestartOfPracticeSessionStaysPractice() {
        let skill = SkillArtifact(id: "s", title: "S", exercises: [exercise("a")])
        let instances = buildInstances(skills: [(ref: SkillRef(unitKey: nil, skillKey: "s"), skill: skill)], cards: [:])
        var e = LessonEngine(state: LessonState(queue: instances, practice: true), courseCode: "fa", grader: nil)
        e.restart(instances, practice: false)
        XCTAssertTrue(e.state.practice)
    }

    func testRestoredPracticeAgainRoundKeepsRetakeCounted() throws {
        var e = engine(["a"], grader: FakeGrader(["Correct", "Correct", "Correct"]))
        let again = e.state.queue
        e.submit("a")
        e.restart(again, practice: true)
        // process death mid practice-again round
        let back = try JSONDecoder().decode(LessonState.self, from: JSONEncoder().encode(e.state))
        XCTAssertTrue(back.practice)
        var restored = LessonEngine(state: back, courseCode: "fa", grader: FakeGrader(["Correct"]))
        restored.restart(again, practice: false)
        XCTAssertFalse(restored.state.practice)
        restored.submit("a")
        XCTAssertEqual(restored.completion(courseCode: "fa", courseVersion: 1, occurredAt: Date(), exerciseCountBySkill: ["s": 1])?.sessions.count, 1)
        // an old saved state without the field falls back to its practice flag
        var legacy = LessonEngine(state: LessonState(queue: again, practice: true), courseCode: "fa", grader: nil, sessionPractice: nil)
        legacy.restart(again, practice: false)
        XCTAssertTrue(legacy.state.practice)
        // an explicit session flag wins over the state's round flag
        var planned = LessonEngine(state: LessonState(queue: again, practice: true), courseCode: "fa", grader: nil, sessionPractice: false)
        planned.restart(again, practice: false)
        XCTAssertFalse(planned.state.practice)
    }

    func testCompletionIdsAreStableAcrossCallsAndRestoredState() throws {
        var e = engine(["a", "b"], grader: FakeGrader(["Correct", "Correct"]))
        e.submit("a")
        e.submit("b")
        var n = 0
        let first = e.completion(courseCode: "fa", courseVersion: 1, occurredAt: Date(), exerciseCountBySkill: ["s": 2], newId: { n += 1; return "id\(n)" })
        let second = e.completion(courseCode: "fa", courseVersion: 1, occurredAt: Date(), exerciseCountBySkill: ["s": 2], newId: { n += 1; return "id\(n)" })
        XCTAssertEqual(first?.sessions.map { $0.submissionId }, ["id1"])
        XCTAssertEqual(second?.sessions.map { $0.submissionId }, ["id1"])
        let back = try JSONDecoder().decode(LessonState.self, from: JSONEncoder().encode(e.state))
        var restored = LessonEngine(state: back, courseCode: "fa", grader: nil)
        let third = restored.completion(courseCode: "fa", courseVersion: 1, occurredAt: Date(), exerciseCountBySkill: ["s": 2], newId: { n += 1; return "id\(n)" })
        XCTAssertEqual(third?.sessions.map { $0.submissionId }, ["id1"])
    }

    func testCompletionRefusedUntilFinished() {
        var e = engine(["a", "b"], grader: FakeGrader(["Correct"]))
        e.submit("a")
        XCTAssertNil(e.completion(courseCode: "fa", courseVersion: 1, occurredAt: Date(), exerciseCountBySkill: ["s": 2]))
        XCTAssertNil(e.state.submissionIds)
    }

    func testDueTagFilterAndStateRoundTrip() throws {
        let skill = SkillArtifact(id: "s", title: "S", exercises: [exercise("a"), exercise("b")])
        let due = buildInstances(skills: [(ref: SkillRef(unitKey: "u", skillKey: "s"), skill: skill)], cards: [:], dueTags: ["b"])
        XCTAssertEqual(due.map { $0.exercise.answer[0] }, ["b"])

        var e = engine(["a", "b"], grader: FakeGrader(["Incorrect"]))
        e.submit("x")
        let data = try JSONEncoder().encode(e.state)
        let back = try JSONDecoder().decode(LessonState.self, from: data)
        XCTAssertEqual(back, e.state)
    }

    func testDropFromQueueForStory() {
        var e = engine(["a", "b"], grader: FakeGrader(["Incorrect"]))
        e.submit("x")
        e.dropFromQueue(key: "u/s/0")
        XCTAssertEqual(keys(e), ["b"])
    }

    func testXpForAnswerRounding() {
        XCTAssertEqual(xpForAnswer(.correct, attempt: 1, usedHint: true), 5)
        XCTAssertEqual(xpForAnswer(.acceptedWithCorrection, attempt: 1, usedHint: true), 4)
        XCTAssertEqual(xpForAnswer(.correct, attempt: 2, usedHint: true), 3)
        XCTAssertEqual(xpForAnswer(.incorrect, attempt: 1, usedHint: false), 0)
    }
}
