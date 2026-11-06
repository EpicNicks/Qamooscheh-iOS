// What the Journey plays once, after a graded lesson completes and the learner returns to the path:
// the newly completed edges draw in order, then the newly unlocked position plays its unlock.
// Pure: computed from a before/after snapshot of `computePathProgress`. Shared model with Android/web
// (Qamooscheh-Android #133). Nothing here is persisted; the caller plays it once and drops it.

public struct JourneyEdge: Equatable, Hashable, Sendable {
    public var from: String
    public var to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

public struct JourneyTransition: Equatable, Sendable {
    public var completedSkillKey: String
    /// In draw order, within one unit (never across a unit boundary). At a fork, one per completed branch
    /// node and next-position node.
    public var edges: [JourneyEdge]
    /// The skills of the newly current position (several when it is a fork); empty at the end of the course.
    public var unlockedSkillKeys: [String]

    public init(completedSkillKey: String, edges: [JourneyEdge], unlockedSkillKeys: [String]) {
        self.completedSkillKey = completedSkillKey
        self.edges = edges
        self.unlockedSkillKeys = unlockedSkillKeys
    }
}

/// The renderer behind the transition, so a richer one (Rive) can replace the default later.
@MainActor
public protocol JourneyAnimator {
    func drawEdges(_ edges: [JourneyEdge]) async
    func playUnlock(_ skillKeys: [String]) async
}

/// Plays `transition` in order, or applies the end state at once (no animation) under reduce-motion.
@MainActor
public func playJourneyTransition(_ transition: JourneyTransition, animator: JourneyAnimator, reduceMotion: Bool) async {
    if reduceMotion { return }
    if !transition.edges.isEmpty { await animator.drawEdges(transition.edges) }
    if !transition.unlockedSkillKeys.isEmpty { await animator.playUnlock(transition.unlockedSkillKeys) }
}

private func flatPositions(_ path: [PathUnit]) -> [PathPosition] {
    path.flatMap { $0.standardPositions }
}

/// The transition for finishing `completedSkillKey`, or nil when there is nothing to animate: the lesson was
/// not newly completed (a replay), it was not at the cursor (practice, a passed-over fork alternate), or
/// the cursor did not move.
public func diffPathProgress(before: [PathUnit], after: [PathUnit], completedSkillKey: String) -> JourneyTransition? {
    let was = flatPositions(before)
    let now = flatPositions(after)
    guard let beforeCursor = was.firstIndex(where: { $0.status == .current }),
          let afterCursor = now.firstIndex(where: { $0.status == .current }),
          afterCursor > beforeCursor
    else { return nil }

    let beforeDone = Set(was.flatMap { $0.skills }.filter { $0.completed }.map { $0.skillKey })
    let atCursor = was[beforeCursor].skills.contains(where: { $0.skillKey == completedSkillKey })
    let nowDone = now[beforeCursor].skills.first(where: { $0.skillKey == completedSkillKey })?.completed ?? false
    guard atCursor, nowDone, !beforeDone.contains(completedSkillKey) else { return nil }

    // The edges that went from not-completed to completed: out of each newly completed branch at the
    // old cursor position, into the next position's nodes.
    let newlyCompleted = now[beforeCursor].skills.filter { $0.completed && !beforeDone.contains($0.skillKey) }
    // Each unit is its own road: the last position of a unit has no edge into the next unit.
    let nextInUnit = beforeCursor + 1 < now.count && now[beforeCursor + 1].skills.first?.unitKey == now[beforeCursor].skills.first?.unitKey
    let next = nextInUnit ? now[beforeCursor + 1].skills : []
    let edges = newlyCompleted.flatMap { from in next.map { JourneyEdge(from: from.skillKey, to: $0.skillKey) } }
    let unlocked = now[afterCursor].skills.map { $0.skillKey }
    if edges.isEmpty && unlocked.isEmpty { return nil }
    return JourneyTransition(completedSkillKey: completedSkillKey, edges: edges, unlockedSkillKeys: unlocked)
}
