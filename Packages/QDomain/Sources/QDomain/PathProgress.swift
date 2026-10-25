// Client-side re-derivation of the user_progress unlock gate, for rendering the
// path/skill-tree screen. Ported 1:1 from web src/domain/pathProgress.ts.
// Authoritative for DISPLAY only; gated reads are enforced server-side.

public enum SkillCategory: String, Equatable, Hashable, Sendable {
    case standard
    case story
    case conversation
    case song
}

public enum SkillStatus: String, Equatable, Hashable, Sendable {
    case locked
    case unlocked
    case current
}

public struct PathSkillInput: Equatable, Sendable {
    public var skillKey: String
    public var title: String
    public var category: SkillCategory
    /// The narrative this skill is a chapter of, if any.
    public var arc: String?

    public init(skillKey: String, title: String, category: SkillCategory, arc: String? = nil) {
        self.skillKey = skillKey
        self.title = title
        self.category = category
        self.arc = arc
    }
}

/// One point in a unit's standard sequence: 1 skill = no fork, 2+ = alternates.
public struct PathPositionInput: Equatable, Sendable {
    public var skills: [PathSkillInput]

    public init(skills: [PathSkillInput]) {
        self.skills = skills
    }
}

public struct PathUnitInput: Equatable, Sendable {
    public var unitKey: String
    public var title: String
    public var standardPositions: [PathPositionInput]
    public var otherSkills: [PathSkillInput]

    public init(
        unitKey: String,
        title: String,
        standardPositions: [PathPositionInput],
        otherSkills: [PathSkillInput]
    ) {
        self.unitKey = unitKey
        self.title = title
        self.standardPositions = standardPositions
        self.otherSkills = otherSkills
    }
}

public struct PathSkill: Equatable, Sendable {
    public var skillKey: String
    public var title: String
    public var category: SkillCategory
    public var arc: String?
    public var unitKey: String
    public var status: SkillStatus
    /// Whether the learner has a completion event for this skill.
    public var completed: Bool
    /// Index within the unit's standard sequence; nil for non-standard skills.
    public var positionIndex: Int?
    /// Whether the learner stowed this lesson and has not passed it yet. It sits behind the cursor,
    /// so `status` says nothing about it: draw it from this flag. Comes from the Stowage, never from position.
    public var stowed: Bool

    public init(
        skillKey: String,
        title: String,
        category: SkillCategory,
        arc: String?,
        unitKey: String,
        status: SkillStatus,
        completed: Bool,
        positionIndex: Int?,
        stowed: Bool = false
    ) {
        self.skillKey = skillKey
        self.title = title
        self.category = category
        self.arc = arc
        self.unitKey = unitKey
        self.status = status
        self.completed = completed
        self.positionIndex = positionIndex
        self.stowed = stowed
    }
}

/// Status lives here: every alternate at a position shares it.
public struct PathPosition: Equatable, Sendable {
    public var positionIndex: Int
    public var status: SkillStatus
    public var skills: [PathSkill]

    public init(positionIndex: Int, status: SkillStatus, skills: [PathSkill]) {
        self.positionIndex = positionIndex
        self.status = status
        self.skills = skills
    }
}

public struct PathUnit: Equatable, Sendable {
    public var unitKey: String
    public var title: String
    public var standardPositions: [PathPosition]
    public var otherSkills: [PathSkill]

    public init(unitKey: String, title: String, standardPositions: [PathPosition], otherSkills: [PathSkill]) {
        self.unitKey = unitKey
        self.title = title
        self.standardPositions = standardPositions
        self.otherSkills = otherSkills
    }

    /// A unit with a live stowed lesson is never complete, however far the cursor has moved past it.
    public var deferred: Bool {
        standardPositions.contains(where: { position in position.skills.contains(where: { $0.stowed }) })
    }
}

public struct PositionKey: Equatable, Hashable, Sendable {
    public var unitKey: String
    public var skillKey: String

    public init(unitKey: String, skillKey: String) {
        self.unitKey = unitKey
        self.skillKey = skillKey
    }
}

public enum BranchKind: String, Equatable, Sendable {
    case fork
}

public struct PositionBranches: Equatable, Sendable {
    public var kind: BranchKind
    public var skills: [PathSkill]
    public var done: Int
    public var total: Int

    public init(kind: BranchKind, skills: [PathSkill], done: Int, total: Int) {
        self.kind = kind
        self.skills = skills
        self.done = done
        self.total = total
    }
}

/// The branches of a position, or nil when it is a single lesson.
public func positionBranches(_ position: PathPosition) -> PositionBranches? {
    if position.skills.count < 2 { return nil }
    return PositionBranches(
        kind: .fork,
        skills: position.skills,
        done: position.skills.filter { $0.completed }.count,
        total: position.skills.count
    )
}

public func computePathProgress(
    _ units: [PathUnitInput],
    position: PositionKey?,
    completedSkillKeys: Set<String> = [],
    stowedLessonKeys: Set<String> = []
) -> [PathUnit] {
    let currentUnitIndex: Int
    if let position = position {
        currentUnitIndex = units.firstIndex(where: { $0.unitKey == position.unitKey }) ?? -1
    } else {
        currentUnitIndex = -1
    }

    var result: [PathUnit] = []
    for (unitIndex, unit) in units.enumerated() {
        var currentPositionIndex = -1
        if unitIndex == currentUnitIndex, let position = position {
            currentPositionIndex = unit.standardPositions.firstIndex(where: { pos in
                pos.skills.contains(where: { $0.skillKey == position.skillKey })
            }) ?? -1
        }

        var standardPositions: [PathPosition] = []
        for (posIndex, pos) in unit.standardPositions.enumerated() {
            let status: SkillStatus
            if unitIndex < currentUnitIndex {
                status = .unlocked
            } else if unitIndex > currentUnitIndex {
                status = .locked
            } else if currentPositionIndex < 0 {
                status = .locked
            } else if posIndex < currentPositionIndex {
                status = .unlocked
            } else if posIndex == currentPositionIndex {
                status = .current
            } else {
                status = .locked
            }

            let skills = pos.skills.map { s in
                PathSkill(
                    skillKey: s.skillKey,
                    title: s.title,
                    category: s.category,
                    arc: s.arc,
                    unitKey: unit.unitKey,
                    status: status,
                    completed: completedSkillKeys.contains(s.skillKey),
                    positionIndex: posIndex,
                    stowed: stowedLessonKeys.contains(s.skillKey)
                )
            }
            standardPositions.append(PathPosition(positionIndex: posIndex, status: status, skills: skills))
        }

        let otherStatus: SkillStatus = unitIndex <= currentUnitIndex ? .unlocked : .locked
        let otherSkills = unit.otherSkills.map { s in
            PathSkill(
                skillKey: s.skillKey,
                title: s.title,
                category: s.category,
                arc: s.arc,
                unitKey: unit.unitKey,
                status: otherStatus,
                completed: completedSkillKeys.contains(s.skillKey),
                positionIndex: nil
            )
        }

        result.append(PathUnit(
            unitKey: unit.unitKey,
            title: unit.title,
            standardPositions: standardPositions,
            otherSkills: otherSkills
        ))
    }
    return result
}

/// The standard position immediately after the current one, crossing into the
/// next unit with a standard position if needed. Nil when nothing is current
/// or the current position is the last in the course.
public func findNextStandardTarget(_ path: [PathUnit]) -> PositionKey? {
    for unitIndex in 0..<path.count {
        let unit = path[unitIndex]
        guard let currentPosIndex = unit.standardPositions.firstIndex(where: { $0.status == .current }) else {
            continue
        }

        if currentPosIndex + 1 < unit.standardPositions.count {
            let next = unit.standardPositions[currentPosIndex + 1]
            return PositionKey(unitKey: unit.unitKey, skillKey: next.skills[0].skillKey)
        }

        var nextUnitIndex = unitIndex + 1
        while nextUnitIndex < path.count {
            if let nextPosition = path[nextUnitIndex].standardPositions.first {
                return PositionKey(unitKey: path[nextUnitIndex].unitKey, skillKey: nextPosition.skills[0].skillKey)
            }
            nextUnitIndex += 1
        }
        return nil
    }
    return nil
}

/// The lesson a learner who just finished `finished` would start next: the
/// current position, once the cursor has moved past every lesson in `finished`.
public func findLessonAfter(_ path: [PathUnit], finished: [(unitKey: String?, skillKey: String)]) -> PositionKey? {
    for unit in path {
        guard let current = unit.standardPositions.first(where: { $0.status == .current }) else { continue }
        let stillCurrent = current.skills.contains(where: { s in
            finished.contains(where: { $0.unitKey == unit.unitKey && $0.skillKey == s.skillKey })
        })
        if stillCurrent { return nil }
        let branch = current.skills.first(where: { !$0.completed }) ?? current.skills[0]
        return PositionKey(unitKey: unit.unitKey, skillKey: branch.skillKey)
    }
    return nil
}

/// The next unit's own first standard position ("skip the rest of this unit").
public func findNextUnitEntryTarget(_ path: [PathUnit]) -> PositionKey? {
    guard let currentUnitIndex = path.firstIndex(where: { unit in
        unit.standardPositions.contains(where: { $0.status == .current })
    }) else {
        return nil
    }

    var nextUnitIndex = currentUnitIndex + 1
    while nextUnitIndex < path.count {
        if let firstPosition = path[nextUnitIndex].standardPositions.first {
            return PositionKey(unitKey: path[nextUnitIndex].unitKey, skillKey: firstPosition.skills[0].skillKey)
        }
        nextUnitIndex += 1
    }
    return nil
}

/// Whether `target` is the first standard position of the first unit; matches
/// any alternate at that position.
public func isFirstStandardPosition(_ path: [PathUnit], target: PositionKey) -> Bool {
    guard let firstUnit = path.first, firstUnit.unitKey == target.unitKey else { return false }
    guard let firstPosition = firstUnit.standardPositions.first else { return false }
    return firstPosition.skills.contains(where: { $0.skillKey == target.skillKey })
}

/// A run of skills sharing one `arc`, or a lone skill belonging to none.
public struct ArcGroup: Equatable, Sendable {
    public var key: String
    public var arc: String?
    public var skills: [PathSkill]

    public init(key: String, arc: String?, skills: [PathSkill]) {
        self.key = key
        self.arc = arc
        self.skills = skills
    }
}

/// Buckets non-standard skills into arc groups, preserving content order; a
/// group takes the position of its first member. Skills without an arc (nil or
/// empty, matching JS falsiness) stay singleton groups with `arc == nil`.
public func groupByArc(_ skills: [PathSkill]) -> [ArcGroup] {
    var groups: [ArcGroup] = []
    var indexByArc: [String: Int] = [:]

    for skill in skills {
        guard let arc = skill.arc, !arc.isEmpty else {
            groups.append(ArcGroup(key: "\(skill.unitKey)/\(skill.skillKey)", arc: nil, skills: [skill]))
            continue
        }

        if let idx = indexByArc[arc] {
            groups[idx].skills.append(skill)
        } else {
            indexByArc[arc] = groups.count
            groups.append(ArcGroup(key: "arc:\(arc)", arc: arc, skills: [skill]))
        }
    }
    return groups
}
