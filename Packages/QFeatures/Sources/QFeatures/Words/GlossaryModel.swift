import Foundation
import Combine
import QDomain

/// What the glossary is showing (Android GlossaryPage).
public enum GlossaryPage: Equatable {
    case tree([GlossaryEntry])
    case leaf(path: [String], entry: GlossaryEntry)
    case notFound
}

/// Glossary navigation state (web GlossaryPage/GlossaryEntryPage, Android GlossaryViewModel).
/// The tree is bundled, so there is no loading or error state. The open/closed state of folders
/// lives here, keyed by path, so it survives the view being rebuilt.
@MainActor
public final class GlossaryModel: ObservableObject {
    public let courseCode: String?
    public let entries: [GlossaryEntry]
    @Published public private(set) var path: [String]
    @Published public private(set) var collapsed: Set<String> = []

    public init(courseCode: String?, glossary: Glossary, path: [String] = []) {
        self.courseCode = courseCode
        self.entries = glossary.forCourse(courseCode)
        self.path = path
    }

    public var page: GlossaryPage {
        if path.isEmpty { return .tree(entries) }
        guard let entry = findGlossaryEntry(entries, path: path), !entry.isFolder else { return .notFound }
        return .leaf(path: path, entry: entry)
    }

    /// True when a back press should step to the tree instead of leaving the glossary.
    public var isOnLeaf: Bool { !path.isEmpty }

    public func open(_ newPath: [String]) { path = newPath }

    public func up() { path = [] }

    public static func key(_ path: [String]) -> String { path.joined(separator: "/") }

    /// Folders start open (web and Android).
    public func isOpen(_ path: [String]) -> Bool { !collapsed.contains(GlossaryModel.key(path)) }

    public func toggle(_ path: [String]) {
        let k = GlossaryModel.key(path)
        if collapsed.contains(k) { collapsed.remove(k) } else { collapsed.insert(k) }
    }

    /// Whether a term is set right-to-left: an RTL course and the term is in its own script.
    public func isRtl(_ text: String) -> Bool {
        Languages.writingDirection(courseCode) == .rtl && Languages.isNativeText(courseCode, text)
    }
}
