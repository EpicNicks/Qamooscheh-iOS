import XCTest
import QDomain
import QDesign
@testable import QFeatures

private func std(_ key: String) -> PathSkillInput { PathSkillInput(skillKey: key, title: key, category: .standard) }
private func side(_ key: String, _ category: QDomain.SkillCategory, after: Int?) -> PathSkillInput {
    PathSkillInput(skillKey: key, title: key, category: category, afterPosition: after)
}

private func unit(cursor: String, completed: Set<String> = [], others: [PathSkillInput]) -> PathUnit {
    computePathProgress(
        [PathUnitInput(
            unitKey: "u", title: "U",
            standardPositions: [PathPositionInput(skills: [std("a")]), PathPositionInput(skills: [std("b")]), PathPositionInput(skills: [std("review")])],
            otherSkills: others)],
        position: PositionKey(unitKey: "u", skillKey: cursor), completedSkillKeys: completed)[0]
}

final class SideRoadTests: XCTestCase {
    private let light = AppPalette.light
    private let config = PathTheme.standard.layout
    private let lane = PathTheme.standard.sideLane

    func testAUnitWithoutSideLessonsDrawsExactlyAsBefore() {
        let u = unit(cursor: "a", others: [side("conv", .conversation, after: 2)])
        let road = UnitRoad(unit: u, config: config, collapseForks: false, sideLane: lane)
        let bare = UnitRoad(positions: u.standardPositions, config: config, collapseForks: false)
        XCTAssertFalse(road.hasSides)
        XCTAssertEqual(road.layout, bare.layout)
        XCTAssertTrue(road.sideEdges.isEmpty)
        XCTAssertTrue(road.junctions.isEmpty)
    }

    func testASideLessonAddsAShortRowAndShiftsTheRoadBelowIt() {
        let u = unit(cursor: "a", others: [side("l1", .listening, after: 0)])
        let road = UnitRoad(unit: u, config: config, collapseForks: false, sideLane: lane)
        XCTAssertTrue(road.hasSides)
        // Position 0 at 95, the spur row 190..320 (centre 255), then positions 1 and 2 below.
        XCTAssertEqual(road.layout.nodes.map { $0.y }, [95, 415, 605])
        XCTAssertEqual(road.layout.totalHeight, 190 * 3 + 130)
        XCTAssertEqual(road.junctions.map { [$0.x, $0.y] }, [[160, 255]])
        XCTAssertEqual(road.sideNodes.count, 1)
        XCTAssertEqual(road.sideNodes[0].y, 255)
        XCTAssertEqual(road.sideNodes[0].side, sidePathSide(unitKey: "u", skillKey: "l1"))
        // The road passes through the junction: p0 to junction, junction to p1, plus the branch out. p1 to p2 is a plain stretch.
        XCTAssertEqual(road.sideEdges.count, 3)
        XCTAssertEqual(road.sideEdges.filter { $0.isBranch }.count, 1)
        XCTAssertEqual(road.edges.map { [$0.fromPositionIndex, $0.toPositionIndex] }, [[1, 2]])
    }

    func testTheCurrentNodeYFollowsTheShiftedRoad() {
        let u = unit(cursor: "b", others: [side("l1", .listening, after: 0)])
        let road = UnitRoad(unit: u, config: config, collapseForks: false, sideLane: lane)
        XCTAssertEqual(road.currentNodeY, 415)
    }

    func testLockedUntilItsParsleIsPassedAndTheLineToneSaysSo() {
        // The cursor is on position 1; l0 follows position 0 (passed), l2 follows position 2 (ahead).
        let u = unit(cursor: "b", others: [side("l0", .listening, after: 0), side("l2", .listening, after: 2)])
        let road = UnitRoad(unit: u, config: config, collapseForks: false, sideLane: lane)
        XCTAssertEqual(road.sideNodes.map { [$0.skill.skillKey, $0.locked ? "locked" : "open"] }, [["l0", "open"], ["l2", "locked"]])
        let branches = road.sideEdges.filter { $0.isBranch }
        XCTAssertEqual(branches.map { $0.tone }, [.open, .locked])
    }

    func testADoneSideLessonRunsGreen() {
        let u = unit(cursor: "b", completed: ["l0"], others: [side("l0", .story, after: 0)])
        let road = UnitRoad(unit: u, config: config, collapseForks: false, sideLane: lane)
        XCTAssertEqual(road.sideEdges.first { $0.isBranch }?.tone, .done)
    }

    func testRoadThroughAJunctionTakesTheLookOfWhereItLeads() {
        // l0 follows position 0 (passed), the cursor is on position 1: the road into the junction leads on to position 1 (current).
        let u = unit(cursor: "b", others: [side("l0", .listening, after: 0)])
        let road = UnitRoad(unit: u, config: config, collapseForks: false, sideLane: lane)
        let through = road.sideEdges.filter { !$0.isBranch }
        XCTAssertEqual(through.map { $0.tone }, [.open, .open])
        XCTAssertEqual(road.junctions.map { $0.tone }, [.open])
    }

    func testATrailingSideLessonAtTheRoadsEndTakesItsOwnState() {
        // After the last Parsle there is no next position: the junction and the road into it take the lesson's state.
        let locked = unit(cursor: "a", others: [side("end", .listening, after: 2)])
        let road = UnitRoad(unit: locked, config: config, collapseForks: false, sideLane: lane)
        XCTAssertEqual(road.junctions.map { $0.tone }, [.locked])
        let done = unit(cursor: "review", completed: ["review", "end"], others: [side("end", .listening, after: 2)])
        let finished = UnitRoad(unit: done, config: config, collapseForks: false, sideLane: lane)
        XCTAssertEqual(finished.junctions.map { $0.tone }, [.done])
    }

    func testCollapsedForksStillGetOneNodePerPositionBesideSideLessons() {
        let forked = computePathProgress(
            [PathUnitInput(
                unitKey: "u", title: "U",
                standardPositions: [PathPositionInput(skills: [std("a1"), std("a2")]), PathPositionInput(skills: [std("b")])],
                otherSkills: [side("l", .listening, after: 0)])],
            position: PositionKey(unitKey: "u", skillKey: "a1"))[0]
        let compact = UnitRoad(unit: forked, config: PathTheme.standard.layoutFor(compact: true), collapseForks: true, sideLane: PathTheme.standard.sideLaneFor(compact: true))
        XCTAssertEqual(compact.layout.nodes.count, 2)
        let wide = UnitRoad(unit: forked, config: config, collapseForks: false, sideLane: lane)
        XCTAssertEqual(wide.layout.nodes.count, 3)
    }

    func testTheThemePicksTheCompactLaneOnPhones() {
        XCTAssertEqual(PathTheme.standard.sideLaneFor(compact: true).spurRowHeight, 108)
        XCTAssertEqual(PathTheme.standard.sideLaneFor(compact: false).spurRowHeight, 130)
        // The lane clears the road's own card: the side node's centre is further out than both half widths.
        XCTAssertGreaterThan(lane.sideOffset, config.nodeHalfWidth + lane.sideHalfWidth)
        XCTAssertEqual(PathTheme.standard.icons[.listening], "\u{1F3A7}")
    }

    func testSideNodeColorsAndLabels() {
        XCTAssertEqual(sideNodeColors(locked: true, completed: false, palette: light), nodeColors(status: .locked, palette: light))
        XCTAssertEqual(sideNodeColors(locked: false, completed: false, palette: light).accent, light.current)
        XCTAssertEqual(sideNodeColors(locked: false, completed: true, palette: light).accent, light.primary)
        let l = PathSkill(skillKey: "l", title: "Cafe", category: .listening, arc: nil, unitKey: "u", status: .unlocked, completed: false, positionIndex: nil)
        var s = l
        s.category = .story
        XCTAssertEqual(sideNodeLabel(l, locked: true), "Listening: Cafe, locked")
        XCTAssertEqual(sideNodeLabel(l, locked: false), "Listening: Cafe")
        s.completed = true
        XCTAssertEqual(sideNodeLabel(s, locked: false), "Story: Cafe, done")
    }
}

private final class RecordingNavigator: PathNavigator {
    var calls: [String] = []
    func startLesson(_ skill: PathSkill) { calls.append("start:\(skill.skillKey)") }
    func practice(_ skill: PathSkill) { calls.append("practice:\(skill.skillKey)") }
    func retryStowed(_ skill: PathSkill) { calls.append("retry:\(skill.skillKey)") }
    func checkpoint(_ target: PositionKey) { calls.append("checkpoint") }
    func reviewVocabulary(_ skill: PathSkill) { calls.append("vocab") }
    func reviewUnitVocabulary(unitKey: String) { calls.append("unitVocab") }
    func deepDiveRemix(lessonKey: String) { calls.append("deepDive") }
    func openTheme(themeId: String, fromLessonKey: String) { calls.append("theme") }
}

final class SideTapTests: XCTestCase {
    private func skill(_ key: String, _ category: QDomain.SkillCategory, completed: Bool = false) -> PathSkill {
        PathSkill(skillKey: key, title: key, category: category, arc: nil, unitKey: "u", status: .unlocked, completed: completed, positionIndex: nil)
    }

    func testTapActionByState() {
        XCTAssertNil(pathSideTapAction(skill("l", .listening), locked: true))
        XCTAssertEqual(pathSideTapAction(skill("l", .listening), locked: false), .startLesson)
        XCTAssertEqual(pathSideTapAction(skill("l", .listening, completed: true), locked: false), .practice)
    }

    func testOpenSideGoesThroughTheNavigator() {
        let nav = RecordingNavigator()
        nav.openSide(skill("l", .listening), locked: true)
        XCTAssertTrue(nav.calls.isEmpty)
        nav.openSide(skill("l", .listening), locked: false)
        nav.openSide(skill("s", .story, completed: true), locked: false)
        XCTAssertEqual(nav.calls, ["start:l", "practice:s"])
    }
}
