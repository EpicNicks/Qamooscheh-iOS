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

/// Which side of the road a side lesson hangs on: a stable hash of its unit and skill keys, so it never moves between
/// visits or launches. The same FNV-1a plus final avalanche as web's `storySide` (roadRows.ts), over the same
/// "unitKey/skillKey" string, so a lesson hangs on the same side on every surface.
public func sidePathSide(unitKey: String, skillKey: String) -> SidePathSide {
    var h: UInt32 = 0x811c9dc5
    for scalar in "\(unitKey)/\(skillKey)".unicodeScalars {
        // JS charCodeAt(0) of a code point: the code unit, or the high surrogate of an astral one.
        let unit = String(scalar).utf16.first ?? 0
        h = (h ^ UInt32(unit)) &* 0x01000193
    }
    h ^= h >> 15
    h = h &* 0x2c1b3c6d
    h ^= h >> 12
    return h & 1 == 0 ? .left : .right
}

/// A side lesson of the unit, in published order, that branches off the road.
public func sidePathSkills(_ unit: PathUnit, category: SkillCategory) -> [PathSkill] {
    unit.otherSkills.filter { $0.category == category && $0.category.branchesOffRoad }
}

/// Whether a side lesson on the road is still locked: its unit has not been reached, or the Parsle it follows is not
/// passed yet (every standard position before the cursor reads `.unlocked`). One following no Parsle opens with its unit.
/// Web's storyRoadStatus also opens it once the lesson itself is done, or once its Parsle is done (the cursor clamps on
/// the course's last lesson, so a trailing side lesson would otherwise stay locked for good).
public func sidePathLocked(_ skill: PathSkill, in unit: PathUnit) -> Bool {
    if skill.status == .locked { return true }
    if skill.completed { return false }
    guard let anchor = skill.afterPosition, unit.standardPositions.indices.contains(anchor) else { return false }
    let position = unit.standardPositions[anchor]
    if position.skills.contains(where: { $0.completed }) { return false }
    return position.status != .unlocked
}

/// A library page of one side category: its lessons by unit. Unlocked by the unit (reached), not by the road's Parsle.
public struct SideLibraryUnit: Equatable, Sendable {
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

public typealias ListeningLibraryUnit = SideLibraryUnit

/// Units that have a lesson of `category`, in course order; units without one are left out. Only the categories that
/// branch off the road (story, listening) have a library page built from here.
public func sideLibrary(_ path: [PathUnit], category: SkillCategory) -> [SideLibraryUnit] {
    path.compactMap { unit in
        let lessons = sidePathSkills(unit, category: category)
        if lessons.isEmpty { return nil }
        return SideLibraryUnit(
            unitKey: unit.unitKey, heading: unit.heading, lessons: lessons,
            unlocked: lessons.contains { $0.status != .locked })
    }
}

/// The listening library page: listening lessons by unit.
public func listeningLibrary(_ path: [PathUnit]) -> [SideLibraryUnit] {
    sideLibrary(path, category: .listening)
}

/// The story library page: stories by unit.
public func storyLibrary(_ path: [PathUnit]) -> [SideLibraryUnit] {
    sideLibrary(path, category: .story)
}
