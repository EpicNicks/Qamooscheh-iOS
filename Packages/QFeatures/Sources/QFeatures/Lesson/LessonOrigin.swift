import SwiftUI

/// Where a lesson was launched from, so leaving or finishing it can say and go back to that place. The lesson itself
/// is a full-screen cover over the tabs, so closing it already lands on the launching tab's stack; the origin names
/// that place in the "Back to ..." labels and keeps the stack right (a story reader is popped to its library page).
/// `.path` is the default and the behaviour from before origins existed.
public enum LessonOrigin: Hashable, Sendable {
    /// The Journey (also the fallback for anything that sets no origin).
    case path
    /// A Library page of side lessons: Stories or Listening.
    case sideLibrary(SideLibraryKind)
    /// The Library's Themes page: a remix of its topics.
    case themes
    /// A topic page (reached from Themes or the Journey): one of its lessons.
    case topic

    /// The label of every "back" button after a lesson: "Back to path" unless it came from elsewhere.
    public var backLabel: String {
        switch self {
        case .path: return LessonScreenLogic.backToPath
        case .sideLibrary(let kind): return "Back to \(kind.title)"
        case .themes: return "Back to themes"
        case .topic: return "Back to topic"
        }
    }

    /// The tab's navigation stack as it should be when a lesson launched from here is presented. A library page keeps
    /// itself as the top destination, popping anything pushed above it (the story reader) rather than stacking a second
    /// copy, and is pushed only if somehow absent. Other origins leave the stack alone.
    public func stackForLesson(_ stack: [AppRoute]) -> [AppRoute] {
        switch self {
        case .sideLibrary(let kind):
            let page = AppRoute.sideLibrary(kind)
            if let index = stack.lastIndex(of: page) { return Array(stack[...index]) }
            return stack + [page]
        case .path, .themes, .topic:
            return stack
        }
    }
}

private struct LessonBackLabelKey: EnvironmentKey {
    static let defaultValue = LessonScreenLogic.backToPath
}

extension EnvironmentValues {
    /// The "Back to ..." text of the lesson cover's buttons; the cover sets it from the route's origin.
    var lessonBackLabel: String {
        get { self[LessonBackLabelKey.self] }
        set { self[LessonBackLabelKey.self] = newValue }
    }
}
