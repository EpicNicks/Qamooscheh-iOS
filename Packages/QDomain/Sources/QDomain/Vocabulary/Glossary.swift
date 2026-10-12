import Foundation

// Per-course reference glossary. It ships with the app (the bundled
// glossary.json resource, generated from the web's glossaryContent.ts), keyed
// by course code. The tree nests to any depth: a node with children is a
// folder (accordion), a leaf is a page of `terms` (or a custom `view`).
// Port of web glossaryContent.ts (Android Glossary.kt).

public struct GlossaryTerm: Codable, Equatable, Sendable {
    public var term: String
    public var romanization: String?
    public var definition: String

    public init(term: String, romanization: String? = nil, definition: String) {
        self.term = term
        self.romanization = romanization
        self.definition = definition
    }
}

/// A leaf that renders its own interactive component in place of a `terms` table.
public enum GlossaryView: String, Codable, Equatable, Sendable {
    case abjad
}

public struct GlossaryEntry: Codable, Equatable, Sendable {
    /// URL-safe segment, unique among siblings (not globally).
    public var id: String
    public var title: String
    /// Non-empty exactly when this node is a folder; empty means a leaf page of `terms`.
    public var children: [GlossaryEntry]
    public var terms: [GlossaryTerm]
    /// Explanatory prose shown above a leaf's table.
    public var note: String?
    public var view: GlossaryView?

    public init(id: String, title: String, children: [GlossaryEntry] = [], terms: [GlossaryTerm] = [], note: String? = nil, view: GlossaryView? = nil) {
        self.id = id
        self.title = title
        self.children = children
        self.terms = terms
        self.note = note
        self.view = view
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.children = try c.decodeIfPresent([GlossaryEntry].self, forKey: .children) ?? []
        self.terms = try c.decodeIfPresent([GlossaryTerm].self, forKey: .terms) ?? []
        self.note = try c.decodeIfPresent(String.self, forKey: .note)
        self.view = try c.decodeIfPresent(GlossaryView.self, forKey: .view)
    }

    public var isFolder: Bool { !children.isEmpty }
}

public struct Glossary: Codable, Equatable, Sendable {
    public var courses: [String: [GlossaryEntry]]

    public init(courses: [String: [GlossaryEntry]]) {
        self.courses = courses
    }

    /// This course's glossary tree, or empty when the course hasn't authored one yet.
    public func forCourse(_ courseCode: String?) -> [GlossaryEntry] {
        guard let code = courseCode, !code.isEmpty else { return [] }
        return courses[code] ?? []
    }
}

/// Walks `path` (leading-to-trailing id segments) down the tree. Returns nil on any miss, so a stale link shows "not found" rather than the wrong entry.
public func findGlossaryEntry(_ entries: [GlossaryEntry], path: [String]) -> GlossaryEntry? {
    guard let head = path.first else { return nil }
    guard let match = entries.first(where: { $0.id == head }) else { return nil }
    let rest = Array(path.dropFirst())
    return rest.isEmpty ? match : findGlossaryEntry(match.children, path: rest)
}

/// Decodes a glossary document; throws on malformed JSON or an unknown `view`.
public func parseGlossary(_ json: String) throws -> Glossary {
    try JSONDecoder().decode(Glossary.self, from: Data(json.utf8))
}

/// The glossary bundled with the app (parsed once, then cached).
public func loadGlossary() -> Glossary { bundledGlossary }

private let bundledGlossary: Glossary = {
    let bundle = Bundle.module
    guard let url = bundle.url(forResource: "glossary", withExtension: "json")
        ?? bundle.url(forResource: "glossary", withExtension: "json", subdirectory: "Resources"),
        let data = try? Data(contentsOf: url),
        let glossary = try? JSONDecoder().decode(Glossary.self, from: data)
    else {
        fatalError("Missing or invalid bundled resource glossary.json")
    }
    return glossary
}()
