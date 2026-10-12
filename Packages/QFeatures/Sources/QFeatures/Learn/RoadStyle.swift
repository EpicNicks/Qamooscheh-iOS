import Foundation
import QDomain
import QDesign

// Pure styling and geometry for the Path road (Android SkillNode.kt nodeColors and
// SkillRoad.kt UnitRoad). Colors are 0xAARRGGBB so they test without SwiftUI.

/// Linear interpolation per channel, alpha included (Compose lerp).
public func lerpARGB(_ a: UInt32, _ b: UInt32, _ fraction: Double) -> UInt32 {
    func channel(_ shift: UInt32) -> UInt32 {
        let x = Double((a >> shift) & 0xFF)
        let y = Double((b >> shift) & 0xFF)
        let v = (x + (y - x) * fraction).rounded()
        return UInt32(min(255, max(0, v)))
    }
    return (channel(24) << 24) | (channel(16) << 16) | (channel(8) << 8) | channel(0)
}

/// The color with its alpha replaced by `alpha` (0...1).
public func withAlphaARGB(_ color: UInt32, _ alpha: Double) -> UInt32 {
    let a = UInt32(min(255, max(0, (alpha * 255).rounded())))
    return (a << 24) | (color & 0x00FFFFFF)
}

/// The colors a node draws with, by status.
public struct NodeColors: Equatable, Sendable {
    public var background: UInt32
    public var accent: UInt32
    public var title: UInt32
    public var halo: UInt32?
    public var flapLight: UInt32
    public var flapDark: UInt32

    public init(background: UInt32, accent: UInt32, title: UInt32, halo: UInt32?, flapLight: UInt32, flapDark: UInt32) {
        self.background = background
        self.accent = accent
        self.title = title
        self.halo = halo
        self.flapLight = flapLight
        self.flapDark = flapDark
    }
}

/// - Parameters:
///   - completed: a finished fork branch (blue) or, with `branch` false, a fully finished group (green).
///   - branch: whether `completed` marks one finished alternate of a fork rather than a whole group.
public func nodeColors(status: SkillStatus, palette c: AppPalette, completed: Bool = false, branch: Bool = true) -> NodeColors {
    let base: NodeColors
    switch status {
    case .locked:
        // Greyed out, not faded: a dedicated grey token at full opacity stays legible.
        base = NodeColors(
            background: c.locked, accent: c.locked, title: c.textMuted, halo: nil,
            flapLight: lerpARGB(c.locked, c.textMuted, 0.25), flapDark: lerpARGB(c.locked, c.textMuted, 0.45)
        )
    case .unlocked:
        base = NodeColors(
            background: c.surface, accent: c.primary, title: c.text, halo: nil,
            flapLight: lerpARGB(c.surface, c.primary, 0.45), flapDark: c.primary
        )
    case .current:
        base = NodeColors(
            background: lerpARGB(c.surface, c.current, 0.12), accent: c.current, title: c.text,
            halo: withAlphaARGB(c.current, 0.25),
            flapLight: lerpARGB(c.surface, c.current, 0.45), flapDark: c.current
        )
    }
    guard completed && status != .locked else { return base }
    let tint = branch ? c.current : c.primary
    var tinted = base
    tinted.accent = tint
    tinted.flapDark = tint
    tinted.flapLight = lerpARGB(c.surface, tint, 0.45)
    return tinted
}

/// The spoken status of a node (Android contentDescription suffix).
public func nodeStatusWord(status: SkillStatus, completed: Bool) -> String {
    let word: String
    switch status {
    case .locked: word = "locked"
    case .unlocked: word = "completed"
    case .current: word = "current lesson"
    }
    return completed && status != .unlocked ? "\(word), completed" : word
}

/// A road connector with its endpoints resolved against the layout's nodes.
public struct RoadEdgeGeometry: Equatable, Sendable {
    public var fromPositionIndex: Int
    public var fromSkillIndex: Int
    public var toPositionIndex: Int
    public var toSkillIndex: Int
    public var fromX: Double
    public var fromY: Double
    public var toX: Double
    public var toY: Double
}

/// Reads "M x,y L x,y" (QDomain RoadEdge.d) into four numbers.
public func parseRoadEdgePath(_ d: String) -> (fromX: Double, fromY: Double, toX: Double, toY: Double)? {
    let parts = d.split(separator: " ").map(String.init)
    guard parts.count == 4, parts[0] == "M", parts[2] == "L" else { return nil }
    let a = parts[1].split(separator: ",").compactMap { Double($0) }
    let b = parts[3].split(separator: ",").compactMap { Double($0) }
    guard a.count == 2, b.count == 2 else { return nil }
    return (a[0], a[1], b[0], b[1])
}

private func nodeSkillIndex(in layout: RoadLayout, position: Int, x: Double, y: Double) -> Int {
    let match = layout.nodes.first { $0.positionIndex == position && abs($0.x - x) < 0.001 && abs($0.y - y) < 0.001 }
    return match?.skillIndex ?? 0
}

public func roadEdgeGeometries(_ layout: RoadLayout) -> [RoadEdgeGeometry] {
    var result: [RoadEdgeGeometry] = []
    for edge in layout.edges {
        guard let p = parseRoadEdgePath(edge.d) else { continue }
        result.append(RoadEdgeGeometry(
            fromPositionIndex: edge.fromPositionIndex,
            fromSkillIndex: nodeSkillIndex(in: layout, position: edge.fromPositionIndex, x: p.fromX, y: p.fromY),
            toPositionIndex: edge.toPositionIndex,
            toSkillIndex: nodeSkillIndex(in: layout, position: edge.toPositionIndex, x: p.toX, y: p.toY),
            fromX: p.fromX, fromY: p.fromY, toX: p.toX, toY: p.toY
        ))
    }
    return result
}

/// One unit's road, laid out for a width class. Forks collapse to one node on compact screens.
public struct UnitRoad: Equatable, Sendable {
    public var positions: [PathPosition]
    public var layout: RoadLayout
    public var config: RoadLayoutConfig
    public var collapseForks: Bool

    public init(positions: [PathPosition], config: RoadLayoutConfig, collapseForks: Bool) {
        self.positions = positions
        self.config = config
        self.collapseForks = collapseForks
        self.layout = computeRoadLayout(positions.map { collapseForks ? 1 : $0.skills.count }, config: config)
    }

    /// The current position's node y, if this unit has one: what the screen scrolls to.
    public var currentNodeY: Double? {
        layout.nodes.first(where: { positions[$0.positionIndex].status == .current })?.y
    }

    public var edges: [RoadEdgeGeometry] { roadEdgeGeometries(layout) }

    /// Whether the node is a finished fork branch. A collapsed fork has no per-branch nodes.
    public func branchFinished(positionIndex: Int, skillIndex: Int) -> Bool {
        if collapseForks { return false }
        let skills = positions[positionIndex].skills
        return skills.count > 1 && skillIndex < skills.count && skills[skillIndex].completed
    }

    /// The branches an edge stands for when forks are collapsed: the group it leaves, else the one it enters.
    public func collapsedBranches(_ edge: RoadEdgeGeometry) -> [PathSkill]? {
        if !collapseForks { return nil }
        let from = positions[edge.fromPositionIndex].skills
        let to = positions[edge.toPositionIndex].skills
        if from.count > 1 { return from }
        if to.count > 1 { return to }
        return nil
    }

    /// Edges in paint order: those touching a finished branch last, so they sit over a sibling's shared end.
    public var edgesInPaintOrder: [RoadEdgeGeometry] {
        let all = edges
        func finished(_ e: RoadEdgeGeometry) -> Bool {
            return branchFinished(positionIndex: e.fromPositionIndex, skillIndex: e.fromSkillIndex)
                || branchFinished(positionIndex: e.toPositionIndex, skillIndex: e.toSkillIndex)
        }
        return all.filter { !finished($0) } + all.filter { finished($0) }
    }

    /// An edge takes its look from where it leads.
    public func edgeColor(_ edge: RoadEdgeGeometry, palette: AppPalette) -> UInt32 {
        let toStatus = positions[edge.toPositionIndex].status
        let touchesFinished = branchFinished(positionIndex: edge.fromPositionIndex, skillIndex: edge.fromSkillIndex)
            || branchFinished(positionIndex: edge.toPositionIndex, skillIndex: edge.toSkillIndex)
        if toStatus != .locked && touchesFinished { return palette.current }
        switch toStatus {
        case .locked: return palette.border
        case .unlocked: return palette.primary
        case .current: return palette.current
        }
    }

    /// Per-branch line colors for a collapsed edge, in variant order.
    public func collapsedBranchColors(_ edge: RoadEdgeGeometry, branches: [PathSkill], palette: AppPalette) -> [UInt32] {
        let leaving = positions[edge.fromPositionIndex].skills.count > 1
        let unfinished = (leaving || positions[edge.toPositionIndex].status == .locked) ? palette.border : palette.current
        return branches.map { $0.completed ? palette.primary : unfinished }
    }
}

/// A group of alternates is done when every branch is.
public func allBranchesFinished(_ position: PathPosition) -> Bool {
    return position.skills.count > 1 && position.skills.allSatisfy { $0.completed }
}

/// The group node's accessibility note, ", 2 of 3 done" (Android doneNote).
public func groupDoneNote(_ position: PathPosition) -> String {
    let done = position.skills.filter { $0.completed }.count
    return done > 0 ? ", \(done) of \(position.skills.count) done" : ""
}
