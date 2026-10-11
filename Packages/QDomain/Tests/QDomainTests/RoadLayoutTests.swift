import XCTest
@testable import QDomain

final class RoadLayoutTests: XCTestCase {
    private let config = RoadLayoutConfig(rowHeight: 190, branchSpread: 110, logicalWidth: 320, nodeHalfWidth: 42)

    func testCentresASingletonPositionOnHalfLogicalWidth() {
        let layout = computeRoadLayout([1], config: config)
        XCTAssertEqual(layout.nodes, [RoadNode(positionIndex: 0, skillIndex: 0, x: 160, y: 95)])
    }

    func testSpreadsAForksAlternatesSymmetricallyAboutTheCentre() {
        let layout = computeRoadLayout([3], config: config)
        let xs = layout.nodes.map { $0.x }
        XCTAssertEqual(xs[1], 160)
        XCTAssertEqual(160 - xs[0], xs[2] - 160, accuracy: 0.0001)
        XCTAssertEqual(xs[2] - xs[0], config.branchSpread * 2, accuracy: 0.0001)
    }

    func testClampsOuterNodesSoTheyCannotOverhangTheViewBox() {
        let wide = RoadLayoutConfig(rowHeight: 190, branchSpread: 300, logicalWidth: 320, nodeHalfWidth: 120)
        let layout = computeRoadLayout([2], config: wide)
        let xs = layout.nodes.map { $0.x }.sorted()
        XCTAssertEqual(xs, [120, 200])
    }

    func testProducesTotalHeightForZeroOneAndNPositions() {
        XCTAssertEqual(computeRoadLayout([], config: config).totalHeight, 0)
        XCTAssertEqual(computeRoadLayout([1], config: config).totalHeight, config.rowHeight)
        XCTAssertEqual(
            computeRoadLayout([1, 1, 1], config: config).totalHeight,
            config.rowHeight + 2 * config.rowHeight
        )
    }

    func testDrawsOneEdgePerPairOfAdjacentPositionSkills() {
        let layout = computeRoadLayout([1, 2, 1], config: config)
        XCTAssertEqual(layout.edges.count, 4)
    }

    func testCollapsingEveryCountToOneReducesEdgeCountToNMinusOne() {
        let collapsed = computeRoadLayout([1, 1, 1, 1], config: config)
        XCTAssertEqual(collapsed.edges.count, 3)
    }

    func testEdgePathIsAStraightSegmentBetweenNodes() {
        let layout = computeRoadLayout([1, 1], config: config)
        XCTAssertEqual(layout.edges.first?.d, "M 160,95 L 160,285")
    }
}
