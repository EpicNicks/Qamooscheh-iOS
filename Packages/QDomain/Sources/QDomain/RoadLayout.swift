// Pure geometry for the straight, branching standard-skill road. Ported 1:1
// from web src/domain/roadLayout.ts. x is in a fixed logical width, y in points.

public struct RoadLayoutConfig: Equatable, Sendable {
    /// Vertical distance between consecutive positions.
    public var rowHeight: Double
    /// Distance between adjacent alternates at a branching position, in logical units.
    public var branchSpread: Double
    /// The coordinate space x is computed in.
    public var logicalWidth: Double
    /// Half a node's width, in logical units, so a fork spread cannot push one off the edge.
    public var nodeHalfWidth: Double

    public init(rowHeight: Double, branchSpread: Double, logicalWidth: Double, nodeHalfWidth: Double) {
        self.rowHeight = rowHeight
        self.branchSpread = branchSpread
        self.logicalWidth = logicalWidth
        self.nodeHalfWidth = nodeHalfWidth
    }
}

public struct RoadNode: Equatable, Sendable {
    public var positionIndex: Int
    public var skillIndex: Int
    /// In logical units.
    public var x: Double
    public var y: Double

    public init(positionIndex: Int, skillIndex: Int, x: Double, y: Double) {
        self.positionIndex = positionIndex
        self.skillIndex = skillIndex
        self.x = x
        self.y = y
    }
}

public struct RoadEdge: Equatable, Sendable {
    /// A straight segment from one node to the next, "M x,y L x,y".
    public var d: String
    public var fromPositionIndex: Int
    public var toPositionIndex: Int

    public init(d: String, fromPositionIndex: Int, toPositionIndex: Int) {
        self.d = d
        self.fromPositionIndex = fromPositionIndex
        self.toPositionIndex = toPositionIndex
    }
}

public struct RoadLayout: Equatable, Sendable {
    public var nodes: [RoadNode]
    public var edges: [RoadEdge]
    public var totalHeight: Double

    public init(nodes: [RoadNode], edges: [RoadEdge], totalHeight: Double) {
        self.nodes = nodes
        self.edges = edges
        self.totalHeight = totalHeight
    }
}

/// Formats like JS number-to-string for the values this layout produces:
/// whole numbers print without a fractional part.
private func formatCoordinate(_ value: Double) -> String {
    if value == value.rounded() && abs(value) < 1e15 {
        return String(Int64(value))
    }
    return String(value)
}

/// - Parameter positionSkillCounts: how many skills sit at each position, in
///   order; `[1, 2, 1]` is one skill, a two-way fork, then one skill.
public func computeRoadLayout(_ positionSkillCounts: [Int], config: RoadLayoutConfig) -> RoadLayout {
    let centre = config.logicalWidth / 2
    let topPadding = config.rowHeight / 2

    let minX = config.nodeHalfWidth
    let maxX = config.logicalWidth - config.nodeHalfWidth
    func clamp(_ x: Double) -> Double {
        return min(maxX, max(minX, x))
    }

    var nodesByPosition: [[RoadNode]] = []
    for (positionIndex, count) in positionSkillCounts.enumerated() {
        let y = topPadding + Double(positionIndex) * config.rowHeight

        if count <= 1 {
            nodesByPosition.append([RoadNode(positionIndex: positionIndex, skillIndex: 0, x: centre, y: y)])
            continue
        }

        var row: [RoadNode] = []
        for skillIndex in 0..<count {
            let offset = Double(skillIndex) - Double(count - 1) / 2
            row.append(RoadNode(
                positionIndex: positionIndex,
                skillIndex: skillIndex,
                x: clamp(centre + offset * config.branchSpread),
                y: y
            ))
        }
        nodesByPosition.append(row)
    }

    var edges: [RoadEdge] = []
    if nodesByPosition.count > 1 {
        for i in 0..<(nodesByPosition.count - 1) {
            for from in nodesByPosition[i] {
                for to in nodesByPosition[i + 1] {
                    let start = "\(formatCoordinate(from.x)),\(formatCoordinate(from.y))"
                    let end = "\(formatCoordinate(to.x)),\(formatCoordinate(to.y))"
                    edges.append(RoadEdge(
                        d: "M \(start) L \(end)",
                        fromPositionIndex: from.positionIndex,
                        toPositionIndex: to.positionIndex
                    ))
                }
            }
        }
    }

    let totalHeight: Double = positionSkillCounts.isEmpty
        ? 0
        : topPadding * 2 + Double(positionSkillCounts.count - 1) * config.rowHeight

    return RoadLayout(nodes: nodesByPosition.flatMap { $0 }, edges: edges, totalHeight: totalHeight)
}
