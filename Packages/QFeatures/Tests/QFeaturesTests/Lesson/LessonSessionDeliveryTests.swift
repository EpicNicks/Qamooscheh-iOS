import XCTest
import QModel
import QDomain
import QData
@testable import QFeatures

private final class Probe: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    var log: [String] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func add(_ line: String) {
        lock.lock()
        stored.append(line)
        lock.unlock()
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return n
    }

    func bump() {
        lock.lock()
        n += 1
        lock.unlock()
    }
}

private struct Boom: Error {}

private final class AlwaysRight: Grader {
    func gradeEnvelope(_ request: GraderRequest) -> GraderResponse {
        GraderResponse(verdict: "Correct", matchedAnswer: request.submitted, correct: true, xp: 0)
    }

    func xp(verdict: String, attempt: Int, usedHint: Bool, retype: Bool, retypeNumber: Int?) -> Int { 0 }
}

final class LessonSessionDeliveryTests: XCTestCase {
    private func instance(_ ordinal: Int) -> ExerciseInstance {
        let exercise = ExerciseArtifact(type: .wordBank, scriptMode: .native, prompt: "p\(ordinal)", tiles: ["a"], answer: ["a"], tags: ["t\(ordinal)"])
        return ExerciseInstance(key: "u/s/\(ordinal)", unitKey: "u", skillKey: "s", ordinal: ordinal, exercise: exercise, renderType: .wordBank)
    }

    private func setup(count: Int = 2, practice: Bool = false) -> LessonSetup {
        LessonSetup(courseCode: "fa", courseVersion: 1, instances: (0..<count).map { instance($0) }, exerciseCountBySkill: ["s": count], practice: practice)
    }

    private func make(
        count: Int = 2,
        practice: Bool = false,
        draft: LessonDraftStore = .none,
        practiceDraft: LessonDraftStore? = nil,
        enqueue: @escaping LessonEnqueueFunction = { _ in },
        submit: @escaping LessonSubmitFunction = { _ in .queued },
        counted: Counter = Counter()
    ) -> LessonSession {
        let deps = LessonDependencies(
            grader: AlwaysRight(), gradingOnDevice: true, submit: submit, enqueue: enqueue, draft: draft, practiceDraft: practiceDraft,
            onLessonCounted: { counted.bump() }
        )
        return LessonSession(setup: setup(count: count, practice: practice), dependencies: deps)
    }

    private func answerAll(_ session: LessonSession) {
        while session.phase == .active && session.instance != nil {
            session.setTileAnswer("a")
            session.check()
            session.continueOn()
        }
    }

    // MARK: A thrown submit is not a rejection

    func testThrownSubmitAfterEnqueueEndsQueuedAndOffersTryAgain() async {
        let session = make(submit: { _ in throw Boom() })
        answerAll(session)
        await session.waitForDelivery()
        XCTAssertEqual(session.phase, .ended(.queued(completed: true)))
        if case .ended(let end) = session.phase { XCTAssertTrue(offersTryAgain(end: end)) }
    }

    func testServerRefusalIsStillRejected() async {
        let session = make(submit: { _ in .rejected(reason: "no") })
        answerAll(session)
        await session.waitForDelivery()
        XCTAssertEqual(session.phase, .ended(.rejected(partial: false, reason: "no")))
    }

    // MARK: Write-ahead

    func testSessionIsEnqueuedBeforeItIsSubmittedAndBeforeTheLessonEnds() async {
        let probe = Probe()
        let session = make(
            enqueue: { _ in probe.add("enqueue") },
            submit: { _ in
                probe.add("submit")
                return .queued
            }
        )
        answerAll(session)
        XCTAssertEqual(session.phase, .saving)
        await session.waitForDelivery()
        XCTAssertEqual(probe.log, ["enqueue", "submit"])
        XCTAssertEqual(session.phase, .ended(.queued(completed: true)))
    }

    func testFinishedStateIsOnDiskBeforeDelivery() async {
        let draft = MemoryLessonDraft()
        let seen = Probe()
        let session = make(draft: draft.store, enqueue: { _ in
            seen.add(draft.state?.finished == true ? "draft-finished" : "no-draft")
        })
        answerAll(session)
        await session.waitForDelivery()
        XCTAssertEqual(seen.log, ["draft-finished"])
        XCTAssertNil(draft.state, "cleared once saved")
    }

    func testStorageFailureShowsSaveFailedKeepsDraftAndRetrySaves() async {
        let draft = MemoryLessonDraft()
        let healed = Counter()
        let session = make(
            draft: draft.store,
            enqueue: { _ in if healed.value == 0 { throw Boom() } },
            submit: { _ in
                if healed.value == 0 { throw Boom() }
                return .queued
            }
        )
        answerAll(session)
        await session.waitForDelivery()
        XCTAssertEqual(session.phase, .saveFailed)
        XCTAssertNotNil(draft.state)
        healed.bump()
        session.retrySave()
        XCTAssertEqual(session.phase, .saving)
        await session.waitForDelivery()
        XCTAssertEqual(session.phase, .ended(.queued(completed: true)))
        XCTAssertNil(draft.state)
    }

    func testDeliverTreatsEnqueueFailureAsFineWhenSubmitSucceeds() async {
        let one = SubmittedSession(
            submissionId: "a", courseCode: "fa", unitKey: "u", skillKey: "s", courseVersion: 1,
            occurredAt: Date(timeIntervalSince1970: 0), completed: true, items: []
        )
        let delivery = await LessonSession.deliver(sessions: [one], enqueue: { _ in throw Boom() }, submit: { _ in .queued })
        XCTAssertEqual(delivery, LessonSession.Delivery(results: [.queued], unsaved: false))
    }

    // MARK: Draft

    func testProgressIsSavedAfterEachStepAndRestoredByANewSession() {
        let draft = MemoryLessonDraft()
        let first = make(draft: draft.store)
        first.setTileAnswer("a")
        first.check()
        first.continueOn()
        XCTAssertEqual(draft.state?.completedCount, 1)
        let second = make(draft: draft.store)
        XCTAssertEqual(second.state.completedCount, 1)
        XCTAssertEqual(second.instance?.ordinal, 1)
        XCTAssertEqual(second.state.items.count, 1)
    }

    func testRestoredCountedRetakeStaysCounted() {
        let draft = MemoryLessonDraft()
        let first = make(draft: draft.store)
        first.practiceAgain()
        XCTAssertEqual(draft.state?.sessionPractice, false)
        XCTAssertEqual(draft.state?.practice, true)
        let second = make(draft: draft.store)
        XCTAssertTrue(second.state.practice)
        XCTAssertEqual(second.state.sessionPractice, false)
        second.tryAgain()
        XCTAssertFalse(second.state.practice)
    }

    func testMismatchedDraftIsDiscarded() {
        let stale = LessonState(queue: [instance(7)], totalCount: 1)
        let draft = MemoryLessonDraft(stale)
        let session = make(draft: draft.store)
        XCTAssertEqual(session.state.completedCount, 0)
        XCTAssertEqual(session.state.queue.count, 2)
        XCTAssertNil(draft.state)
    }

    func testRestoredFinishedDraftIsDeliveredAgain() async {
        let source = MemoryLessonDraft()
        let first = make(draft: source.store, submit: { _ in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return .queued
        })
        answerAll(first)
        XCTAssertEqual(first.phase, .saving)
        let saved = source.state
        XCTAssertEqual(saved?.finished, true)
        let sent = Probe()
        let second = make(draft: MemoryLessonDraft(saved).store, submit: { s in
            sent.add(s.submissionId)
            return .queued
        })
        XCTAssertEqual(second.phase, .saving)
        await second.waitForDelivery()
        XCTAssertEqual(sent.log.count, 1)
        XCTAssertEqual(sent.log.first, saved?.submissionIds?.values.first)
        XCTAssertEqual(second.phase, .ended(.queued(completed: true)))
    }

    func testFinishedDraftIsDeliveredEvenWhenTheSetupChanged() async {
        let source = MemoryLessonDraft()
        let first = make(draft: source.store, submit: { _ in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return .queued
        })
        answerAll(first)
        let saved = source.state
        XCTAssertEqual(saved?.finished, true)
        let draft = MemoryLessonDraft(saved)
        let sent = Probe()
        let second = make(count: 3, draft: draft.store, submit: { s in
            sent.add(s.submissionId)
            return .queued
        })
        await second.waitForDelivery()
        XCTAssertEqual(sent.log.count, 1)
        XCTAssertEqual(sent.log.first, saved?.submissionIds?.values.first)
        XCTAssertEqual(second.phase, .ended(.queued(completed: false)))
    }

    func testPracticeAgainDraftIsKeptApartFromTheCountedDraft() {
        let counted = MemoryLessonDraft()
        let practice = MemoryLessonDraft()
        let first = make(draft: counted.store, practiceDraft: practice.store)
        first.practiceAgain()
        XCTAssertNil(counted.state)
        XCTAssertEqual(practice.state?.practice, true)
        let later = make(draft: counted.store, practiceDraft: practice.store)
        XCTAssertFalse(later.state.practice)
        XCTAssertEqual(later.state.completedCount, 0)
        later.practiceAgain()
        later.tryAgain()
        XCTAssertNil(practice.state)
        XCTAssertEqual(counted.state?.practice, false)
    }

    func testLeavingMidLessonClearsTheDraftButLeavingWhileSavingDoesNot() {
        let draft = MemoryLessonDraft()
        let session = make(draft: draft.store)
        session.setTileAnswer("a")
        session.check()
        session.continueOn()
        XCTAssertNotNil(draft.state)
        session.leave()
        XCTAssertNil(draft.state)

        let keep = MemoryLessonDraft()
        let finishing = make(draft: keep.store, submit: { _ in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return .queued
        })
        answerAll(finishing)
        finishing.leave()
        XCTAssertNotNil(keep.state)
    }

    func testPracticeKeepsNoFinishedDraft() async {
        let draft = MemoryLessonDraft()
        let session = make(practice: true, draft: draft.store)
        answerAll(session)
        await session.waitForDelivery()
        XCTAssertNil(draft.state)
        XCTAssertEqual(session.phase, .ended(.practice))
    }

    // MARK: lessonsCompleted

    func testCompletedLessonIsCountedOnce() async {
        let counted = Counter()
        let session = make(counted: counted)
        answerAll(session)
        await session.waitForDelivery()
        XCTAssertEqual(counted.value, 1)
    }

    func testPracticeAndRejectedLessonsAreNotCounted() async {
        let counted = Counter()
        let practice = make(practice: true, counted: counted)
        answerAll(practice)
        await practice.waitForDelivery()
        let rejected = make(submit: { _ in .rejected(reason: nil) }, counted: counted)
        answerAll(rejected)
        await rejected.waitForDelivery()
        XCTAssertEqual(counted.value, 0)
    }

    func testCountsAsCompletedFollowsAndroid() {
        XCTAssertTrue(LessonSession.countsAsCompleted(.queued(completed: nil)))
        XCTAssertTrue(LessonSession.countsAsCompleted(.saved(completed: true, alreadyRecorded: false)))
        XCTAssertFalse(LessonSession.countsAsCompleted(.saved(completed: false, alreadyRecorded: false)))
        XCTAssertFalse(LessonSession.countsAsCompleted(.practice))
    }
}

private struct StubLoader: LessonSetupLoading {
    var result: LessonSetup?
    func setup(for route: LessonRoute) async throws -> LessonSetup? { result }
    func serverPrefs() async -> LessonServerPrefs { LessonServerPrefs() }
    func saveScriptMode(_ mode: ScriptMode) async {}
}

final class LessonEnvironmentTests: XCTestCase {
    private func lesson() -> LessonSetup {
        let exercise = ExerciseArtifact(type: .wordBank, scriptMode: .native, prompt: "p", tiles: ["a"], answer: ["a"], tags: ["t"])
        let instance = ExerciseInstance(key: "u/s/0", unitKey: "u", skillKey: "s", ordinal: 0, exercise: exercise, renderType: .wordBank)
        return LessonSetup(courseCode: "fa", courseVersion: 1, instances: [instance], exerciseCountBySkill: ["s": 1])
    }

    func testNoUserBlocksTheLessonBeforeItStarts() async {
        let env = LessonEnvironment(loader: StubLoader(result: lesson()), userId: { nil }, submit: { _, _ in .queued })
        do {
            _ = try await env.makeSession(for: LessonRoute(skillKey: "s"))
            XCTFail("expected signedOut")
        } catch {
            XCTAssertEqual(error as? LessonEnvironmentError, .signedOut)
        }
    }

    func testSessionWritesAheadUnderTheUserResolvedAtStart() async throws {
        let probe = Probe()
        let defaults = UserDefaults(suiteName: "lesson-env-test-" + UUID().uuidString) ?? UserDefaults.standard
        let env = LessonEnvironment(
            loader: StubLoader(result: lesson()),
            userId: { "u9" },
            prefsStore: LocalPrefsStore(defaults: defaults),
            submit: { user, _ in
                probe.add("submit " + user)
                return .queued
            },
            enqueue: { user, _ in probe.add("enqueue " + user) },
            grader: AlwaysRight(), gradingOnDevice: true
        )
        let made = try await env.makeSession(for: LessonRoute(skillKey: "s"))
        let session = try XCTUnwrap(made)
        session.setTileAnswer("a")
        session.check()
        session.continueOn()
        await session.waitForDelivery()
        XCTAssertEqual(probe.log, ["enqueue u9", "submit u9"])
        XCTAssertEqual(session.phase, .ended(.queued(completed: true)))
    }
}

final class LessonLoadFailureTests: XCTestCase {
    func testMessagesAreDistinct() {
        let signedOut = LessonScreenLogic.loadFailureMessage(for: LessonEnvironmentError.signedOut)
        let unwired = LessonScreenLogic.loadFailureMessage(for: UnwiredLessonSetupLoader.NotWired())
        let network = LessonScreenLogic.loadFailureMessage(for: URLError(.notConnectedToInternet))
        let other = LessonScreenLogic.loadFailureMessage(for: Boom())
        XCTAssertEqual(Set([signedOut, unwired, network, other]).count, 4)
        XCTAssertTrue(network.contains("connection"))
    }
}

final class LessonDraftStoreTests: XCTestCase {
    func testKeyDistinguishesUserAndPractice() {
        let a = LessonDraftStore.key(userId: "u1", courseCode: "fa", unitKey: "u", skillKey: "s", practice: false, checkpoint: false)
        let b = LessonDraftStore.key(userId: "u2", courseCode: "fa", unitKey: "u", skillKey: "s", practice: false, checkpoint: false)
        let c = LessonDraftStore.key(userId: "u1", courseCode: "fa", unitKey: "u", skillKey: "s", practice: true, checkpoint: false)
        XCTAssertEqual(Set([a, b, c]).count, 3)
        XCTAssertFalse(LessonDraftStore.fileName(for: a).contains("|"))
    }

    func testFileRoundTripAndClear() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lesson-draft-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LessonDraftStore.file(directory: dir, key: "u1|fa|u|s|counted|lesson")
        XCTAssertNil(store.load())
        let state = LessonState(queue: [], totalCount: 3, xp: 4)
        store.save(state)
        XCTAssertEqual(store.load(), state)
        store.clear()
        XCTAssertNil(store.load())
    }
}
