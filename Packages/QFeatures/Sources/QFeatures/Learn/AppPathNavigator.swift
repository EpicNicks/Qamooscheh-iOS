import Foundation
import QDomain

/// Where a path button leads: a lesson cover or a screen pushed on the Learn tab.
public enum PathDestination: Equatable, Sendable {
    case lesson(LessonRoute)
    case push(AppRoute)
}

/// The path's buttons as app routes (Android `AppPathNavigator`, web `useSkillActions`). The route mapping is pure
/// (`destination`), so it is tested as a table; the struct only hands each destination to the app.
public struct AppPathNavigator: PathNavigator {
    private let open: (PathDestination) -> Void
    /// Where the lessons this navigator opens return to. The Journey unless a library page says otherwise.
    private let origin: LessonOrigin

    public init(origin: LessonOrigin = .path, open: @escaping (PathDestination) -> Void) {
        self.origin = origin
        self.open = open
    }

    /// Opens lessons through `startLesson` (the root's lesson cover) and screens through `push`.
    public init(origin: LessonOrigin = .path, startLesson: @escaping (LessonRoute) -> Void, push: @escaping (AppRoute) -> Void) {
        self.origin = origin
        self.open = { destination in
            switch destination {
            case .lesson(let route): startLesson(route)
            case .push(let route): push(route)
            }
        }
    }

    public func startLesson(_ skill: PathSkill) { open(AppPathNavigator.start(skill, origin: origin)) }
    public func practice(_ skill: PathSkill) { open(AppPathNavigator.practice(skill, origin: origin)) }
    public func retryStowed(_ skill: PathSkill) { open(AppPathNavigator.retryStowed(skill, origin: origin)) }
    public func checkpoint(_ target: PositionKey) { open(AppPathNavigator.checkpoint(target, origin: origin)) }
    public func reviewVocabulary(_ skill: PathSkill) { open(AppPathNavigator.vocabulary(skill)) }
    public func reviewUnitVocabulary(unitKey: String) { open(AppPathNavigator.unitVocabulary(unitKey: unitKey)) }
    public func deepDiveRemix(lessonKey: String) { open(AppPathNavigator.deepDive(lessonKey: lessonKey, origin: origin)) }
    public func openTheme(themeId: String, fromLessonKey: String) { open(AppPathNavigator.theme(themeId: themeId)) }

    // MARK: The mapping

    /// Standard skills play from the cursor's plan; stories, conversations, songs and listening lessons are played by
    /// name. All are the same route on iOS: the loader reads the skill's category from the course and picks the setup
    /// itself. A story opens its reader; a listening lesson opens the lesson player and is submitted like any lesson.
    public static func start(_ skill: PathSkill, origin: LessonOrigin = .path) -> PathDestination {
        if skill.category == .story { return storyReader(skill, origin: origin) }
        return .lesson(LessonRoute(unitKey: skill.unitKey, skillKey: skill.skillKey, origin: origin))
    }

    /// A story opens its reader directly; the reader's button leads on to the story's cloze lessons.
    public static func storyReader(_ skill: PathSkill, practice: Bool = false, origin: LessonOrigin = .path) -> PathDestination {
        .push(.storyReader(unitKey: skill.unitKey, skillKey: skill.skillKey, practice: practice, origin: origin))
    }

    /// A completed lesson, played locally: nothing is submitted.
    public static func practice(_ skill: PathSkill, origin: LessonOrigin = .path) -> PathDestination {
        if skill.category == .story { return storyReader(skill, practice: true, origin: origin) }
        return .lesson(LessonRoute(unitKey: skill.unitKey, skillKey: skill.skillKey, practice: true, origin: origin))
    }

    /// A stowed lesson through the ordinary route, so a pass is submitted and the server clears the stow.
    public static func retryStowed(_ skill: PathSkill, origin: LessonOrigin = .path) -> PathDestination {
        .lesson(LessonRoute(unitKey: skill.unitKey, skillKey: skill.skillKey, origin: origin))
    }

    public static func checkpoint(_ target: PositionKey, origin: LessonOrigin = .path) -> PathDestination {
        .lesson(LessonRoute.forCheckpoint(unitKey: target.unitKey, skillKey: target.skillKey).from(origin))
    }

    public static func vocabulary(_ skill: PathSkill) -> PathDestination {
        .push(.skillVocabulary(unitKey: skill.unitKey, skillKey: skill.skillKey))
    }

    public static func unitVocabulary(unitKey: String) -> PathDestination {
        .push(.skillVocabulary(unitKey: unitKey, skillKey: nil))
    }

    public static func deepDive(lessonKey: String, origin: LessonOrigin = .path) -> PathDestination {
        .lesson(LessonRoute.forDeepDive(lessonKey: lessonKey).from(origin))
    }

    public static func theme(themeId: String) -> PathDestination {
        .push(.topic(themeId))
    }
}
