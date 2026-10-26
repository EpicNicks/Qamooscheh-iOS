import Foundation
import QDomain

/// Where the path's buttons lead (Android PathNavigator). The app wires these to its routes.
public protocol PathNavigator {
    /// The current lesson.
    func startLesson(_ skill: PathSkill)
    /// A completed lesson, as local practice (no credit, never a lockout).
    func practice(_ skill: PathSkill)
    /// A stowed lesson, played through the ordinary for-lesson path so a pass counts and clears the stow.
    func retryStowed(_ skill: PathSkill)
    /// A checkpoint into `target`: "test out" of the current lesson, or the placement test into the next unit.
    func checkpoint(_ target: PositionKey)
    func reviewVocabulary(_ skill: PathSkill)
    /// The unit's vocabulary, from the book on its title.
    func reviewUnitVocabulary(unitKey: String)
    /// A Deep Dive blending every topic this lesson touches.
    func deepDiveRemix(lessonKey: String)
    /// One topic of a Deep Dive, opened from `fromLessonKey`.
    func openTheme(themeId: String, fromLessonKey: String)
}

public extension PathNavigator {
    /// The popover's primary button: retry a stowed lesson, start the current one, practise the rest.
    func performPrimary(_ skill: PathSkill) {
        switch pathPrimaryAction(skill) {
        case .retryStowed: retryStowed(skill)
        case .startLesson: startLesson(skill)
        case .practice: practice(skill)
        }
    }
}

/// For screens and tests that need a navigator that goes nowhere.
public struct NoopPathNavigator: PathNavigator {
    public init() {}
    public func startLesson(_ skill: PathSkill) {}
    public func practice(_ skill: PathSkill) {}
    public func retryStowed(_ skill: PathSkill) {}
    public func checkpoint(_ target: PositionKey) {}
    public func reviewVocabulary(_ skill: PathSkill) {}
    public func reviewUnitVocabulary(unitKey: String) {}
    public func deepDiveRemix(lessonKey: String) {}
    public func openTheme(themeId: String, fromLessonKey: String) {}
}
