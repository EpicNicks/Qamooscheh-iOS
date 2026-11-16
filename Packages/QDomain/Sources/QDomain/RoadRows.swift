// The Journey road with side lessons hung off it (stories and listening lessons): which rows a unit's road is made of
// and where every node and connector goes. Ported 1:1 from web src/domain/roadRows.ts and the row form of
// src/domain/roadLayout.ts. A unit with no side lesson lays out exactly as `computeRoadLayout` does.

/// One row of a unit's road, top to bottom.
public enum RoadRow: Equatable, Sendable {
    /// A standard position, by its index in the unit's standard positions.
    case position(Int)
    /// A side lesson hanging off the road on `side`: a junction dot on the road and a node out to one side.
    case side(PathSkill, SidePathSide)

    public var isSide: Bool {
        if case .side = self { return true }
        return false
    }
}

/// The unit's rows: each standard position, immediately followed by the side lessons anchored to it (in published
/// order); side lessons anchored before the first position come first. Only stories and listening lessons branch off;
/// conversations and songs stay in their library page. A side lesson whose anchor is past the end hangs off the last position.
public func buildRoadRows(_ unit: PathUnit) -> [RoadRow] {
    let last = unit.standardPositions.count - 1
    let sides = unit.otherSkills.filter { $0.category.branchesOffRoad }
    // No recorded Parsle before it (nil) is "before the first position" (-1), as web's anchorPositionIndex.
    func anchor(_ skill: PathSkill) -> Int { min(skill.afterPosition ?? -1, last) }
    func rows(after index: Int) -> [RoadRow] {
        sides.filter { anchor($0) == index }.map { .side($0, sidePathSide(unitKey: $0.unitKey, skillKey: $0.skillKey)) }
    }
    var result = rows(after: -1)
    for index in unit.standardPositions.indices {
        result.append(.position(index))
        result.append(contentsOf: rows(after: index))
    }
    return result
}

/// The side lane's metrics, beside the road's own `RoadLayoutConfig` (web `spurRowHeight`, `storyOffset`, `storyHalfWidth`).
public struct SideRoadConfig: Equatable, Sendable {
    /// Height of the short row a side lesson's junction sits in.
    public var spurRowHeight: Double
    /// How far a side node sits from the road's centre axis, in logical units.
    public var sideOffset: Double
    /// Half a side node's width, in logical units: the same clamp as `nodeHalfWidth`, for the side lane.
    public var sideHalfWidth: Double

    public init(spurRowHeight: Double, sideOffset: Double, sideHalfWidth: Double) {
        self.spurRowHeight = spurRowHeight
        self.sideOffset = sideOffset
        self.sideHalfWidth = sideHalfWidth
    }
}

/// What a row holds, for layout: a position's skill count, or a side lesson's side.
public enum RoadRowInput: Equatable, Sendable {
    case position(count: Int)
    case side(SidePathSide)
}

public enum RowNodeKind: Equatable, Sendable {
    case skill
    case junction
    case side
}

public struct RowNode: Equatable, Sendable {
    public var kind: RowNodeKind
    public var rowIndex: Int
    /// Index among the position rows only; nil for a junction or side node.
    public var positionIndex: Int?
    public var skillIndex: Int?
    /// In logical units.
    public var x: Double
    public var y: Double

    public init(kind: RowNodeKind, rowIndex: Int, positionIndex: Int?, skillIndex: Int?, x: Double, y: Double) {
        self.kind = kind
        self.rowIndex = rowIndex
        self.positionIndex = positionIndex
        self.skillIndex = skillIndex
        self.x = x
        self.y = y
    }
}

public struct RowEdge: Equatable, Sendable {
    /// False for a segment along the road between consecutive rows; true for the horizontal connector from a junction to its side node.
    public var isBranch: Bool
    public var fromRowIndex: Int
    public var toRowIndex: Int
    /// Nil when that end is a junction or a side node rather than a position's skill.
    public var fromPositionIndex: Int?
    public var toPositionIndex: Int?
    public var fromSkillIndex: Int?
    public var toSkillIndex: Int?
    public var x1: Double
    public var y1: Double
    public var x2: Double
    public var y2: Double
}

public struct RowsLayout: Equatable, Sendable {
    public var nodes: [RowNode]
    public var edges: [RowEdge]
    public var totalHeight: Double

    public init(nodes: [RowNode], edges: [RowEdge], totalHeight: Double) {
        self.nodes = nodes
        self.edges = edges
        self.totalHeight = totalHeight
    }
}

public func computeRowsLayout(_ rows: [RoadRowInput], config: RoadLayoutConfig, side: SideRoadConfig) -> RowsLayout {
    let centre = config.logicalWidth / 2
    func clamp(_ x: Double, _ halfWidth: Double) -> Double {
        min(config.logicalWidth - halfWidth, max(halfWidth, x))
    }

    var nodes: [RowNode] = []
    var edges: [RowEdge] = []
    // The nodes the road itself passes through on the previous row: a position's skills, or a side row's junction.
    var previous: [RowNode] = []
    var top = 0.0
    var positionIndex = 0

    func edge(_ isBranch: Bool, _ from: RowNode, _ to: RowNode) -> RowEdge {
        RowEdge(
            isBranch: isBranch, fromRowIndex: from.rowIndex, toRowIndex: to.rowIndex,
            fromPositionIndex: from.positionIndex, toPositionIndex: to.positionIndex,
            fromSkillIndex: from.skillIndex, toSkillIndex: to.skillIndex,
            x1: from.x, y1: from.y, x2: to.x, y2: to.y)
    }

    for (rowIndex, row) in rows.enumerated() {
        let height: Double
        switch row {
        case .position: height = config.rowHeight
        case .side: height = side.spurRowHeight
        }
        let y = top + height / 2
        top += height

        let onRoad: [RowNode]
        switch row {
        case .position(let count):
            let n = max(1, count)
            onRoad = (0..<n).map { skillIndex in
                RowNode(
                    kind: .skill, rowIndex: rowIndex, positionIndex: positionIndex, skillIndex: skillIndex,
                    x: n == 1 ? centre : clamp(centre + (Double(skillIndex) - Double(n - 1) / 2) * config.branchSpread, config.nodeHalfWidth),
                    y: y)
            }
            positionIndex += 1
            nodes.append(contentsOf: onRoad)
        case .side(let which):
            let junction = RowNode(kind: .junction, rowIndex: rowIndex, positionIndex: nil, skillIndex: nil, x: centre, y: y)
            let node = RowNode(
                kind: .side, rowIndex: rowIndex, positionIndex: nil, skillIndex: nil,
                x: clamp(centre + (which == .left ? -side.sideOffset : side.sideOffset), side.sideHalfWidth), y: y)
            onRoad = [junction]
            nodes.append(junction)
            nodes.append(node)
            edges.append(edge(true, junction, node))
        }

        // One straight segment per (node on the previous row) x (node on this one): 1 to 1, a fan out, a merge, N to M.
        for from in previous {
            for to in onRoad { edges.append(edge(false, from, to)) }
        }
        previous = onRoad
    }
    return RowsLayout(nodes: nodes, edges: edges, totalHeight: top)
}
