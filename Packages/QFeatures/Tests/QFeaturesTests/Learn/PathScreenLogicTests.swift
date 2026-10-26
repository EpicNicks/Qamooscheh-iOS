import XCTest
import QModel
import QDomain
import QData
@testable import QFeatures

private func pathSkillFixture(_ key: String, status: SkillStatus, stowed: Bool = false, completed: Bool = false) -> PathSkill {
    PathSkill(skillKey: key, title: key, category: .standard, arc: nil, unitKey: "u1", status: status, completed: completed, positionIndex: 0, stowed: stowed)
}

private final class RecordingNavigator: PathNavigator {
    var calls: [String] = []
    func startLesson(_ skill: PathSkill) { calls.append("start:\(skill.skillKey)") }
    func practice(_ skill: PathSkill) { calls.append("practice:\(skill.skillKey)") }
    func retryStowed(_ skill: PathSkill) { calls.append("retry:\(skill.skillKey)") }
    func checkpoint(_ target: PositionKey) { calls.append("checkpoint:\(target.skillKey)") }
    func reviewVocabulary(_ skill: PathSkill) { calls.append("vocab:\(skill.skillKey)") }
    func reviewUnitVocabulary(unitKey: String) { calls.append("unitVocab:\(unitKey)") }
    func deepDiveRemix(lessonKey: String) { calls.append("remix:\(lessonKey)") }
    func openTheme(themeId: String, fromLessonKey: String) { calls.append("theme:\(themeId):\(fromLessonKey)") }
}

final class PathScreenLogicTests: XCTestCase {
    // MARK: Screen state mapping

    func testNoCourseAndLoadingShowTheSpinner() {
        XCTAssertEqual(pathScreenPhase(status: .noCourse, download: nil), .loading)
        XCTAssertEqual(pathScreenPhase(status: .loading, download: nil), .loading)
        // No course means nothing to download, whatever a stale download says.
        XCTAssertEqual(pathScreenPhase(status: .noCourse, download: .waiting), .loading)
    }

    func testUnfinishedDownloadComesBeforeTheReadResult() {
        XCTAssertEqual(pathScreenPhase(status: .loading, download: .waiting), .downloading(.waiting))
        XCTAssertEqual(pathScreenPhase(status: .failed("x"), download: .failed), .downloading(.failed))
        XCTAssertEqual(pathScreenPhase(status: .ready, download: .downloading(done: 1, total: 4)), .downloading(.downloading(done: 1, total: 4)))
    }

    func testReadResultOnceTheDownloadIsComplete() {
        XCTAssertEqual(pathScreenPhase(status: .ready, download: nil), .ready)
        XCTAssertEqual(pathScreenPhase(status: .failed("boom"), download: nil), .failed)
    }

    func testDownloadMessages() {
        XCTAssertEqual(PathScreenCopy.message(for: .waiting), "Waiting for a connection to download your course\u{2026}")
        XCTAssertEqual(PathScreenCopy.message(for: .downloading(done: 3, total: 40)), "Downloading your course\u{2026} 3 of 40")
        XCTAssertEqual(PathScreenCopy.message(for: .downloading(done: 0, total: 0)), "Downloading your course\u{2026}")
        XCTAssertEqual(PathScreenCopy.message(for: .failed), "Couldn't download this course.")
    }

    func testDownloaderProgressBecomesAPhase() {
        XCTAssertEqual(CourseDownloadPhase(DownloadProgress(done: 5, discovered: 9)), .downloading(done: 5, total: 9))
    }

    // MARK: Primary action

    func testPrimaryActionPerLessonState() {
        XCTAssertEqual(pathPrimaryAction(pathSkillFixture("a", status: .unlocked, stowed: true)), .retryStowed)
        XCTAssertEqual(pathPrimaryAction(pathSkillFixture("a", status: .current)), .startLesson)
        XCTAssertEqual(pathPrimaryAction(pathSkillFixture("a", status: .unlocked)), .practice)
        XCTAssertEqual(pathPrimaryAction(pathSkillFixture("a", status: .locked)), .practice)
    }

    func testPopoverLabelForAStowedLessonRetries() {
        let stowed = skillActions(pathSkillFixture("a", status: .unlocked, stowed: true), nextSkipTarget: nil)
        XCTAssertEqual(stowed.primaryLabel, "Retry lesson")
        XCTAssertFalse(stowed.startsLesson)
        XCTAssertEqual(skillActions(pathSkillFixture("a", status: .current), nextSkipTarget: nil).primaryLabel, "Start lesson")
        XCTAssertEqual(skillActions(pathSkillFixture("a", status: .unlocked), nextSkipTarget: nil).primaryLabel, "Practice")
    }

    func testNavigatorRoutesThePrimaryButton() {
        let navigator = RecordingNavigator()
        navigator.performPrimary(pathSkillFixture("s", status: .unlocked, stowed: true))
        navigator.performPrimary(pathSkillFixture("c", status: .current))
        navigator.performPrimary(pathSkillFixture("p", status: .unlocked))
        XCTAssertEqual(navigator.calls, ["retry:s", "start:c", "practice:p"])
    }

    // MARK: Units and layout

    func testCompactBelowTheBreakpoint() {
        XCTAssertTrue(pathIsCompact(width: 390))
        XCTAssertTrue(pathIsCompact(width: 767))
        XCTAssertFalse(pathIsCompact(width: 768))
        XCTAssertEqual(pathColumnMaxWidth, 560)
    }

    func testUnitCompleteWhenEveryPositionIsBehindTheCursor() {
        let state = PathScreenFixtures.readyState()
        XCTAssertFalse(pathUnitComplete(state.units[0]))
        XCTAssertFalse(pathUnitComplete(state.units[1]))
        let done = PathUnit(
            unitKey: "d",
            title: "D",
            standardPositions: [PathPosition(positionIndex: 0, status: .unlocked, skills: [pathSkillFixture("a", status: .unlocked)])],
            otherSkills: []
        )
        XCTAssertTrue(pathUnitComplete(done))
        XCTAssertFalse(pathUnitComplete(PathUnit(unitKey: "e", title: "E", standardPositions: [], otherSkills: [])))
    }

    func testFindsALessonByKey() {
        let state = PathScreenFixtures.readyState()
        XCTAssertEqual(pathSkill(key: "trains", in: state.units)?.unitKey, "u2")
        XCTAssertEqual(pathSkill(key: "drinks", in: state.units)?.skillKey, "drinks")
        XCTAssertNil(pathSkill(key: "missing", in: state.units))
    }

    // MARK: Scroll target

    func testScrollTargetIsTheUnitWithTheCurrentNode() {
        let state = PathScreenFixtures.readyState()
        let config = PathTheme.standard.layoutFor(compact: true)
        let roads = state.units.map { UnitRoad(positions: $0.standardPositions, config: config, collapseForks: true) }
        let target = currentRoadTarget(roads)
        XCTAssertEqual(target?.unitIndex, 0)
        XCTAssertEqual(target?.nodeY, roads[0].currentNodeY)
        XCTAssertNotNil(roads[0].currentNodeY)
        XCTAssertNil(roads[1].currentNodeY)
    }

    func testNoScrollTargetWithoutACurrentNode() {
        XCTAssertNil(currentRoadTarget([]))
        let locked = PathPosition(positionIndex: 0, status: .locked, skills: [pathSkillFixture("a", status: .locked)])
        let road = UnitRoad(positions: [locked], config: PathTheme.standard.layoutFor(compact: true), collapseForks: true)
        XCTAssertNil(currentRoadTarget([road]))
    }

    func testScrollKeyChangesWithTheCourseContent() {
        let state = PathScreenFixtures.readyState()
        let key = pathScrollKey(course: state.course, units: state.units)
        XCTAssertEqual(key, pathScrollKey(course: state.course, units: state.units))
        XCTAssertNotEqual(key, pathScrollKey(course: state.course, units: Array(state.units.dropFirst())))
        XCTAssertNotEqual(key, pathScrollKey(course: CourseRef(code: "ja", version: 2, manifestSha256: "x"), units: state.units))
        XCTAssertEqual(pathScrollKey(course: nil, units: []), "/0//0")
    }

    func testAnchorCentresTheNodeWhenThereIsRoom() {
        // Road 600 tall in an 800 viewport, node at 300: roadTop = 400 - 300 = 100, a = 100 / 200.
        XCTAssertEqual(pathScrollAnchorFraction(viewportHeight: 800, roadHeight: 600, nodeY: 300), 0.5, accuracy: 0.0001)
        // A road taller than the viewport: node 1000 down a 2000 road centres at the middle.
        XCTAssertEqual(pathScrollAnchorFraction(viewportHeight: 800, roadHeight: 2000, nodeY: 1000), 0.5, accuracy: 0.0001)
        // Node near the top of a tall road: the road's top is the best it can do.
        XCTAssertEqual(pathScrollAnchorFraction(viewportHeight: 800, roadHeight: 2000, nodeY: 100), 0, accuracy: 0.0001)
        // Node near the bottom of a tall road.
        XCTAssertEqual(pathScrollAnchorFraction(viewportHeight: 800, roadHeight: 2000, nodeY: 1950), 1, accuracy: 0.0001)
        // Equal heights: nothing to solve.
        XCTAssertEqual(pathScrollAnchorFraction(viewportHeight: 800, roadHeight: 800, nodeY: 100), 0.5, accuracy: 0.0001)
    }

    func testAnchorSolvesRoadTopForACentredNode() {
        // The road's point at fraction a lands at the viewport's fraction a: check the top ends up viewport/2 - nodeY.
        let viewport = 800.0
        let road = 500.0
        let node = 120.0
        let a = pathScrollAnchorFraction(viewportHeight: viewport, roadHeight: road, nodeY: node)
        let roadTop = a * viewport - a * road
        XCTAssertEqual(roadTop + node, viewport / 2, accuracy: 0.0001)
    }

    // MARK: Jump button

    func testRoadOnScreenReportsTheNodeAgainstTheViewport() {
        let visible = currentRoadScroll(roadMinY: 100, roadHeight: 600, nodeY: 200, viewportHeight: 800, roadOnScreen: true)
        XCTAssertEqual(visible, .visible(nodeCentre: 300, viewportStart: 0, viewportEnd: 800))
        XCTAssertNil(jumpToCurrentDirection(visible))
        let nodeAbove = currentRoadScroll(roadMinY: -400, roadHeight: 600, nodeY: 100, viewportHeight: 800, roadOnScreen: true)
        XCTAssertEqual(jumpToCurrentDirection(nodeAbove), .up)
        let nodeBelow = currentRoadScroll(roadMinY: 700, roadHeight: 600, nodeY: 300, viewportHeight: 800, roadOnScreen: true)
        XCTAssertEqual(jumpToCurrentDirection(nodeBelow), .down)
    }

    func testRoadOffScreenPointsTheWayItIs() {
        let above = currentRoadScroll(roadMinY: -900, roadHeight: 600, nodeY: 100, viewportHeight: 800, roadOnScreen: false)
        XCTAssertEqual(above, .offscreenAbove)
        XCTAssertEqual(jumpToCurrentDirection(above), .up)
        let below = currentRoadScroll(roadMinY: 1200, roadHeight: 600, nodeY: 100, viewportHeight: 800, roadOnScreen: false)
        XCTAssertEqual(below, .offscreenBelow)
        XCTAssertEqual(jumpToCurrentDirection(below), .down)
    }

    func testStateTakesTheReportedScroll() {
        var state = PathScreenFixtures.readyState()
        XCTAssertNotNil(state.currentNode)
        state.setScroll(.offscreenBelow)
        XCTAssertEqual(state.jumpDirection, .down)
        state.setScroll(.visible(nodeCentre: 100, viewportStart: 0, viewportEnd: 800))
        XCTAssertNil(state.jumpDirection)
    }

    // MARK: Reminder gating

    func testReminderOnlyWhenDueAndTheDialogsAreClosedAndThePathIsDrawn() {
        XCTAssertTrue(stowReminderPresented(isShown: true, flowOpen: false, phase: .ready, hasGroups: true))
        XCTAssertFalse(stowReminderPresented(isShown: false, flowOpen: false, phase: .ready, hasGroups: true))
        // Never over the Stow dialogs.
        XCTAssertFalse(stowReminderPresented(isShown: true, flowOpen: true, phase: .ready, hasGroups: true))
        // Only once the path it lists is drawn.
        XCTAssertFalse(stowReminderPresented(isShown: true, flowOpen: false, phase: .loading, hasGroups: true))
        XCTAssertFalse(stowReminderPresented(isShown: true, flowOpen: false, phase: .downloading(.waiting), hasGroups: true))
        XCTAssertFalse(stowReminderPresented(isShown: true, flowOpen: false, phase: .failed, hasGroups: true))
        // Nothing to list.
        XCTAssertFalse(stowReminderPresented(isShown: true, flowOpen: false, phase: .ready, hasGroups: false))
    }
}
