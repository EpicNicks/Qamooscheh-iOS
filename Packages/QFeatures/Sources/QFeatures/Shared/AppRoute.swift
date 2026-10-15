import Foundation

/// A screen pushed inside a tab's NavigationStack. Titles and the lists each tab offers live here so they can be tested.
public enum AppRoute: Hashable, Sendable {
    case themes
    case topic(String)
    case glossary
    case flashcards
    case vocabulary
    case settings
    case friends
    case help
    case about
    case shareStreak

    public var title: String {
        switch self {
        case .themes: return "Themes"
        case .topic: return "Topic"
        case .glossary: return "Glossary"
        case .flashcards: return "Flashcards"
        case .vocabulary: return "Vocabulary"
        case .settings: return "Settings"
        case .friends: return "Friends"
        case .help: return "Help & FAQ"
        case .about: return "About"
        case .shareStreak: return "Share your streak"
        }
    }

    /// The Library tab's entries.
    public static let libraryEntries: [AppRoute] = [.themes, .glossary]
    /// The Review tab's entries.
    public static let reviewEntries: [AppRoute] = [.flashcards, .vocabulary]
    /// The Profile tab's links.
    public static let profileLinks: [AppRoute] = [.settings, .friends, .help, .about, .shareStreak]
}
