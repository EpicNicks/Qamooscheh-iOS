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

    public init(open: @escaping (PathDestination) -> Void) {
        self.open = open
    }

    /// Opens lessons through `startLesson` (the root's lesson cover) and screens through `push`.
    public init(startLesson: @escaping (LessonRoute) -> Void, push: @escaping (AppRoute) -> Void) {
        self.open = { destination in
            switch destination {
            case .lesson(let route): startLesson(route)
            case .push(let route): push(route)
            }
        }
    }

    public func startLesson(_ skill: PathSkill) { open(AppPathNavigator.start(skill)) }
    public func practice(_ skill: PathSkill) { open(AppPathNavigator.practice(skill)) }
    public func retryStowed(_ skill: PathSkill) { open(AppPathNavigator.retryStowed(skill)) }
    public func checkpoint(_ target: PositionKey) { open(AppPathNavigator.checkpoint(target)) }
    public func reviewVocabulary(_ skill: PathSkill) { open(AppPathNavigator.vocabulary(skill)) }
    public func reviewUnitVocabulary(unitKey: String) { open(AppPathNavigator.unitVocabulary(unitKey: unitKey)) }
    public func deepDiveRemix(lessonKey: String) { open(AppPathNavigator.deepDive(lessonKey: lessonKey)) }
    public func openTheme(themeId: String, fromLessonKey: String) { open(AppPathNavigator.theme(themeId: themeId)) }

    // MARK: The mapping

    /// Standard skills play from the cursor's plan; stories, conversations and songs are played by name. Both are the
    /// same route on iOS: the loader reads the skill's category from the course and picks the story setup itself.
    public static func start(_ skill: PathSkill) -> PathDestination {
        .lesson(LessonRoute(unitKey: skill.unitKey, skillKey: skill.skillKey))
    }

    /// A completed lesson, played locally: nothing is submitted.
    public static func practice(_ skill: PathSkill) -> PathDestination {
        .lesson(LessonRoute(unitKey: skill.unitKey, skillKey: skill.skillKey, practice: true))
    }

    /// A stowed lesson through the ordinary route, so a pass is submitted and the server clears the stow.
    public static func retryStowed(_ skill: PathSkill) -> PathDestination {
        .lesson(LessonRoute(unitKey: skill.unitKey, skillKey: skill.skillKey))
    }

    public static func checkpoint(_ target: PositionKey) -> PathDestination {
        .lesson(LessonRoute.forCheckpoint(unitKey: target.unitKey, skillKey: target.skillKey))
    }

    public static func vocabulary(_ skill: PathSkill) -> PathDestination {
        .push(.skillVocabulary(unitKey: skill.unitKey, skillKey: skill.skillKey))
    }

    public static func unitVocabulary(unitKey: String) -> PathDestination {
        .push(.skillVocabulary(unitKey: unitKey, skillKey: nil))
    }

    public static func deepDive(lessonKey: String) -> PathDestination {
        .lesson(LessonRoute.forDeepDive(lessonKey: lessonKey))
    }

    public static func theme(themeId: String) -> PathDestination {
        .push(.topic(themeId))
    }
}
