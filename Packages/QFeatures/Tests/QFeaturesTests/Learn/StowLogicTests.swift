import XCTest
import QModel
import QDomain
import QNetwork
@testable import QFeatures

private func skill(_ key: String) -> PathSkillInput {
    PathSkillInput(skillKey: key, title: key, category: .standard)
}

private let units: [PathUnitInput] = [
    PathUnitInput(
        unitKey: "u1",
        title: "Unit 1",
        standardPositions: [
            PathPositionInput(skills: [skill("a")]),
            PathPositionInput(skills: [skill("b")]),
            PathPositionInput(skills: [skill("c")]),
        ],
        otherSkills: []
    ),
    PathUnitInput(
        unitKey: "u2",
        title: "Unit 2",
        standardPositions: [PathPositionInput(skills: [skill("d")]), PathPositionInput(skills: [skill("e")])],
        otherSkills: []
    ),
]

private let course = CourseRef(code: "ja", version: 1, manifestSha256: "x")

private func stowed(_ key: String, due: Bool = false) -> StowedLesson {
    StowedLesson(lessonKey: key, stowedAt: Date(timeIntervalSince1970: 0), lessonsCompletedSince: 0, readyPromptDue: due, muted: false)
}

private func bootstrap(position: String = "d", unit: String = "u2", stowage: [StowageUnit] = [], stowable: [String] = []) -> BootstrapResponse {
    BootstrapResponse(
        course: course,
        position: PositionRef(unitKey: unit, skillKey: position),
        graders: [],
        enrolledCourseCodes: ["ja"],
        onboardingComplete: true,
        stowage: stowage,
        stowableLessonKeys: stowable
    )
}

private func readyState(_ boot: BootstrapResponse) -> PathState {
    var state = PathState()
    state.setBootstrap(boot)
    state.setContent(PathContent(units: units))
    return state
}

private func allSkills(_ state: PathState) -> [PathSkill] {
    state.units.flatMap { $0.standardPositions.flatMap { $0.skills } }
}

private struct TestError: Error {}

@MainActor
private final class FakeHost: StowStateHost {
    var stowage: [StowageUnit]
    var applied: [(stowage: [StowageUnit], position: PositionRef?)] = []

    init(stowage: [StowageUnit] = []) {
        self.stowage = stowage
    }

    func applyStowage(_ stowage: [StowageUnit], position: PositionRef?) {
        self.stowage = stowage
        applied.append((stowage, position))
    }
}

private final class FakeService: StowService, @unchecked Sendable {
    var events: [String] = []
    var stowResult: Result<StowResponse, Error> = .success(StowResponse(applied: true, position: PositionRef(unitKey: "u2", skillKey: "e"), stowage: [StowageUnit(unitKey: "u1", lessons: [stowed("b")])]))
    var snoozeResult: Result<StowageResponse, Error> = .success(StowageResponse(applied: true, stowage: []))
    var muteResult: Result<StowageResponse, Error> = .success(StowageResponse(applied: true, stowage: []))

    func stow(lessonKey: String) async throws -> StowResponse {
        events.append("stow:\(lessonKey)")
        return try stowResult.get()
    }
    func snoozeStowage() async throws -> StowageResponse {
        events.append("snooze")
        return try snoozeResult.get()
    }
    func muteStowage() async throws -> StowageResponse {
        events.append("mute")
        return try muteResult.get()
    }
}

private final class FakeFlusher: StowQueueFlushing, @unchecked Sendable {
    let service: FakeService
    var flushes = 0
    init(service: FakeService) {
        self.service = service
    }
    func flushQueue() async {
        flushes += 1
        service.events.append("flush")
    }
}

private final class MemoryPrefs: StowReminderPrefs, @unchecked Sendable {
    var enabled = true
    var sets = 0
    func isEnabled() -> Bool { enabled }
    func setEnabled(_ enabled: Bool) {
        sets += 1
        self.enabled = enabled
    }
}

final class StowPathStateTests: XCTestCase {
    func testSetBootstrapKeepsStowageAndStowableKeys() {
        let boot = bootstrap(stowage: [StowageUnit(unitKey: "u1", lessons: [stowed("b")])], stowable: ["d"])
        let state = readyState(boot)
        XCTAssertEqual(state.stowage, boot.stowage)
        XCTAssertEqual(state.stowableLessonKeys, ["d"])
        XCTAssertEqual(state.stowedLessonKeys, ["b"])
    }

    func testSkillIsStowedOnlyWhenInAStowageEntry() {
        let state = readyState(bootstrap(stowage: [StowageUnit(unitKey: "u1", lessons: [stowed("b")])]))
        XCTAssertEqual(allSkills(state).filter { $0.stowed }.map { $0.skillKey }, ["b"])
        // Behind the cursor, but unstowed lessons are untouched.
        XCTAssertFalse(allSkills(state).first(where: { $0.skillKey == "a" })!.stowed)
    }

    func testUnitWithALiveStowedLessonIsDeferredAndOthersAreNot() {
        let state = readyState(bootstrap(stowage: [StowageUnit(unitKey: "u1", lessons: [stowed("b")])]))
        XCTAssertEqual(state.deferredUnitKeys, ["u1"])
        XCTAssertEqual(state.units.map { $0.deferred }, [true, false])
    }

    func testNoStowageMeansNoDeferredUnit() {
        let state = readyState(bootstrap())
        XCTAssertTrue(state.deferredUnitKeys.isEmpty)
    }

    func testStowedStateComesFromStowageNotPosition() {
        // The same cursor, with and without a Stowage entry for a lesson behind it.
        let without = readyState(bootstrap())
        let with = readyState(bootstrap(stowage: [StowageUnit(unitKey: "u1", lessons: [stowed("c")])]))
        XCTAssertEqual(without.units[0].standardPositions.map { $0.status }, with.units[0].standardPositions.map { $0.status })
        XCTAssertFalse(allSkills(without).contains(where: { $0.stowed }))
        XCTAssertTrue(allSkills(with).first(where: { $0.skillKey == "c" })!.stowed)
    }

    func testStowedStyleIsOnePlaceholderThroughRetries() {
        let state = readyState(bootstrap(stowage: [StowageUnit(unitKey: "u1", lessons: [stowed("b")])]))
        let b = allSkills(state).first(where: { $0.skillKey == "b" })!
        let a = allSkills(state).first(where: { $0.skillKey == "a" })!
        XCTAssertEqual(StowedNodeStyle.style(for: b), StowedNodeStyle.placeholder)
        XCTAssertTrue(StowedNodeStyle.placeholder.gray)
        XCTAssertFalse(StowedNodeStyle.placeholder.showsDone)
        XCTAssertNil(StowedNodeStyle.style(for: a))
        // A failed or abandoned retry leaves the Stowage unchanged, so the style is unchanged.
        var again = state
        again.setBootstrap(bootstrap(stowage: [StowageUnit(unitKey: "u1", lessons: [stowed("b")])]))
        XCTAssertEqual(StowedNodeStyle.style(for: allSkills(again).first(where: { $0.skillKey == "b" })!), StowedNodeStyle.placeholder)
    }

    func testStowOfferedOnlyForStowableKeysAndIsTheLastAction() {
        let state = readyState(bootstrap(stowable: ["d"]))
        let d = allSkills(state).first(where: { $0.skillKey == "d" })!
        let e = allSkills(state).first(where: { $0.skillKey == "e" })!
        XCTAssertTrue(skillActions(d, nextSkipTarget: state.nextSkipTarget, stowableLessonKeys: Set(state.stowableLessonKeys)).stowOffered)
        XCTAssertFalse(skillActions(e, nextSkipTarget: nil, stowableLessonKeys: Set(state.stowableLessonKeys)).stowOffered)
        XCTAssertFalse(skillActions(d, nextSkipTarget: nil).stowOffered)
        let popover = lessonPopoverActions(d, nextSkipTarget: nil, themeIndex: nil, stowableLessonKeys: ["d"])
        XCTAssertTrue(popover.stowOffered)
    }

    func testStowedLessonIsNotOfferedStowAgain() {
        let state = readyState(bootstrap(stowage: [StowageUnit(unitKey: "u1", lessons: [stowed("b")])], stowable: ["b"]))
        let b = allSkills(state).first(where: { $0.skillKey == "b" })!
        XCTAssertFalse(skillActions(b, nextSkipTarget: nil, stowableLessonKeys: ["b"]).stowOffered)
    }

    func testApplyStowageMovesCursorAndMarksTheLesson() {
        var state = readyState(bootstrap(position: "d", stowable: ["d"]))
        state.applyStowage([StowageUnit(unitKey: "u2", lessons: [stowed("d")])], position: PositionRef(unitKey: "u2", skillKey: "e"))
        XCTAssertEqual(state.position, PositionKey(unitKey: "u2", skillKey: "e"))
        XCTAssertTrue(allSkills(state).first(where: { $0.skillKey == "d" })!.stowed)
        XCTAssertEqual(state.currentNode?.skillKey, "e")
        XCTAssertTrue(state.stowableLessonKeys.isEmpty)
    }

    func testApplyStowClearedDropsTheLessonAndEmptyUnits() {
        var state = readyState(bootstrap(stowage: [
            StowageUnit(unitKey: "u2", lessons: [stowed("d")]),
            StowageUnit(unitKey: "u1", lessons: [stowed("a"), stowed("b")]),
        ]))
        state.applyStowCleared("d")
        XCTAssertEqual(state.stowage.map { $0.unitKey }, ["u1"])
        XCTAssertEqual(state.units.map { $0.deferred }, [true, false])
        state.applyStowCleared("a")
        state.applyStowCleared("b")
        XCTAssertTrue(state.stowage.isEmpty)
        XCTAssertTrue(state.deferredUnitKeys.isEmpty)
    }
}

@MainActor
final class StowFlowModelTests: XCTestCase {
    private func make(_ service: FakeService = FakeService(), host: FakeHost? = nil, refreshes: Counter = Counter()) -> (StowFlowModel, FakeService, FakeFlusher, FakeHost, Counter) {
        let host = host ?? FakeHost()
        let flusher = FakeFlusher(service: service)
        let model = StowFlowModel(service: service, flusher: flusher, host: host, refresh: { refreshes.count += 1 })
        return (model, service, flusher, host, refreshes)
    }

    final class Counter: @unchecked Sendable {
        var count = 0
    }

    func testRequestOpensTheConfirmation() {
        let (model, _, _, _, _) = make()
        model.request(lessonKey: "d")
        XCTAssertEqual(model.flow?.step, .confirm)
        XCTAssertEqual(model.flow?.lessonKey, "d")
    }

    func testConfirmFlushesFirstThenStowsThenAppliesAndEncourages() async {
        let (model, service, flusher, host, refreshes) = make()
        model.request(lessonKey: "d")
        await model.confirm()
        XCTAssertEqual(service.events, ["flush", "stow:d"])
        XCTAssertEqual(flusher.flushes, 1)
        XCTAssertEqual(host.applied.count, 1)
        XCTAssertEqual(host.applied[0].position, PositionRef(unitKey: "u2", skillKey: "e"))
        XCTAssertEqual(host.applied[0].stowage.map { $0.unitKey }, ["u1"])
        XCTAssertEqual(refreshes.count, 1)
        XCTAssertEqual(model.flow?.step, .encouraged)
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.error)
    }

    func testAppliedFalseIsSuccess() async {
        let service = FakeService()
        service.stowResult = .success(StowResponse(applied: false, position: PositionRef(unitKey: "u2", skillKey: "e"), stowage: []))
        let (model, _, _, host, _) = make(service)
        model.request(lessonKey: "d")
        await model.confirm()
        XCTAssertEqual(model.flow?.step, .encouraged)
        XCTAssertEqual(host.applied.count, 1)
    }

    func testStowErrorsMapToMessagesAndStayOnTheConfirmation() async {
        let cases: [(StowError, String)] = [
            (.noFailedAttempt, "This lesson can't be stowed any more. Your path has been refreshed."),
            (.alreadyCleared, "You've already passed this lesson."),
            (.alreadyDropped, "This lesson is no longer on your path."),
            (.unknownLesson, "This lesson is no longer on your path."),
            (.notCurrentPosition, "Your path has moved on. It has been refreshed."),
            (.notProvisioned, "Your path has moved on. It has been refreshed."),
            (.invalidRequest, StowCopy.genericStowError),
        ]
        for (error, message) in cases {
            let service = FakeService()
            service.stowResult = .failure(error)
            let (model, _, _, host, refreshes) = make(service)
            model.request(lessonKey: "d")
            await model.confirm()
            XCTAssertEqual(model.error, message)
            XCTAssertEqual(model.flow?.step, .confirm)
            XCTAssertFalse(model.busy)
            XCTAssertTrue(host.applied.isEmpty)
            // A contract refusal means the held path was stale, except a malformed request.
            XCTAssertEqual(refreshes.count, error == .invalidRequest ? 0 : 1)
        }
    }

    func testOtherFailureShowsGenericMessageAndCanRetry() async {
        let service = FakeService()
        service.stowResult = .failure(TestError())
        let (model, _, flusher, _, _) = make(service)
        model.request(lessonKey: "d")
        await model.confirm()
        XCTAssertEqual(model.error, StowCopy.genericStowError)
        service.stowResult = .success(StowResponse(applied: true, position: PositionRef(unitKey: "u2", skillKey: "e"), stowage: []))
        await model.confirm()
        XCTAssertNil(model.error)
        XCTAssertEqual(model.flow?.step, .encouraged)
        XCTAssertEqual(flusher.flushes, 2)
    }

    func testDeclineShowsEncouragementAndRetryReturnsTheTappedLesson() {
        let (model, service, _, _, _) = make()
        model.request(lessonKey: "d")
        model.decline()
        XCTAssertEqual(model.flow?.step, .declined)
        XCTAssertEqual(model.retryLesson(), "d")
        XCTAssertNil(model.flow)
        XCTAssertTrue(service.events.isEmpty)
    }

    func testCloseAndContinueDismiss() async {
        let (model, _, _, _, _) = make()
        model.request(lessonKey: "d")
        model.decline()
        model.dismiss()
        XCTAssertNil(model.flow)
        model.request(lessonKey: "d")
        await model.confirm()
        model.dismiss()
        XCTAssertNil(model.flow)
        XCTAssertNil(model.retryLesson())
    }

    func testMessageMapping() {
        XCTAssertEqual(StowCopy.message(for: TestError()), StowCopy.genericStowError)
    }
}

@MainActor
final class StowReminderModelTests: XCTestCase {
    private func make(stowage: [StowageUnit], enabled: Bool = true) -> (StowReminderModel, FakeService, FakeHost, MemoryPrefs) {
        let service = FakeService()
        let host = FakeHost(stowage: stowage)
        let prefs = MemoryPrefs()
        prefs.enabled = enabled
        return (StowReminderModel(service: service, prefs: prefs, host: host), service, host, prefs)
    }

    private let due = [StowageUnit(unitKey: "u1", lessons: [stowed("a", due: false), stowed("b", due: true)])]

    func testShownWhenAnyLessonIsDueAndTheSettingIsOn() {
        let (model, _, _, _) = make(stowage: due)
        XCTAssertTrue(model.readyPromptDue)
        XCTAssertTrue(model.isShown)
    }

    func testHiddenWhenNothingIsDue() {
        let (model, _, _, _) = make(stowage: [StowageUnit(unitKey: "u1", lessons: [stowed("a")])])
        XCTAssertFalse(model.isShown)
        XCTAssertFalse(make(stowage: []).0.isShown)
    }

    func testHiddenWhenTheDeviceSettingIsOff() {
        let (model, _, _, _) = make(stowage: due, enabled: false)
        XCTAssertTrue(model.readyPromptDue)
        XCTAssertFalse(model.isShown)
    }

    func testNotYetSnoozesAppliesStowageAndLeavesThePref() async {
        let (model, service, host, prefs) = make(stowage: due)
        let after = [StowageUnit(unitKey: "u1", lessons: [stowed("a"), stowed("b")])]
        service.snoozeResult = .success(StowageResponse(applied: true, stowage: after))
        await model.notYet()
        XCTAssertEqual(service.events, ["snooze"])
        XCTAssertEqual(host.stowage, after)
        XCTAssertEqual(prefs.sets, 0)
        XCTAssertTrue(prefs.enabled)
        XCTAssertFalse(model.isShown)
        XCTAssertFalse(model.busy)
    }

    func testMuteCallsMuteAppliesStowageAndLeavesThePref() async {
        let (model, service, host, prefs) = make(stowage: due)
        let after = [StowageUnit(unitKey: "u1", lessons: [StowedLesson(lessonKey: "b", stowedAt: Date(timeIntervalSince1970: 0), lessonsCompletedSince: 3, readyPromptDue: false, muted: true)])]
        service.muteResult = .success(StowageResponse(applied: true, stowage: after))
        await model.mute()
        XCTAssertEqual(service.events, ["mute"])
        XCTAssertEqual(host.stowage, after)
        XCTAssertEqual(prefs.sets, 0)
        XCTAssertTrue(prefs.enabled)
    }

    func testFailureKeepsTheReminderAndShowsAnError() async {
        let (model, service, host, _) = make(stowage: due)
        service.snoozeResult = .failure(TestError())
        await model.notYet()
        XCTAssertEqual(model.error, StowCopy.reminderError)
        XCTAssertEqual(host.stowage, due)
        XCTAssertTrue(model.isShown)
        XCTAssertFalse(model.busy)
    }

    func testPutAwayHidesWithoutCallingTheServer() {
        let (model, service, _, _) = make(stowage: due)
        model.putAway()
        XCTAssertFalse(model.isShown)
        XCTAssertTrue(service.events.isEmpty)
    }

    func testGroupsKeepTheServerOrderUnitsDescending() {
        let stowage = [
            StowageUnit(unitKey: "u2", lessons: [stowed("e", due: true), stowed("d")]),
            StowageUnit(unitKey: "u1", lessons: [stowed("a"), stowed("c")]),
            StowageUnit(unitKey: "gone", lessons: [stowed("zz")]),
        ]
        let (model, _, _, _) = make(stowage: stowage)
        let path = readyState(bootstrap(stowage: stowage)).units
        let groups = model.groups(path: path)
        XCTAssertEqual(groups.map { $0.unitKey }, ["u2", "u1"])
        XCTAssertEqual(groups.map { $0.unitTitle }, ["Unit 2", "Unit 1"])
        XCTAssertEqual(groups[0].lessons.map { $0.skillKey }, ["e", "d"])
        XCTAssertEqual(groups[1].lessons.map { $0.skillKey }, ["a", "c"])
    }

    func testPrefsDefaultOnAndAreDeviceLocal() {
        let suite = "stow-prefs-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = UserDefaultsStowReminderPrefs(defaults: defaults)
        XCTAssertTrue(prefs.isEnabled())
        prefs.setEnabled(false)
        XCTAssertFalse(UserDefaultsStowReminderPrefs(defaults: defaults).isEnabled())
        prefs.setEnabled(true)
        XCTAssertTrue(prefs.isEnabled())
    }
}

@MainActor
final class StowClearedModelTests: XCTestCase {
    private final class Repo: PathRepository, @unchecked Sendable {
        var contentCalls = 0
        func pathContent(course: CourseRef) async throws -> PathContent {
            contentCalls += 1
            return PathContent(units: units)
        }
        func completedLessonKeys(courseCode: String) async throws -> Set<String> { [] }
        func prefs() async throws -> PrefsResponse { throw TestError() }
        func activity(courseCode: String) async throws -> ActivityResponse { throw TestError() }
    }

    func testStowClearedDropsTheLessonAndRefreshes() async {
        let repo = Repo()
        let model = PathModel(repository: repo)
        await model.refresh(bootstrap: bootstrap(stowage: [StowageUnit(unitKey: "u1", lessons: [stowed("b")])]))
        XCTAssertEqual(model.state.deferredUnitKeys, ["u1"])
        XCTAssertEqual(repo.contentCalls, 1)

        await model.applyStowCleared("b")
        XCTAssertTrue(model.state.stowage.isEmpty)
        XCTAssertTrue(model.state.deferredUnitKeys.isEmpty)
        XCTAssertEqual(repo.contentCalls, 2)
    }
}

@MainActor
final class StowJourneyHooksTests: XCTestCase {
    private func hooks() -> (StowJourneyHooks, StowFlowModel) {
        let host = FakeHost()
        let service = FakeService()
        let flow = StowFlowModel(service: service, flusher: FakeFlusher(service: service), host: host)
        let reminder = StowReminderModel(service: service, prefs: MemoryPrefs(), host: host)
        return (StowJourneyHooks(flow: flow, reminder: reminder, onRetryLesson: { _ in }), flow)
    }

    private func pathSkill(_ key: String, stowed: Bool = false) -> PathSkill {
        PathSkill(
            skillKey: key, title: key, category: .standard, arc: nil, unitKey: "u1",
            status: .unlocked, completed: true, positionIndex: 0, stowed: stowed
        )
    }

    func testOnStowIsNilUnlessOffered() {
        let (hooks, flow) = hooks()
        let skill = pathSkill("a")
        let off = SkillActions(primaryLabel: "Practice", startsLesson: false, skipTarget: nil, stowOffered: false)
        XCTAssertNil(hooks.onStow(for: skill, actions: off))
        let on = SkillActions(primaryLabel: "Practice", startsLesson: false, skipTarget: nil, stowOffered: true)
        let closure = hooks.onStow(for: skill, actions: on)
        XCTAssertNotNil(closure)
        closure?()
        XCTAssertEqual(flow.flow?.lessonKey, "a")
        XCTAssertEqual(flow.flow?.step, .confirm)
    }

    func testDeferredUnitGetsTheStowStyleAndNeverTheCheck() {
        let normal = PathUnit(unitKey: "u1", title: "U1", standardPositions: [PathPosition(positionIndex: 0, status: .unlocked, skills: [pathSkill("a")])], otherSkills: [])
        let deferred = PathUnit(unitKey: "u1", title: "U1", standardPositions: [PathPosition(positionIndex: 0, status: .unlocked, skills: [pathSkill("a", stowed: true)])], otherSkills: [])
        XCTAssertNil(StowedUnitStyle.style(for: normal))
        let style = StowedUnitStyle.style(for: deferred)
        XCTAssertEqual(style, StowedUnitStyle.placeholder)
        XCTAssertEqual(style?.showsCheck, false)
        XCTAssertLessThan(StowedUnitStyle.placeholder.borderOpacity, 1)
    }
}

@MainActor
final class StowRemindersSettingTests: XCTestCase {
    func testPrefsDefaultOnAndDeviceLocal() {
        let suite = UserDefaults(suiteName: "stow.prefs." + UUID().uuidString)!
        let prefs = UserDefaultsStowReminderPrefs(defaults: suite)
        XCTAssertTrue(prefs.isEnabled())
        prefs.setEnabled(false)
        XCTAssertFalse(UserDefaultsStowReminderPrefs(defaults: suite).isEnabled())
    }
}
