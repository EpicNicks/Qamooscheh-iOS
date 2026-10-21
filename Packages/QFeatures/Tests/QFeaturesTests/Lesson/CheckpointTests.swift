import XCTest
import QModel
import QDomain
import QData
@testable import QFeatures

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [T] = []
    var values: [T] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func add(_ value: T) {
        lock.lock()
        stored.append(value)
        lock.unlock()
    }
}

private func bankExercise(_ tag: String, tags: [String]? = nil) -> ExerciseArtifact {
    ExerciseArtifact(type: .wordBank, scriptMode: .native, prompt: "p-\(tag)", tiles: ["a"], answer: ["a"], tags: tags ?? [tag])
}

private func plan(requiresTest: Bool = true, skills: [CheckpointSkillPlan]) -> CheckpointPlanResponse {
    CheckpointPlanResponse(
        courseVersion: 3, targetUnitKey: "u2", targetSkillKey: "t", skills: skills,
        skippedLessons: [], skippedCount: 3, alreadyCompletedCount: 1, requiresTest: requiresTest
    )
}

final class CheckpointLogicTests: XCTestCase {
    func testSkipSummaryFollowsAndroid() {
        XCTAssertNil(CheckpointLogic.skipSummary(skippedCount: 0, alreadyCompletedCount: 0))
        XCTAssertEqual(CheckpointLogic.skipSummary(skippedCount: 1, alreadyCompletedCount: 0), "Skipping 1 lesson.")
        XCTAssertEqual(CheckpointLogic.skipSummary(skippedCount: 3, alreadyCompletedCount: 0), "Skipping 3 lessons.")
        XCTAssertEqual(
            CheckpointLogic.skipSummary(skippedCount: 3, alreadyCompletedCount: 1),
            "Skipping 3 lessons \u{2014} 1 already done via deep dive."
        )
    }

    func testInstancesKeepOnlyThePlannedOrdinalsPerSkill() {
        let skillA = SkillArtifact(id: "a", title: "A", exercises: [bankExercise("a0"), bankExercise("a1"), bankExercise("a2")])
        let skillB = SkillArtifact(id: "b", title: "B", exercises: [bankExercise("b0"), bankExercise("b1")])
        let response = plan(skills: [
            CheckpointSkillPlan(unitKey: "u1", skillKey: "a", exerciseOrdinals: [0, 2]),
            CheckpointSkillPlan(unitKey: "u1", skillKey: "b", exerciseOrdinals: [1]),
        ])
        let found = CheckpointLogic.instances(
            plan: response,
            skills: [(SkillRef(unitKey: "u1", skillKey: "a"), skillA), (SkillRef(unitKey: "u1", skillKey: "b"), skillB)],
            cards: [:]
        )
        XCTAssertEqual(found.map { $0.key }, ["u1/a/0", "u1/a/2", "u1/b/1"])
    }

    func testSetupCarriesThePlanAndSummary() {
        let skillA = SkillArtifact(id: "a", title: "A", exercises: [bankExercise("a0")])
        let response = plan(skills: [CheckpointSkillPlan(unitKey: "u1", skillKey: "a", exerciseOrdinals: [0])])
        let setup = CheckpointLogic.setup(courseCode: "fa", plan: response, skills: [(SkillRef(unitKey: "u1", skillKey: "a"), skillA)], cards: [:])
        XCTAssertTrue(setup.isCheckpoint)
        XCTAssertEqual(setup.courseVersion, 3)
        XCTAssertEqual(setup.checkpoint?.targetSkillKey, "t")
        XCTAssertEqual(setup.checkpointSummary, "Skipping 3 lessons \u{2014} 1 already done via deep dive.")
    }

    func testNothingSkippedStillMakesACheckpoint() {
        let response = CheckpointPlanResponse(
            courseVersion: 1, targetUnitKey: "u", targetSkillKey: "s", skills: [], skippedLessons: [],
            skippedCount: 0, alreadyCompletedCount: 0, requiresTest: true
        )
        let setup = CheckpointLogic.setup(courseCode: "fa", plan: response, skills: [], cards: [:])
        XCTAssertNil(setup.checkpointSummary)
        XCTAssertTrue(setup.isCheckpoint)
    }

    func testRequestGroupsBySkillAndEmitsAnItemPerTag() {
        let info = CheckpointPlanInfo(courseVersion: 3, targetUnitKey: "u2", targetSkillKey: "t", skippedCount: 3, alreadyCompletedCount: 0, requiresTest: true)
        let first = ExerciseInstance(key: "u1/a/0", unitKey: "u1", skillKey: "a", ordinal: 0, exercise: bankExercise("x", tags: ["x", "y"]), renderType: .wordBank)
        let second = ExerciseInstance(key: "u1/b/1", unitKey: "u1", skillKey: "b", ordinal: 1, exercise: bankExercise("z"), renderType: .typeIn)
        let third = ExerciseInstance(key: "u1/a/2", unitKey: "u1", skillKey: "a", ordinal: 2, exercise: bankExercise("w"), renderType: .wordBank)
        let unanswered = ExerciseInstance(key: "u1/b/3", unitKey: "u1", skillKey: "b", ordinal: 3, exercise: bankExercise("v"), renderType: .wordBank)
        let when = Date(timeIntervalSince1970: 1_000)
        let request = CheckpointLogic.request(
            info: info, instances: [first, second, third, unanswered],
            answers: ["u1/a/0": "one", "u1/b/1": "two", "u1/a/2": "three"],
            submissionId: "id-9", occurredAt: when
        )
        XCTAssertEqual(request.submissionId, "id-9")
        XCTAssertEqual(request.targetUnitKey, "u2")
        XCTAssertEqual(request.targetSkillKey, "t")
        XCTAssertEqual(request.courseVersion, 3)
        XCTAssertEqual(request.occurredAt, when)
        XCTAssertEqual(request.skills.map { $0.skillKey }, ["a", "b"])
        let a = request.skills[0].items
        XCTAssertEqual(a.map { $0.lexemeTag }, ["x", "y", "w"])
        XCTAssertEqual(a.map { $0.submittedText }, ["one", "one", "three"])
        XCTAssertEqual(a.map { $0.exerciseOrdinal }, [0, 0, 2])
        XCTAssertTrue(a.allSatisfy { $0.attempt == 1 && !$0.usedHint && $0.latencyMs == nil })
        let b = request.skills[1].items
        XCTAssertEqual(b.count, 1)
        XCTAssertEqual(b[0].exerciseType, .typeIn)
    }

    func testResultCopy() {
        let passed = CheckpointLogic.resultCopy(CheckpointOutcome(passed: true, score: 0.854, applied: true))
        XCTAssertEqual(passed.title, "Checkpoint passed!")
        XCTAssertEqual(passed.body, "Score: 85%")
        let failed = CheckpointLogic.resultCopy(CheckpointOutcome(passed: false, score: 0.4, applied: false))
        XCTAssertEqual(failed.title, "Not quite there yet")
        XCTAssertTrue(failed.body.contains("Score: 40%"))
        XCTAssertTrue(failed.body.contains("didn't move your position"))
    }

    func testReadyCopyAndLabels() {
        XCTAssertEqual(CheckpointLogic.readyCopy(noTest: false).title, "Ready to submit")
        XCTAssertEqual(CheckpointLogic.readyCopy(noTest: true).title, "No test needed")
        XCTAssertEqual(CheckpointLogic.primaryLabel(noTest: false, submitting: false), "Submit checkpoint")
        XCTAssertEqual(CheckpointLogic.primaryLabel(noTest: true, submitting: false), "Continue")
        XCTAssertEqual(CheckpointLogic.primaryLabel(noTest: true, submitting: true), CheckpointLogic.submittingLabel)
        XCTAssertEqual(CheckpointLogic.secondaryLabel(noTest: false), "Exit without submitting")
        XCTAssertEqual(CheckpointLogic.secondaryLabel(noTest: true), "Cancel")
    }
}

private final class AlwaysWrong: Grader {
    func gradeEnvelope(_ request: GraderRequest) -> GraderResponse {
        GraderResponse(verdict: "Incorrect", matchedAnswer: nil, correct: false, xp: 0)
    }

    func xp(verdict: String, attempt: Int, usedHint: Bool, retype: Bool, retypeNumber: Int?) -> Int { 0 }
}

final class CheckpointSessionTests: XCTestCase {
    private func setup(count: Int, requiresTest: Bool = true) -> LessonSetup {
        let instances = (0..<count).map { n in
            ExerciseInstance(key: "u/s/\(n)", unitKey: "u", skillKey: "s", ordinal: n, exercise: bankExercise("t\(n)"), renderType: .wordBank)
        }
        let info = CheckpointPlanInfo(courseVersion: 2, targetUnitKey: "u2", targetSkillKey: "t", skippedCount: 2, alreadyCompletedCount: 0, requiresTest: requiresTest)
        return LessonSetup(
            courseCode: "fa", courseVersion: 2, instances: instances,
            checkpointSummary: CheckpointLogic.skipSummary(skippedCount: 2, alreadyCompletedCount: 0), checkpoint: info
        )
    }

    private func response(passed: Bool) -> CheckpointSubmitResponse {
        CheckpointSubmitResponse(passed: passed, score: 0.9, cards: [], skippedLessons: [], skippedCount: 2, alreadyCompletedCount: 0, requiresTest: true, applied: true)
    }

    private func make(count: Int, requiresTest: Bool = true, send: CheckpointSubmitFunction?, submits: Box<String> = Box<String>(), now: @escaping () -> Date = { Date() }, checkpointDraft: CheckpointDraftStore = .none) -> LessonSession {
        let deps = LessonDependencies(
            grader: AlwaysWrong(), gradingOnDevice: true,
            submit: { _ in
                submits.add("session submitted")
                return .queued
            },
            enqueue: { _ in submits.add("session enqueued") },
            now: now,
            submitCheckpoint: send,
            newSubmissionId: { "fixed-id" },
            checkpointDraft: checkpointDraft
        )
        return LessonSession(setup: setup(count: count, requiresTest: requiresTest), dependencies: deps)
    }

    private func answer(_ session: LessonSession) {
        session.setTileAnswer("a")
        session.check()
    }

    func testAnswersAreNotMarkedAndMoveStraightOn() {
        let session = make(count: 2, send: nil)
        answer(session)
        XCTAssertNil(session.review)
        XCTAssertEqual(session.phase, .active)
        XCTAssertEqual(session.state.completedCount, 1)
        XCTAssertTrue(session.state.items.isEmpty)
        answer(session)
        XCTAssertEqual(session.phase, .checkpointReady)
    }

    func testWrongAnswersAreNeverRequeued() {
        let session = make(count: 1, send: nil)
        answer(session)
        XCTAssertEqual(session.phase, .checkpointReady)
        XCTAssertEqual(session.state.queue.count, 0)
    }

    func testNothingToAskGoesStraightToReady() {
        let session = make(count: 0, requiresTest: false, send: nil)
        XCTAssertEqual(session.phase, .checkpointReady)
        XCTAssertTrue(session.checkpointNeedsNoTest)
    }

    func testSubmitSendsEveryAnswerOnceAndShowsTheVerdict() async {
        let sent = Box<SubmitCheckpointRequest>()
        let session = make(count: 2, send: { request in
            sent.add(request)
            return CheckpointSubmitResponse(passed: true, score: 0.9, cards: [], skippedLessons: [], skippedCount: 2, alreadyCompletedCount: 0, requiresTest: true, applied: true)
        })
        answer(session)
        answer(session)
        session.submitCheckpoint()
        XCTAssertEqual(session.phase, .checkpointSubmitting)
        await session.waitForDelivery()
        XCTAssertEqual(session.phase, .checkpointDone(CheckpointOutcome(passed: true, score: 0.9, applied: true)))
        let requests = sent.values
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].submissionId, "fixed-id")
        XCTAssertEqual(requests[0].courseVersion, 2)
        XCTAssertEqual(requests[0].skills.first?.items.count, 2)
    }

    func testFailedSendKeepsTheAnswersAndRetriesWithTheSameId() async {
        let attempts = Box<String>()
        let session = make(count: 1, send: { request in
            attempts.add(request.submissionId)
            if attempts.values.count == 1 { throw URLError(.notConnectedToInternet) }
            return CheckpointSubmitResponse(passed: false, score: 0.2, cards: [], skippedLessons: [], skippedCount: 2, alreadyCompletedCount: 0, requiresTest: true, applied: true)
        })
        answer(session)
        session.submitCheckpoint()
        await session.waitForDelivery()
        XCTAssertEqual(session.phase, .checkpointReady)
        XCTAssertEqual(session.checkpointError, CheckpointLogic.submitFailure)
        session.submitCheckpoint()
        await session.waitForDelivery()
        XCTAssertEqual(session.phase, .checkpointDone(CheckpointOutcome(passed: false, score: 0.2, applied: true)))
        XCTAssertNil(session.checkpointError)
        XCTAssertEqual(attempts.values, ["fixed-id", "fixed-id"])
    }

    func testRetryReusesTheOriginalOccurredAt() async {
        let stamps = Box<String>()
        let clock = Box<String>()
        let session = make(count: 1, send: { request in
            stamps.add(String(request.occurredAt.timeIntervalSince1970))
            if stamps.values.count == 1 { throw URLError(.notConnectedToInternet) }
            return CheckpointSubmitResponse(passed: true, score: 1, cards: [], skippedLessons: [], skippedCount: 2, alreadyCompletedCount: 0, requiresTest: true, applied: true)
        }, now: {
            clock.add("tick")
            return Date(timeIntervalSince1970: 1_000 * Double(clock.values.count))
        })
        answer(session)
        session.submitCheckpoint()
        await session.waitForDelivery()
        session.submitCheckpoint()
        await session.waitForDelivery()
        XCTAssertEqual(stamps.values.count, 2)
        XCTAssertEqual(stamps.values[0], stamps.values[1])
    }

    func testKilledAtReadyToSubmitRestoresAnswersIdAndTime() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = CheckpointDraftStore.file(directory: dir, key: "u|fa|-|t|counted|checkpoint|answers")
        let first = make(count: 2, send: nil, now: { Date(timeIntervalSince1970: 5_000) }, checkpointDraft: store)
        answer(first)
        XCTAssertNil(store.load())
        answer(first)
        XCTAssertEqual(first.phase, .checkpointReady)
        XCTAssertEqual(store.load()?.answers.count, 2)

        // The app was killed here. A new session finds the draft.
        let sent = Box<String>()
        let second = make(count: 2, send: { request in
            sent.add("\(request.submissionId)@\(request.occurredAt.timeIntervalSince1970)")
            return CheckpointSubmitResponse(passed: true, score: 1, cards: [], skippedLessons: [], skippedCount: 2, alreadyCompletedCount: 0, requiresTest: true, applied: true)
        }, now: { Date(timeIntervalSince1970: 9_999) }, checkpointDraft: store)
        XCTAssertEqual(second.phase, .checkpointReady)
        second.submitCheckpoint()
        await second.waitForDelivery()
        XCTAssertEqual(sent.values, ["fixed-id@5000.0"])
        XCTAssertNil(store.load())
    }

    func testNoSubmitFunctionIsAFailureNotACrash() async {
        let session = make(count: 1, send: nil)
        answer(session)
        session.submitCheckpoint()
        await session.waitForDelivery()
        XCTAssertEqual(session.phase, .checkpointReady)
        XCTAssertNotNil(session.checkpointError)
    }

    func testACheckpointNeverGoesThroughTheSessionQueue() async {
        let log = Box<String>()
        let session = make(count: 1, send: { _ in
            CheckpointSubmitResponse(passed: true, score: 1, cards: [], skippedLessons: [], skippedCount: 2, alreadyCompletedCount: 0, requiresTest: true, applied: true)
        }, submits: log)
        answer(session)
        session.submitCheckpoint()
        await session.waitForDelivery()
        XCTAssertTrue(log.values.isEmpty)
    }

    func testSubmitIsIgnoredBeforeTheLastAnswer() {
        let session = make(count: 2, send: nil)
        answer(session)
        session.submitCheckpoint()
        XCTAssertEqual(session.phase, .active)
    }
}

final class CheckpointEnvironmentTests: XCTestCase {
    private struct Loader: LessonSetupLoading {
        var result: LessonSetup?
        func setup(for route: LessonRoute) async throws -> LessonSetup? { result }
        func serverPrefs() async -> LessonServerPrefs { LessonServerPrefs() }
        func saveScriptMode(_ mode: ScriptMode) async {}
    }

    private func environment(_ setup: LessonSetup, send: CheckpointUserSubmitFunction?) -> LessonEnvironment {
        let defaults = UserDefaults(suiteName: "checkpoint-env-test-" + UUID().uuidString) ?? UserDefaults.standard
        return LessonEnvironment(
            loader: Loader(result: setup), userId: { "u7" }, prefsStore: LocalPrefsStore(defaults: defaults),
            submit: { _, _ in .queued }, submitCheckpoint: send
        )
    }

    func testRouteFactoryMarksACheckpoint() {
        let route = LessonRoute.forCheckpoint(unitKey: "u2", skillKey: "t")
        XCTAssertTrue(route.checkpoint)
        XCTAssertFalse(LessonRoute(skillKey: "s").checkpoint)
    }

    func testEmptyCheckpointThatNeedsNoTestStillStarts() async throws {
        let info = CheckpointPlanInfo(courseVersion: 1, targetUnitKey: "u", targetSkillKey: "s", skippedCount: 1, alreadyCompletedCount: 1, requiresTest: false)
        let empty = LessonSetup(courseCode: "fa", courseVersion: 1, instances: [], checkpoint: info)
        let made = try await environment(empty, send: nil).makeSession(for: LessonRoute.forCheckpoint(unitKey: "u", skillKey: "s"))
        XCTAssertEqual(made?.phase, .checkpointReady)
    }

    func testEmptyCheckpointThatNeedsATestIsNothingToPlay() async throws {
        let info = CheckpointPlanInfo(courseVersion: 1, targetUnitKey: "u", targetSkillKey: "s", skippedCount: 1, alreadyCompletedCount: 0, requiresTest: true)
        let empty = LessonSetup(courseCode: "fa", courseVersion: 1, instances: [], checkpoint: info)
        let made = try await environment(empty, send: nil).makeSession(for: LessonRoute.forCheckpoint(unitKey: "u", skillKey: "s"))
        XCTAssertNil(made)
    }

    func testSubmitIsBoundToTheUserTheCheckpointStartedFor() async throws {
        let users = Box<String>()
        let info = CheckpointPlanInfo(courseVersion: 1, targetUnitKey: "u", targetSkillKey: "s", skippedCount: 1, alreadyCompletedCount: 1, requiresTest: false)
        let empty = LessonSetup(courseCode: "fa", courseVersion: 1, instances: [], checkpoint: info)
        let env = environment(empty, send: { user, _ in
            users.add(user)
            return CheckpointSubmitResponse(passed: true, score: 1, cards: [], skippedLessons: [], skippedCount: 1, alreadyCompletedCount: 1, requiresTest: false, applied: true)
        })
        let made = try await env.makeSession(for: LessonRoute.forCheckpoint(unitKey: "u", skillKey: "s"))
        let session = try XCTUnwrap(made)
        session.submitCheckpoint()
        await session.waitForDelivery()
        XCTAssertEqual(users.values, ["u7"])
        XCTAssertEqual(session.phase, .checkpointDone(CheckpointOutcome(passed: true, score: 1, applied: true)))
    }
}
