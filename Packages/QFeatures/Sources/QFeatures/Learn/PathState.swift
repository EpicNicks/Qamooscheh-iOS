import Foundation
import Combine
import QModel
import QDomain

// SwiftUI-free state for the Path screen (web PathPage + useCompletedLessons +
// useEnrollment + useSkillActions; Android PathViewModel + PathRepository +
// PathActions). Progress and geometry come from QDomain (computePathProgress,
// computeRoadLayout); nothing is re-derived here.

/// The downloaded course content the path is drawn from.
public struct PathContent: Equatable, Sendable {
    public var units: [PathUnitInput]

    public init(units: [PathUnitInput]) {
        self.units = units
    }
}

/// What the daily-goal ring reads: its own prefs and activity, apart from the path content.
public protocol DailyGoalSource: Sendable {
    /// GET /v1/prefs (dailyGoalXp).
    func prefs() async throws -> PrefsResponse
    /// GET /v1/activity/{courseCode}.
    func activity(courseCode: String) async throws -> ActivityResponse
}

/// What the Path screen reads. The app wires this to QNetwork/QData later.
public protocol PathRepository: DailyGoalSource {
    /// The pinned course's units, from the downloaded content.
    func pathContent(course: CourseRef) async throws -> PathContent
    /// GET /v1/lessons/completed: skill keys with a completion event.
    func completedLessonKeys(courseCode: String) async throws -> Set<String>
}

public enum PathLoadStatus: Equatable, Sendable {
    case noCourse
    case loading
    case ready
    case failed(String)
}

/// The current lesson's place on the road.
public struct PathCurrentNode: Equatable, Sendable {
    public var unitKey: String
    public var unitIndex: Int
    public var positionIndex: Int
    /// The alternate the learner would start: the first unfinished one at a fork, else the first.
    public var skillKey: String

    public init(unitKey: String, unitIndex: Int, positionIndex: Int, skillKey: String) {
        self.unitKey = unitKey
        self.unitIndex = unitIndex
        self.positionIndex = positionIndex
        self.skillKey = skillKey
    }
}

/// Today's XP against the daily goal.
public struct DailyGoalProgress: Equatable, Sendable {
    public var xp: Int
    public var goal: Int

    public init(xp: Int, goal: Int) {
        self.xp = xp
        self.goal = goal
    }

    public var reached: Bool { goal > 0 && xp >= goal }

    /// Ring fill, 0...1.
    public var fraction: Double {
        if goal <= 0 { return 0 }
        return min(max(Double(xp) / Double(goal), 0), 1)
    }
}

public enum JumpDirection: Equatable, Sendable {
    case up
    case down
}

/// Where the current lesson's unit road sits in the scroll view.
public enum CurrentRoadScroll: Equatable, Sendable {
    /// The road is entirely above the viewport.
    case offscreenAbove
    /// The road is entirely below the viewport.
    case offscreenBelow
    /// The road is (partly) on screen: the current node's centre and the viewport's edges, in one coordinate space.
    case visible(nodeCentre: Double, viewportStart: Double, viewportEnd: Double)
}

/// Android PathContent: no button while the current node is on screen; otherwise it points the way it is.
public func jumpToCurrentDirection(_ scroll: CurrentRoadScroll?) -> JumpDirection? {
    guard let scroll = scroll else { return nil }
    switch scroll {
    case .offscreenAbove:
        return .up
    case .offscreenBelow:
        return .down
    case let .visible(nodeCentre, viewportStart, viewportEnd):
        if nodeCentre < viewportStart { return .up }
        if nodeCentre > viewportEnd { return .down }
        return nil
    }
}

/// A skill popover's id; one open at a time. Same shape as `refKey` ("unitKey/skillKey").
public func pathPopoverId(unitKey: String, skillKey: String) -> String {
    return "\(unitKey)/\(skillKey)"
}

/// What a standard skill's popover offers (Android skillActions).
public struct SkillActions: Equatable, Sendable {
    public var primaryLabel: String
    public var startsLesson: Bool
    /// "Test out": only on the current lesson, and only when a position follows it.
    public var skipTarget: PositionKey?
    /// "Stow": the last action, offered only for a key the server lists as stowable.
    public var stowOffered: Bool

    public init(primaryLabel: String, startsLesson: Bool, skipTarget: PositionKey?, stowOffered: Bool = false) {
        self.primaryLabel = primaryLabel
        self.startsLesson = startsLesson
        self.skipTarget = skipTarget
        self.stowOffered = stowOffered
    }
}

public func skillActions(_ skill: PathSkill, nextSkipTarget: PositionKey?, stowableLessonKeys: Set<String> = []) -> SkillActions {
    let current = skill.status == .current
    return SkillActions(
        primaryLabel: current ? "Start lesson" : "Practice",
        startsLesson: current,
        skipTarget: current ? nextSkipTarget : nil,
        stowOffered: stowableLessonKeys.contains(skill.skillKey) && !skill.stowed
    )
}

/// Everything the Path screen renders, as a value. Mutated only through the methods below.
public struct PathState: Equatable, Sendable {
    public private(set) var status: PathLoadStatus = .noCourse
    public private(set) var course: CourseRef?
    public private(set) var enrolledCourseCodes: [String] = []
    public private(set) var position: PositionKey?
    public private(set) var completedSkillKeys: Set<String> = []
    public private(set) var content: PathContent?
    public private(set) var units: [PathUnit] = []
    public private(set) var openPopoverId: String?
    public private(set) var jumpDirection: JumpDirection?
    public private(set) var scroll: CurrentRoadScroll?
    public private(set) var dailyGoal: DailyGoalProgress?
    /// Stowed lessons by unit, as the server returned them (units descending).
    public private(set) var stowage: [StowageUnit] = []
    /// Lesson keys at the cursor that pass the Stow gate.
    public private(set) var stowableLessonKeys: [String] = []

    public init() {}

    /// Keys of every lesson with a live Stowage entry.
    public var stowedLessonKeys: Set<String> {
        Set(stowage.flatMap { unit in unit.lessons.map { $0.lessonKey } })
    }

    /// Units with a live stowed lesson: never drawn as complete.
    public var deferredUnitKeys: Set<String> {
        Set(units.filter { $0.deferred }.map { $0.unitKey })
    }

    /// The first position with status `.current`, if any.
    public var currentNode: PathCurrentNode? {
        for (unitIndex, unit) in units.enumerated() {
            guard let position = unit.standardPositions.first(where: { $0.status == .current }),
                  let first = position.skills.first else { continue }
            let skill = position.skills.first(where: { !$0.completed }) ?? first
            return PathCurrentNode(
                unitKey: unit.unitKey,
                unitIndex: unitIndex,
                positionIndex: position.positionIndex,
                skillKey: skill.skillKey
            )
        }
        return nil
    }

    /// "Test out" target for the current lesson.
    public var nextSkipTarget: PositionKey? { findNextStandardTarget(units) }

    /// The next unit's placement-test target.
    public var nextUnitEntry: PositionKey? { findNextUnitEntryTarget(units) }

    /// y of the current node within its unit's road, from QDomain's layout.
    /// Forks collapse to one row per position by default (phones), as the road itself is drawn.
    public func currentNodeY(config: RoadLayoutConfig, collapseForks: Bool = true) -> Double? {
        guard let node = currentNode else { return nil }
        let counts = units[node.unitIndex].standardPositions.map { collapseForks ? 1 : $0.skills.count }
        let layout = computeRoadLayout(counts, config: config)
        return layout.nodes.first(where: { $0.positionIndex == node.positionIndex })?.y
    }

    // MARK: Reducer

    /// A different course (or none) clears everything course-scoped.
    public mutating func setBootstrap(_ bootstrap: BootstrapResponse) {
        let newCourse = bootstrap.course
        let newPosition = bootstrap.position.map { PositionKey(unitKey: $0.unitKey, skillKey: $0.skillKey) }
        enrolledCourseCodes = bootstrap.enrolledCourseCodes
        stowage = bootstrap.stowage
        stowableLessonKeys = bootstrap.stowableLessonKeys
        let courseChanged = newCourse?.code != course?.code || newCourse?.version != course?.version
        course = newCourse
        position = newPosition
        if newCourse == nil {
            status = .noCourse
            clearCourseScoped()
        } else if courseChanged {
            status = .loading
            clearCourseScoped()
        } else {
            recompute()
        }
    }

    /// A stow answer: the returned Stowage and cursor. The stowed lesson is no longer stowable.
    public mutating func applyStowage(_ stowage: [StowageUnit], position: PositionRef? = nil) {
        self.stowage = stowage
        let stowed = stowedLessonKeys
        stowableLessonKeys = stowableLessonKeys.filter { !stowed.contains($0) }
        if let position = position {
            self.position = PositionKey(unitKey: position.unitKey, skillKey: position.skillKey)
        }
        recompute()
    }

    /// A submit result's `stowCleared`: that lesson leaves the Stowage (and is simply passed).
    public mutating func applyStowCleared(_ lessonKey: String) {
        var next: [StowageUnit] = []
        for var unit in stowage {
            unit.lessons.removeAll(where: { $0.lessonKey == lessonKey })
            if !unit.lessons.isEmpty { next.append(unit) }
        }
        stowage = next
        recompute()
    }

    public mutating func setContent(_ content: PathContent) {
        self.content = content
        status = .ready
        recompute()
    }

    public mutating func setFailed(_ message: String) {
        status = .failed(message)
        content = nil
        units = []
        openPopoverId = nil
        jumpDirection = nil
    }

    public mutating func setCompleted(_ keys: Set<String>) {
        completedSkillKeys = keys
        recompute()
    }

    /// A nil goal hides the ring (Android: the ring simply hides without prefs).
    public mutating func setDailyGoal(goal: Int?, days: [ActivityDay], today: String) {
        guard let goal = goal else {
            dailyGoal = nil
            return
        }
        dailyGoal = DailyGoalProgress(xp: xpToday(days, today: today), goal: goal)
    }

    public mutating func openPopover(_ id: String) {
        openPopoverId = id
    }

    public mutating func closePopover() {
        openPopoverId = nil
    }

    /// Tapping the open node again closes it.
    public mutating func togglePopover(_ id: String) {
        openPopoverId = openPopoverId == id ? nil : id
    }

    public mutating func setScroll(_ scroll: CurrentRoadScroll?) {
        self.scroll = scroll
        updateJumpDirection()
    }

    private mutating func updateJumpDirection() {
        jumpDirection = currentNode == nil ? nil : jumpToCurrentDirection(scroll)
    }

    private mutating func clearCourseScoped() {
        content = nil
        units = []
        completedSkillKeys = []
        dailyGoal = nil
        openPopoverId = nil
        jumpDirection = nil
        scroll = nil
    }

    private mutating func recompute() {
        guard let content = content else {
            units = []
            updateJumpDirection()
            return
        }
        units = computePathProgress(content.units, position: position, completedSkillKeys: completedSkillKeys, stowedLessonKeys: stowedLessonKeys)
        updateJumpDirection()
        if let open = openPopoverId, !hasSkill(popoverId: open) { openPopoverId = nil }
    }

    private func hasSkill(popoverId: String) -> Bool {
        for unit in units {
            for position in unit.standardPositions {
                for skill in position.skills where pathPopoverId(unitKey: unit.unitKey, skillKey: skill.skillKey) == popoverId {
                    return true
                }
            }
            for skill in unit.otherSkills where pathPopoverId(unitKey: unit.unitKey, skillKey: skill.skillKey) == popoverId {
                return true
            }
        }
        return false
    }
}

private func capturePathResult<T: Sendable>(_ work: @Sendable () async throws -> T) async -> Result<T, Error> {
    do {
        return .success(try await work())
    } catch {
        return .failure(error)
    }
}

private func pathErrorMessage(_ error: Error) -> String {
    let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    return text.isEmpty ? "Could not load your path." : text
}

/// Loads the path for a bootstrap and holds the resulting state. Completed lessons, prefs and
/// activity are best-effort (Android `runCatching`): a failure keeps the last values.
@MainActor
public final class PathModel: ObservableObject {
    @Published public private(set) var state = PathState()

    private let repository: PathRepository
    private let dailyGoalSource: DailyGoalSource
    private let now: () -> Date
    private let calendar: Calendar
    private var generation = 0
    private var lastBootstrap: BootstrapResponse?

    public init(repository: PathRepository, dailyGoalSource: DailyGoalSource? = nil, now: @escaping () -> Date = { Date() }, calendar: Calendar = .current) {
        self.repository = repository
        self.dailyGoalSource = dailyGoalSource ?? repository
        self.now = now
        self.calendar = calendar
    }

    /// Apply a (new) bootstrap and reload what it implies. A reload superseded by a newer call is dropped.
    public func refresh(bootstrap: BootstrapResponse) async {
        generation += 1
        let mine = generation
        lastBootstrap = bootstrap
        state.setBootstrap(bootstrap)
        guard let course = bootstrap.course else { return }
        let repository = self.repository
        let goalSource = self.dailyGoalSource

        let content = await capturePathResult { try await repository.pathContent(course: course) }
        let completed = await capturePathResult { try await repository.completedLessonKeys(courseCode: course.code) }
        let prefs = await capturePathResult { try await goalSource.prefs() }
        let activity = await capturePathResult { try await goalSource.activity(courseCode: course.code) }
        guard mine == generation else { return }

        if case let .success(keys) = completed { state.setCompleted(keys) }
        switch content {
        case let .success(value):
            state.setContent(value)
        case let .failure(error):
            state.setFailed(pathErrorMessage(error))
        }
        if case let .success(prefs) = prefs, case let .success(activity) = activity {
            state.setDailyGoal(goal: prefs.dailyGoalXp, days: activity.days, today: todayLocalDay(now: now(), calendar: calendar))
        }
    }

    /// A submit result's `stowCleared`: drop the lesson from the local Stowage, then refresh from it.
    public func applyStowCleared(_ lessonKey: String) async {
        state.applyStowCleared(lessonKey)
        guard var bootstrap = lastBootstrap else { return }
        bootstrap.stowage = state.stowage
        await refresh(bootstrap: bootstrap)
    }

    public func openPopover(_ id: String) { state.openPopover(id) }
    public func closePopover() { state.closePopover() }
    public func togglePopover(_ id: String) { state.togglePopover(id) }
    public func setScroll(_ scroll: CurrentRoadScroll?) { state.setScroll(scroll) }
}

extension PathModel: StowStateHost {
    public var stowage: [StowageUnit] { state.stowage }

    public func applyStowage(_ stowage: [StowageUnit], position: PositionRef?) {
        state.applyStowage(stowage, position: position)
    }
}
