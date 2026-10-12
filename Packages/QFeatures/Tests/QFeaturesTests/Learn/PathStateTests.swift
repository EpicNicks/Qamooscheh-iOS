import XCTest
import QModel
import QDomain
@testable import QFeatures

private func skill(_ key: String) -> PathSkillInput {
    PathSkillInput(skillKey: key, title: key, category: .standard)
}

private let fixtureUnits: [PathUnitInput] = [
    PathUnitInput(
        unitKey: "u1",
        title: "Unit 1",
        standardPositions: [
            PathPositionInput(skills: [skill("a")]),
            PathPositionInput(skills: [skill("b1"), skill("b2")]),
            PathPositionInput(skills: [skill("c")]),
        ],
        otherSkills: [PathSkillInput(skillKey: "story", title: "Story", category: .story)]
    ),
    PathUnitInput(
        unitKey: "u2",
        title: "Unit 2",
        standardPositions: [PathPositionInput(skills: [skill("d")])],
        otherSkills: []
    ),
]

private let course = CourseRef(code: "ja", version: 3, manifestSha256: "x")

private func bootstrap(
    course: CourseRef? = course,
    position: PositionRef? = PositionRef(unitKey: "u1", skillKey: "b1"),
    enrolled: [String] = ["ja"]
) -> BootstrapResponse {
    BootstrapResponse(course: course, position: position, graders: [], enrolledCourseCodes: enrolled, onboardingComplete: true)
}

private func makePrefs(goal: Int) -> PrefsResponse {
    PrefsResponse(scriptMode: .native, register: .standard, autoplayAudio: true, keyboardMode: .contextual, desiredRetention: 0.9, dailyGoalXp: goal)
}

private struct TestError: Error {}

private final class FakeRepo: PathRepository, @unchecked Sendable {
    var content: Result<PathContent, Error> = .success(PathContent(units: fixtureUnits))
    var completed: Result<Set<String>, Error> = .success([])
    var prefsResult: Result<PrefsResponse, Error> = .success(makePrefs(goal: 500))
    var activityResult: Result<ActivityResponse, Error> = .success(ActivityResponse(courseCode: "ja", days: []))
    var contentCalls: [String] = []

    func pathContent(course: CourseRef) async throws -> PathContent {
        contentCalls.append(course.code)
        return try content.get()
    }
    func completedLessonKeys(courseCode: String) async throws -> Set<String> { try completed.get() }
    func prefs() async throws -> PrefsResponse { try prefsResult.get() }
    func activity(courseCode: String) async throws -> ActivityResponse { try activityResult.get() }
}

private func readyState(position: PositionRef? = PositionRef(unitKey: "u1", skillKey: "b1"), completed: Set<String> = []) -> PathState {
    var state = PathState()
    state.setBootstrap(bootstrap(position: position))
    state.setCompleted(completed)
    state.setContent(PathContent(units: fixtureUnits))
    return state
}

final class PathStateTests: XCTestCase {
    // MARK: current node

    func testCurrentNodeIsTheCursorPosition() {
        let node = readyState().currentNode
        XCTAssertEqual(node, PathCurrentNode(unitKey: "u1", unitIndex: 0, positionIndex: 1, skillKey: "b1"))
    }

    func testCurrentNodeMatchesAnyAlternateAtTheCursorPosition() {
        let node = readyState(position: PositionRef(unitKey: "u1", skillKey: "b2")).currentNode
        XCTAssertEqual(node?.positionIndex, 1)
        XCTAssertEqual(node?.skillKey, "b1")
    }

    func testCurrentNodePrefersTheFirstUnfinishedAlternate() {
        let node = readyState(completed: ["b1"]).currentNode
        XCTAssertEqual(node?.skillKey, "b2")
    }

    func testCurrentNodeInALaterUnit() {
        let node = readyState(position: PositionRef(unitKey: "u2", skillKey: "d")).currentNode
        XCTAssertEqual(node, PathCurrentNode(unitKey: "u2", unitIndex: 1, positionIndex: 0, skillKey: "d"))
    }

    func testNoCursorMeansNoCurrentNode() {
        XCTAssertNil(readyState(position: nil).currentNode)
    }

    func testUnknownCursorMeansNoCurrentNode() {
        XCTAssertNil(readyState(position: PositionRef(unitKey: "zz", skillKey: "q")).currentNode)
    }

    func testSkipAndUnitEntryTargets() {
        let state = readyState()
        XCTAssertEqual(state.nextSkipTarget, PositionKey(unitKey: "u1", skillKey: "c"))
        XCTAssertEqual(state.nextUnitEntry, PositionKey(unitKey: "u2", skillKey: "d"))
    }

    func testCurrentNodeYUsesTheRoadLayout() {
        let config = RoadLayoutConfig(rowHeight: 100, branchSpread: 60, logicalWidth: 300, nodeHalfWidth: 20)
        // topPadding 50, position 1 -> 50 + 100.
        XCTAssertEqual(readyState().currentNodeY(config: config), 150)
        XCTAssertNil(readyState(position: nil).currentNodeY(config: config))
    }

    func testSkillActionsOnlyOfferSkipOnTheCurrentLesson() {
        let state = readyState()
        let current = state.units[0].standardPositions[1].skills[0]
        let done = state.units[0].standardPositions[0].skills[0]
        let currentActions = skillActions(current, nextSkipTarget: state.nextSkipTarget)
        XCTAssertEqual(currentActions.primaryLabel, "Start lesson")
        XCTAssertTrue(currentActions.startsLesson)
        XCTAssertEqual(currentActions.skipTarget, PositionKey(unitKey: "u1", skillKey: "c"))
        let doneActions = skillActions(done, nextSkipTarget: state.nextSkipTarget)
        XCTAssertEqual(doneActions.primaryLabel, "Practice")
        XCTAssertNil(doneActions.skipTarget)
        XCTAssertNil(skillActions(current, nextSkipTarget: nil).skipTarget)
    }

    // MARK: popover

    func testOpenReplacesAndCloseClears() {
        var state = readyState()
        state.openPopover("u1/a")
        XCTAssertEqual(state.openPopoverId, "u1/a")
        state.openPopover("u1/c")
        XCTAssertEqual(state.openPopoverId, "u1/c")
        state.closePopover()
        XCTAssertNil(state.openPopoverId)
    }

    func testToggleClosesTheSameNodeAndSwitchesToAnother() {
        var state = readyState()
        state.togglePopover("u1/a")
        XCTAssertEqual(state.openPopoverId, "u1/a")
        state.togglePopover("u1/c")
        XCTAssertEqual(state.openPopoverId, "u1/c")
        state.togglePopover("u1/c")
        XCTAssertNil(state.openPopoverId)
    }

    func testPopoverIdMatchesRefKeyShape() {
        XCTAssertEqual(pathPopoverId(unitKey: "u1", skillKey: "a"), refKey(SkillRef(unitKey: "u1", skillKey: "a")))
    }

    func testOpenPopoverClosesWhenItsSkillDisappears() {
        var state = readyState()
        state.openPopover("u1/a")
        state.setContent(PathContent(units: [fixtureUnits[1]]))
        XCTAssertNil(state.openPopoverId)
    }

    func testChangingCourseClosesThePopover() {
        var state = readyState()
        state.openPopover("u1/a")
        state.setBootstrap(bootstrap(course: CourseRef(code: "fa", version: 1, manifestSha256: "y"), enrolled: ["ja", "fa"]))
        XCTAssertNil(state.openPopoverId)
        XCTAssertEqual(state.status, .loading)
        XCTAssertTrue(state.units.isEmpty)
        XCTAssertEqual(state.enrolledCourseCodes, ["ja", "fa"])
    }

    // MARK: daily goal

    func testDailyGoalProgressFraction() {
        XCTAssertEqual(DailyGoalProgress(xp: 250, goal: 500).fraction, 0.5)
        XCTAssertFalse(DailyGoalProgress(xp: 250, goal: 500).reached)
        XCTAssertEqual(DailyGoalProgress(xp: 900, goal: 500).fraction, 1)
        XCTAssertTrue(DailyGoalProgress(xp: 500, goal: 500).reached)
        XCTAssertEqual(DailyGoalProgress(xp: 10, goal: 0).fraction, 0)
        XCTAssertFalse(DailyGoalProgress(xp: 10, goal: 0).reached)
    }

    func testDailyGoalUsesTodaysXpOnly() {
        var state = readyState()
        let days = [
            ActivityDay(localDay: "2026-10-11", reviews: 3, xp: 400),
            ActivityDay(localDay: "2026-10-12", reviews: 2, xp: 125),
        ]
        state.setDailyGoal(goal: 500, days: days, today: "2026-10-12")
        XCTAssertEqual(state.dailyGoal, DailyGoalProgress(xp: 125, goal: 500))
        state.setDailyGoal(goal: 500, days: days, today: "2026-10-13")
        XCTAssertEqual(state.dailyGoal?.xp, 0)
    }

    func testNoGoalHidesTheRing() {
        var state = readyState()
        state.setDailyGoal(goal: 500, days: [], today: "2026-10-12")
        state.setDailyGoal(goal: nil, days: [], today: "2026-10-12")
        XCTAssertNil(state.dailyGoal)
    }

    // MARK: jump to current

    func testJumpDirectionFromScrollGeometry() {
        XCTAssertNil(jumpToCurrentDirection(nil))
        XCTAssertEqual(jumpToCurrentDirection(.offscreenAbove), .up)
        XCTAssertEqual(jumpToCurrentDirection(.offscreenBelow), .down)
        XCTAssertEqual(jumpToCurrentDirection(.visible(nodeCentre: -5, viewportStart: 0, viewportEnd: 800)), .up)
        XCTAssertEqual(jumpToCurrentDirection(.visible(nodeCentre: 900, viewportStart: 0, viewportEnd: 800)), .down)
        XCTAssertNil(jumpToCurrentDirection(.visible(nodeCentre: 400, viewportStart: 0, viewportEnd: 800)))
        XCTAssertNil(jumpToCurrentDirection(.visible(nodeCentre: 0, viewportStart: 0, viewportEnd: 800)))
        XCTAssertNil(jumpToCurrentDirection(.visible(nodeCentre: 800, viewportStart: 0, viewportEnd: 800)))
    }

    func testStateShowsJumpOnlyWhenThereIsACurrentNode() {
        var state = readyState()
        state.setScroll(.offscreenBelow)
        XCTAssertEqual(state.jumpDirection, .down)
        state.setScroll(.visible(nodeCentre: 10, viewportStart: 0, viewportEnd: 100))
        XCTAssertNil(state.jumpDirection)

        var empty = readyState(position: nil)
        empty.setScroll(.offscreenAbove)
        XCTAssertNil(empty.jumpDirection)
    }

    func testJumpClearsWhenTheCurrentNodeGoesAway() {
        var state = readyState()
        state.setScroll(.offscreenAbove)
        XCTAssertEqual(state.jumpDirection, .up)
        state.setBootstrap(bootstrap(position: nil))
        XCTAssertNil(state.jumpDirection)
    }

    // MARK: no course

    func testNoCourse() {
        var state = readyState()
        state.setBootstrap(bootstrap(course: nil, position: nil))
        XCTAssertEqual(state.status, .noCourse)
        XCTAssertNil(state.currentNode)
        XCTAssertTrue(state.units.isEmpty)
    }
}

@MainActor
final class PathModelTests: XCTestCase {
    private func makeModel(_ repo: FakeRepo) -> PathModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_760_270_400) // 2025-10-12 12:00 UTC
        return PathModel(repository: repo, now: { now }, calendar: calendar)
    }

    func testRefreshLoadsEverything() async {
        let repo = FakeRepo()
        repo.completed = .success(["a"])
        repo.activityResult = .success(ActivityResponse(courseCode: "ja", days: [ActivityDay(localDay: "2025-10-12", reviews: 1, xp: 200)]))
        let model = makeModel(repo)
        await model.refresh(bootstrap: bootstrap())
        XCTAssertEqual(model.state.status, .ready)
        XCTAssertEqual(model.state.currentNode?.positionIndex, 1)
        XCTAssertTrue(model.state.units[0].standardPositions[0].skills[0].completed)
        XCTAssertEqual(model.state.dailyGoal, DailyGoalProgress(xp: 200, goal: 500))
    }

    func testContentFailureShowsFailed() async {
        let repo = FakeRepo()
        repo.content = .failure(TestError())
        let model = makeModel(repo)
        await model.refresh(bootstrap: bootstrap())
        if case .failed = model.state.status {} else { XCTFail("expected failed, got \(model.state.status)") }
    }

    func testCompletedFailureIsBestEffort() async {
        let repo = FakeRepo()
        repo.completed = .failure(TestError())
        let model = makeModel(repo)
        await model.refresh(bootstrap: bootstrap())
        XCTAssertEqual(model.state.status, .ready)
        XCTAssertTrue(model.state.completedSkillKeys.isEmpty)
    }

    func testPrefsFailureHidesTheRing() async {
        let repo = FakeRepo()
        repo.prefsResult = .failure(TestError())
        let model = makeModel(repo)
        await model.refresh(bootstrap: bootstrap())
        XCTAssertNil(model.state.dailyGoal)
    }

    func testNoCourseSkipsLoading() async {
        let repo = FakeRepo()
        let model = makeModel(repo)
        await model.refresh(bootstrap: bootstrap(course: nil, position: nil))
        XCTAssertEqual(model.state.status, .noCourse)
        XCTAssertTrue(repo.contentCalls.isEmpty)
    }

    func testPopoverAndScrollThroughTheModel() async {
        let model = makeModel(FakeRepo())
        await model.refresh(bootstrap: bootstrap())
        model.openPopover("u1/a")
        XCTAssertEqual(model.state.openPopoverId, "u1/a")
        model.setScroll(.offscreenAbove)
        XCTAssertEqual(model.state.jumpDirection, .up)
        model.closePopover()
        XCTAssertNil(model.state.openPopoverId)
    }

    func testRefreshKeepsPopoverAndCursorMovesCurrentNode() async {
        let model = makeModel(FakeRepo())
        await model.refresh(bootstrap: bootstrap())
        model.openPopover("u1/c")
        await model.refresh(bootstrap: bootstrap(position: PositionRef(unitKey: "u1", skillKey: "c")))
        XCTAssertEqual(model.state.currentNode?.positionIndex, 2)
        XCTAssertEqual(model.state.openPopoverId, "u1/c")
    }
}
