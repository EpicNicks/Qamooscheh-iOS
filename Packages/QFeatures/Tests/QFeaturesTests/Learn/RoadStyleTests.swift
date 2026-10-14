import XCTest
import QDomain
import QDesign
@testable import QFeatures

final class RoadStyleTests: XCTestCase {
    private let light = AppPalette.light

    func testLerpEndpointsAndMidpoint() {
        XCTAssertEqual(lerpARGB(0xFF000000, 0xFFFFFFFF, 0), 0xFF000000)
        XCTAssertEqual(lerpARGB(0xFF000000, 0xFFFFFFFF, 1), 0xFFFFFFFF)
        XCTAssertEqual(lerpARGB(0xFF000000, 0xFFFFFFFF, 0.5), 0xFF808080)
    }

    func testHaloIsCurrentAtQuarterAlpha() {
        let colors = nodeColors(status: .current, palette: light)
        XCTAssertEqual(colors.halo, 0x401CB0F6)
        XCTAssertEqual(colors.accent, light.current)
    }

    func testLockedHasNoHaloAndIgnoresCompleted() {
        let plain = nodeColors(status: .locked, palette: light)
        XCTAssertNil(plain.halo)
        XCTAssertEqual(plain.background, light.locked)
        XCTAssertEqual(nodeColors(status: .locked, palette: light, completed: true), plain)
    }

    func testCompletedBranchIsBlueAndGroupIsGreen() {
        XCTAssertEqual(nodeColors(status: .unlocked, palette: light, completed: true, branch: true).accent, light.current)
        XCTAssertEqual(nodeColors(status: .unlocked, palette: light, completed: true, branch: false).accent, light.primary)
        XCTAssertEqual(nodeColors(status: .unlocked, palette: light).accent, light.primary)
    }

    func testStatusWords() {
        XCTAssertEqual(nodeStatusWord(status: .locked, completed: false), "locked")
        XCTAssertEqual(nodeStatusWord(status: .unlocked, completed: true), "completed")
        XCTAssertEqual(nodeStatusWord(status: .current, completed: true), "current lesson, completed")
    }

    func testParseEdgePath() {
        let p = parseRoadEdgePath("M 160,95 L 105.5,285")
        XCTAssertEqual(p?.fromX, 160)
        XCTAssertEqual(p?.toX, 105.5)
        XCTAssertEqual(p?.toY, 285)
        XCTAssertNil(parseRoadEdgePath("garbage"))
    }

    func testEdgesResolveSkillIndices() {
        let road = UnitRoad(positions: PathRoadFixtures.positions(), config: PathTheme.standard.layout, collapseForks: false)
        let edges = road.edges
        XCTAssertEqual(edges.count, road.layout.edges.count)
        let intoFork = edges.filter { $0.fromPositionIndex == 0 && $0.toPositionIndex == 1 }
        XCTAssertEqual(intoFork.map { $0.toSkillIndex }, [0, 1])
    }

    func testFinishedBranchOnlyWhenForkedAndNotCollapsed() {
        let open = UnitRoad(positions: PathRoadFixtures.positions(), config: PathTheme.standard.layout, collapseForks: false)
        XCTAssertTrue(open.branchFinished(positionIndex: 1, skillIndex: 0))
        XCTAssertFalse(open.branchFinished(positionIndex: 1, skillIndex: 1))
        XCTAssertFalse(open.branchFinished(positionIndex: 0, skillIndex: 0))
        let compact = UnitRoad(positions: PathRoadFixtures.positions(), config: PathTheme.standard.compactLayout!, collapseForks: true)
        XCTAssertFalse(compact.branchFinished(positionIndex: 1, skillIndex: 0))
    }

    func testCollapsedRoadHasOneNodePerPositionAndGroupBranches() {
        let road = PathRoadFixtures.road(compact: true)
        XCTAssertEqual(road.layout.nodes.count, 5)
        let leaving = road.edges.first { $0.fromPositionIndex == 1 }!
        XCTAssertEqual(road.collapsedBranches(leaving)?.count, 2)
        let plain = road.edges.first { $0.fromPositionIndex == 0 }
        XCTAssertEqual(plain.flatMap { road.collapsedBranches($0) }?.count, 2)
        XCTAssertNil(UnitRoad(positions: PathRoadFixtures.positions(), config: PathTheme.standard.layout, collapseForks: false).collapsedBranches(leaving))
    }

    func testEdgeColorFollowsDestination() {
        let road = UnitRoad(positions: PathRoadFixtures.positions(), config: PathTheme.standard.layout, collapseForks: false)
        let toCurrent = road.edges.first { $0.toPositionIndex == 2 && $0.fromSkillIndex == 1 }!
        XCTAssertEqual(road.edgeColor(toCurrent, palette: light), light.current)
        let toLocked = road.edges.first { $0.toPositionIndex == 4 }!
        XCTAssertEqual(road.edgeColor(toLocked, palette: light), light.border)
        let toFinishedBranch = road.edges.first { $0.toPositionIndex == 1 && $0.toSkillIndex == 0 }!
        XCTAssertEqual(road.edgeColor(toFinishedBranch, palette: light), light.current)
        let toOpenBranch = road.edges.first { $0.toPositionIndex == 1 && $0.toSkillIndex == 1 }!
        XCTAssertEqual(road.edgeColor(toOpenBranch, palette: light), light.primary)
    }

    func testPaintOrderPutsFinishedBranchEdgesLast() {
        let road = UnitRoad(positions: PathRoadFixtures.positions(), config: PathTheme.standard.layout, collapseForks: false)
        let ordered = road.edgesInPaintOrder
        XCTAssertEqual(ordered.count, road.edges.count)
        let last = ordered.last!
        XCTAssertTrue(road.branchFinished(positionIndex: last.fromPositionIndex, skillIndex: last.fromSkillIndex)
            || road.branchFinished(positionIndex: last.toPositionIndex, skillIndex: last.toSkillIndex))
    }

    func testCollapsedBranchColors() {
        let road = PathRoadFixtures.road(compact: true)
        let into = road.edges.first { $0.toPositionIndex == 1 }!
        let branches = road.collapsedBranches(into)!
        XCTAssertEqual(road.collapsedBranchColors(into, branches: branches, palette: light), [light.primary, light.current])
        let leavingLocked = road.edges.first { $0.fromPositionIndex == 3 }!
        let lockedBranches = road.collapsedBranches(leavingLocked)!
        XCTAssertEqual(road.collapsedBranchColors(leavingLocked, branches: lockedBranches, palette: light), [light.border, light.border])
    }

    func testGroupHelpers() {
        let fork = PathRoadFixtures.positions()[1]
        XCTAssertFalse(allBranchesFinished(fork))
        XCTAssertEqual(groupDoneNote(fork), ", 1 of 2 done")
        XCTAssertEqual(groupDoneNote(PathRoadFixtures.positions()[3]), "")
        XCTAssertFalse(allBranchesFinished(PathRoadFixtures.positions()[0]))
    }

    func testCurrentNodeY() {
        let road = PathRoadFixtures.road(compact: true)
        XCTAssertEqual(road.currentNodeY, 75 + 2 * 150)
    }

    func testThemeLayoutSelection() {
        XCTAssertEqual(PathTheme.standard.layoutFor(compact: true).rowHeight, 150)
        XCTAssertEqual(PathTheme.standard.layoutFor(compact: false).rowHeight, 190)
    }

    func testRoadMirroredX() {
        XCTAssertEqual(roadMirroredX(100, width: 360, rtl: false), 100)
        XCTAssertEqual(roadMirroredX(100, width: 360, rtl: true), 260)
        XCTAssertEqual(roadMirroredX(180, width: 360, rtl: true), 180)
    }

    func testRoadEdgesMirrorLikeNodes() {
        let road = PathRoadFixtures.road(compact: true)
        let width = 360.0
        let scale = width / road.config.logicalWidth
        for edge in road.edges {
            let node = road.layout.nodes.first { $0.positionIndex == edge.fromPositionIndex && $0.skillIndex == edge.fromSkillIndex }!
            XCTAssertEqual(
                roadMirroredX(edge.fromX * scale, width: width, rtl: true),
                roadMirroredX(node.x * scale, width: width, rtl: true),
                accuracy: 0.001
            )
        }
    }

    func testNodeFoldDepth() {
        XCTAssertEqual(nodeFoldDepth(pressed: false, locked: false), 18)
        XCTAssertEqual(nodeFoldDepth(pressed: true, locked: false), 26)
        XCTAssertEqual(nodeFoldDepth(pressed: true, locked: true), 18)
    }
}
