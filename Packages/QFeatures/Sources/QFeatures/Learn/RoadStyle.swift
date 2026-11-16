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

/// Mirrors an x across the road's width in a right-to-left layout; edges and nodes share this.
public func roadMirroredX(_ x: Double, width: Double, rtl: Bool) -> Double {
    return rtl ? width - x : x
}

/// The fold depth of a node corner: deeper while pressed, never on a locked node.
public func nodeFoldDepth(pressed: Bool, locked: Bool) -> Double {
    return pressed && !locked ? 26 : 18
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

/// How a road line is drawn: grey ahead of the cursor or locked, blue while open, green once walked or done.
public enum RoadLineTone: Equatable, Sendable {
    case locked
    case open
    case done

    public func argb(palette: AppPalette) -> UInt32 {
        switch self {
        case .locked: return palette.border
        case .open: return palette.current
        case .done: return palette.primary
        }
    }

    init(status: SkillStatus) {
        switch status {
        case .locked: self = .locked
        case .unlocked: self = .done
        case .current: self = .open
        }
    }
}

/// A side lesson's node on the road: where it is drawn, and whether it can be opened yet.
public struct SideNodeGeometry: Equatable, Sendable {
    public var skill: PathSkill
    public var side: SidePathSide
    public var x: Double
    public var y: Double
    public var locked: Bool
}

/// A road line that touches a junction (or leads out to a side node), with its tone resolved.
public struct SideEdgeGeometry: Equatable, Sendable {
    public var fromX: Double
    public var fromY: Double
    public var toX: Double
    public var toY: Double
    public var tone: RoadLineTone
    /// The horizontal connector out to a side node, as against a stretch of the road itself.
    public var isBranch: Bool
}

/// A junction dot on the road, where a side lesson branches off.
public struct JunctionGeometry: Equatable, Sendable {
    public var skillKey: String
    public var x: Double
    public var y: Double
    public var tone: RoadLineTone
}

/// One unit's road, laid out for a width class. Forks collapse to one node on compact screens.
/// With side lessons (stories, listening) the rows carry short junction rows between positions; `layout` then holds
/// the position nodes at their shifted y and the stretches of road between two positions, while the stretches that
/// touch a junction, the junction dots and the side nodes are in `sideEdges`, `junctions` and `sideNodes`.
public struct UnitRoad: Equatable, Sendable {
    public var positions: [PathPosition]
    public var layout: RoadLayout
    public var config: RoadLayoutConfig
    public var collapseForks: Bool
    public var rows: [RoadRow]
    public private(set) var sideNodes: [SideNodeGeometry] = []
    public private(set) var junctions: [JunctionGeometry] = []
    public private(set) var sideEdges: [SideEdgeGeometry] = []

    /// - Parameter lockedSideKeys: the skill keys of side lessons still locked (see `sidePathLocked`).
    public init(
        positions: [PathPosition], config: RoadLayoutConfig, collapseForks: Bool,
        rows: [RoadRow]? = nil, sideLane: SideRoadConfig = PathTheme.standard.sideLane, lockedSideKeys: Set<String> = []
    ) {
        self.positions = positions
        self.config = config
        self.collapseForks = collapseForks
        let rows = rows ?? positions.indices.map { RoadRow.position($0) }
        self.rows = rows
        if !rows.contains(where: { $0.isSide }) {
            self.layout = computeRoadLayout(positions.map { collapseForks ? 1 : $0.skills.count }, config: config)
            return
        }
        let inputs: [RoadRowInput] = rows.map { row in
            switch row {
            case .position(let index): return .position(count: collapseForks ? 1 : positions[index].skills.count)
            case .side(_, let side): return .side(side)
            }
        }
        let laid = computeRowsLayout(inputs, config: config, side: sideLane)
        // The position-to-position stretches keep the bare road's edge handling (forks, finished branches).
        var roadEdges: [RoadEdge] = []
        for e in laid.edges where !e.isBranch {
            guard let from = e.fromPositionIndex, let to = e.toPositionIndex else { continue }
            roadEdges.append(RoadEdge(d: "M \(e.x1),\(e.y1) L \(e.x2),\(e.y2)", fromPositionIndex: from, toPositionIndex: to))
        }
        self.layout = RoadLayout(
            nodes: laid.nodes.compactMap { n -> RoadNode? in
                guard n.kind == .skill, let p = n.positionIndex, let s = n.skillIndex else { return nil }
                return RoadNode(positionIndex: p, skillIndex: s, x: n.x, y: n.y)
            },
            edges: roadEdges, totalHeight: laid.totalHeight)

        // What a stretch of road looks like where it leads: the next position's status, or the side lesson's own state at the road's end.
        func sideTone(_ skill: PathSkill) -> RoadLineTone {
            if lockedSideKeys.contains(skill.skillKey) { return .locked }
            return skill.completed ? .done : .open
        }
        func throughTone(junctionRow: Int) -> RoadLineTone {
            for row in rows[(junctionRow + 1)...] {
                if case .position(let index) = row { return RoadLineTone(status: positions[index].status) }
            }
            if case .side(let skill, _) = rows[junctionRow] { return sideTone(skill) }
            return .locked
        }
        for node in laid.nodes {
            guard case .side(let skill, let side) = rows[node.rowIndex] else { continue }
            switch node.kind {
            case .junction:
                junctions.append(JunctionGeometry(skillKey: skill.skillKey, x: node.x, y: node.y, tone: throughTone(junctionRow: node.rowIndex)))
            case .side:
                sideNodes.append(SideNodeGeometry(skill: skill, side: side, x: node.x, y: node.y, locked: lockedSideKeys.contains(skill.skillKey)))
            case .skill:
                break
            }
        }
        for e in laid.edges {
            if !e.isBranch && e.fromPositionIndex != nil && e.toPositionIndex != nil { continue }
            let tone: RoadLineTone
            if e.isBranch {
                guard case .side(let skill, _) = rows[e.toRowIndex] else { continue }
                tone = sideTone(skill)
            } else if let to = e.toPositionIndex {
                tone = RoadLineTone(status: positions[to].status)
            } else {
                tone = throughTone(junctionRow: e.toRowIndex)
            }
            sideEdges.append(SideEdgeGeometry(fromX: e.x1, fromY: e.y1, toX: e.x2, toY: e.y2, tone: tone, isBranch: e.isBranch))
        }
    }

    /// A unit's road with its side lessons hung off it.
    public init(unit: PathUnit, config: RoadLayoutConfig, collapseForks: Bool, sideLane: SideRoadConfig = PathTheme.standard.sideLane) {
        let locked = Set(unit.otherSkills.filter { sidePathLocked($0, in: unit) }.map { $0.skillKey })
        self.init(
            positions: unit.standardPositions, config: config, collapseForks: collapseForks,
            rows: buildRoadRows(unit), sideLane: sideLane, lockedSideKeys: locked)
    }

    /// Whether any side lesson hangs off this road.
    public var hasSides: Bool { !sideNodes.isEmpty }

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

/// The colors a side lesson's round node draws with: grey while locked, a blue border while open and still to do,
/// the walked-road green border once done (web SkillNode "story" layout).
public func sideNodeColors(locked: Bool, completed: Bool, palette c: AppPalette) -> NodeColors {
    if locked { return nodeColors(status: .locked, palette: c) }
    var colors = nodeColors(status: .unlocked, palette: c)
    if !completed {
        colors.accent = c.current
        colors.flapDark = c.current
        colors.flapLight = lerpARGB(c.surface, c.current, 0.45)
    }
    return colors
}

/// The spoken label of a side node (web: "Story: title, done" / "Listening: title, locked").
public func sideNodeLabel(_ skill: PathSkill, locked: Bool) -> String {
    let kind = skill.category == .listening ? "Listening" : "Story"
    let state = skill.completed ? ", done" : (locked ? ", locked" : "")
    return "\(kind): \(skill.title)\(state)"
}
