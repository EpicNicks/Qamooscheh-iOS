// Side lessons that hang off the Journey road: stories and listening lessons (features.yaml story-spurs-stories-only,
// listening-side-lessons). Pure rules, so `swift test` proves them; the road and library views read them.

public enum SidePathSide: String, Equatable, Hashable, Sendable {
    case left
    case right
}

public extension SkillCategory {
    /// Only stories and listening lessons branch off as side paths; conversations, songs and standard lessons do not.
    var branchesOffRoad: Bool { self == .story || self == .listening }

    /// Opens in the lesson player (a listening lesson), never in the story reader.
    var opensInLessonPlayer: Bool { self == .listening }

    /// Whether this build can show the category at all. An unknown one is declined, never shown as a story.
    var isKnown: Bool { self != .unknown }
}

/// Which side of the road a side lesson hangs on: a stable hash of its key (the same FNV-1a plus fmix32 the voice pick
/// uses), so it never moves between visits or launches.
public func sidePathSide(skillKey: String) -> SidePathSide {
    Recordings.voiceHash("side:" + skillKey) % 2 == 0 ? .left : .right
}

/// A side lesson of the unit, in published order, that branches off the road.
public func sidePathSkills(_ unit: PathUnit, category: SkillCategory) -> [PathSkill] {
    unit.otherSkills.filter { $0.category == category && $0.category.branchesOffRoad }
}

/// Whether a side lesson on the road is still locked: its unit has not been reached, or the Parsle it follows is not
/// passed yet (every standard position before the cursor reads `.unlocked`). One following no Parsle opens with its unit.
public func sidePathLocked(_ skill: PathSkill, in unit: PathUnit) -> Bool {
    if skill.status == .locked { return true }
    guard let anchor = skill.afterPosition, unit.standardPositions.indices.contains(anchor) else { return false }
    return unit.standardPositions[anchor].status != .unlocked
}

/// The listening library page: listening lessons by unit. Unlocked by the unit (reached), not by the road's Parsle.
public struct ListeningLibraryUnit: Equatable, Sendable {
    public var unitKey: String
    public var heading: String
    public var lessons: [PathSkill]
    public var unlocked: Bool

    public init(unitKey: String, heading: String, lessons: [PathSkill], unlocked: Bool) {
        self.unitKey = unitKey
        self.heading = heading
        self.lessons = lessons
        self.unlocked = unlocked
    }
}

/// Units that have a listening lesson, in course order; units without one are left out.
public func listeningLibrary(_ path: [PathUnit]) -> [ListeningLibraryUnit] {
    path.compactMap { unit in
        let lessons = sidePathSkills(unit, category: .listening)
        if lessons.isEmpty { return nil }
        return ListeningLibraryUnit(
            unitKey: unit.unitKey, heading: unit.heading, lessons: lessons,
            unlocked: lessons.contains { $0.status != .locked })
    }
}
