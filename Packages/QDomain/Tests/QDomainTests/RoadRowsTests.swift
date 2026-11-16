import XCTest
@testable import QDomain

final class RoadRowsTests: XCTestCase {
    private func std(_ key: String) -> PathSkillInput { PathSkillInput(skillKey: key, title: key, category: .standard) }
    private func side(_ key: String, _ category: SkillCategory, after: Int?) -> PathSkillInput {
        PathSkillInput(skillKey: key, title: key, category: category, afterPosition: after)
    }

    private func unit(positions: [[PathSkillInput]], others: [PathSkillInput]) -> PathUnit {
        computePathProgress(
            [PathUnitInput(unitKey: "u", title: "U", standardPositions: positions.map { PathPositionInput(skills: $0) }, otherSkills: others)],
            position: PositionKey(unitKey: "u", skillKey: "a"))[0]
    }

    private func summary(_ unit: PathUnit) -> [String] {
        buildRoadRows(unit).map {
            switch $0 {
            case .position(let i): return "p\(i)"
            case .side(let skill, _): return "s:\(skill.skillKey)"
            }
        }
    }

    func testAUnitWithNoSideLessonsIsJustItsPositions() {
        let u = unit(positions: [[std("a")], [std("b1"), std("b2")], [std("c")]], others: [])
        XCTAssertEqual(summary(u), ["p0", "p1", "p2"])
    }

    func testASideLessonSitsRightAfterThePositionItFollowsAndOneBeforeTheFirstGoesFirst() {
        let u = unit(
            positions: [[std("a")], [std("b")], [std("c")]],
            others: [side("early", .story, after: nil), side("mid", .listening, after: 1)])
        XCTAssertEqual(summary(u), ["s:early", "p0", "p1", "s:mid", "p2"])
    }

    func testTrailingSideLessonsHangOffTheLastPositionInPublishedOrder() {
        let u = unit(
            positions: [[std("a")], [std("review")]],
            others: [side("l1", .listening, after: 1), side("s1", .story, after: 1), side("l2", .listening, after: 1)])
        XCTAssertEqual(summary(u), ["p0", "p1", "s:l1", "s:s1", "s:l2"])
    }

    func testAnAnchorPastTheEndHangsOffTheLastPosition() {
        let u = unit(positions: [[std("a")], [std("b")]], others: [side("late", .story, after: 9)])
        XCTAssertEqual(summary(u), ["p0", "p1", "s:late"])
    }

    func testOnlyStoriesAndListeningBranchOff() {
        let u = unit(
            positions: [[std("a")]],
            others: [side("conv", .conversation, after: 0), side("song", .song, after: 0), side("st", .story, after: 0)])
        XCTAssertEqual(summary(u), ["p0", "s:st"])
    }

    func testTheRowCarriesTheStableSide() {
        let u = unit(positions: [[std("a")]], others: [side("l1", .listening, after: 0)])
        guard case .side(_, let side) = buildRoadRows(u)[1] else { return XCTFail("expected a side row") }
        XCTAssertEqual(side, sidePathSide(unitKey: "u", skillKey: "l1"))
    }

    // MARK: Layout

    private let config = RoadLayoutConfig(rowHeight: 190, branchSpread: 110, logicalWidth: 320, nodeHalfWidth: 50)
    private let lane = SideRoadConfig(spurRowHeight: 130, sideOffset: 110, sideHalfWidth: 42)

    func testWithoutSideRowsItLaysOutLikeTheBareRoad() {
        let counts = [1, 2, 1]
        let bare = computeRoadLayout(counts, config: config)
        let rows = computeRowsLayout(counts.map { .position(count: $0) }, config: config, side: lane)
        XCTAssertEqual(rows.totalHeight, bare.totalHeight)
        XCTAssertEqual(rows.nodes.map { [$0.x, $0.y] }, bare.nodes.map { [$0.x, $0.y] })
        XCTAssertEqual(rows.edges.count, bare.edges.count)
    }

    func testASideRowGetsAShortRowAJunctionAndABranch() {
        let layout = computeRowsLayout([.position(count: 1), .side(.left), .position(count: 1)], config: config, side: lane)
        XCTAssertEqual(layout.totalHeight, 190 + 130 + 190)
        let kinds = layout.nodes.map { $0.kind }
        XCTAssertEqual(kinds, [.skill, .junction, .side, .skill])
        let junction = layout.nodes[1]
        let node = layout.nodes[2]
        XCTAssertEqual([junction.x, junction.y], [160, 255])
        // 160 - 110 = 50, inside the side lane's clamp of 42.
        XCTAssertEqual([node.x, node.y], [50, 255])
        XCTAssertEqual(layout.nodes[3].y, 415)
        // The road passes through the junction, never through the side node.
        // The branch is listed before the road edge into the junction, as web's layout does.
        XCTAssertEqual(layout.edges.map { $0.isBranch }, [true, false, false])
        XCTAssertEqual(layout.edges[1].fromPositionIndex, 0)
        XCTAssertNil(layout.edges[1].toPositionIndex)
        XCTAssertNil(layout.edges[2].fromPositionIndex)
        XCTAssertEqual(layout.edges[2].toPositionIndex, 1)
    }

    func testARightSideNodeSitsMirroredAndIsClamped() {
        let right = computeRowsLayout([.side(.right)], config: config, side: lane)
        XCTAssertEqual(right.nodes[1].x, 270)
        let wide = SideRoadConfig(spurRowHeight: 130, sideOffset: 400, sideHalfWidth: 42)
        let clamped = computeRowsLayout([.side(.right), .side(.left)], config: config, side: wide)
        XCTAssertEqual(clamped.nodes.filter { $0.kind == .side }.map { $0.x }, [278, 42])
    }

    func testPositionIndexCountsPositionRowsOnly() {
        let layout = computeRowsLayout([.side(.left), .position(count: 2), .side(.right), .position(count: 1)], config: config, side: lane)
        XCTAssertEqual(layout.nodes.compactMap { $0.positionIndex }, [0, 0, 1])
    }
}
