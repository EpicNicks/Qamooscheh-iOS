import Foundation

/// What an empty vocabulary list says (features.yaml search-miss-copy, vocab-search-dictionary-links).
/// Only a search over the whole course that matches nothing is a course miss, which also offers dictionary links.
public enum VocabEmptyKind: Equatable, Sendable {
    /// No search text: the scope simply has no words.
    case nothingYet
    /// A search over part of the course (lesson or unit) matched nothing.
    case noMatch(query: String)
    /// A search over the whole course matched nothing.
    case notInCourse(query: String)

    public var text: String {
        switch self {
        case .nothingYet: return "Nothing here yet."
        case .noMatch(let query): return "No words match \"\(query)\"."
        case .notInCourse: return "Word not found in course."
        }
    }

    /// The trimmed query to look up in dictionaries; nil unless this is a whole-course miss.
    public var lookupQuery: String? {
        if case .notInCourse(let query) = self { return query }
        return nil
    }
}

/// Picks the empty-list copy for a search text and scope. The query is trimmed of whitespace and newlines.
public func vocabEmptyKind(query: String, scope: VocabScope) -> VocabEmptyKind {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return .nothingYet }
    switch scope {
    case .course: return .notInCourse(query: trimmed)
    case .lesson, .unit: return .noMatch(query: trimmed)
    }
}

/// The heading above the dictionary buttons.
public func dictionaryLookupHeading(query: String) -> String {
    "Look up \"\(query.trimmingCharacters(in: .whitespacesAndNewlines))\" in:"
}

/// The dictionaries a course miss links to, in display order. Links only: nothing is fetched from either site.
public enum DictionarySite: String, CaseIterable, Sendable {
    case wiktionary
    case vajehyab

    public var name: String {
        switch self {
        case .wiktionary: return "Wiktionary"
        case .vajehyab: return "Vajehyab"
        }
    }

    /// The bundled icon's resource name (a PNG in QFeatures' Resources).
    var iconResource: String { "dictionary-\(rawValue)" }

    /// The bundled icon's file URL, nil if the resource is missing.
    var iconURL: URL? { Bundle.module.url(forResource: iconResource, withExtension: "png") }

    /// The page for a query: Wiktionary's search (the entry itself when one exists) or Vajehyab's word page.
    /// The query is trimmed and percent-encoded so only unreserved ASCII characters stay literal.
    public func url(query: String) -> URL? {
        let encoded = dictionaryPercentEncode(query.trimmingCharacters(in: .whitespacesAndNewlines))
        switch self {
        case .wiktionary: return URL(string: "https://en.wiktionary.org/w/index.php?search=\(encoded)&go=Go")
        case .vajehyab: return URL(string: "https://vajehyab.com/w/\(encoded)")
        }
    }
}

public struct DictionaryLink: Equatable, Sendable {
    public var site: DictionarySite
    public var url: URL

    public init(site: DictionarySite, url: URL) {
        self.site = site
        self.url = url
    }
}

/// Wiktionary then Vajehyab for a query; empty for a blank query.
public func dictionaryLinks(query: String) -> [DictionaryLink] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return [] }
    return DictionarySite.allCases.compactMap { site in
        site.url(query: trimmed).map { DictionaryLink(site: site, url: $0) }
    }
}

/// RFC 3986 unreserved characters only, so the result is safe both as a query value and as a path segment.
private let dictionaryUnreserved = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

/// Percent-encodes UTF-8 bytes of everything outside the unreserved set (a space becomes %20).
public func dictionaryPercentEncode(_ text: String) -> String {
    text.addingPercentEncoding(withAllowedCharacters: dictionaryUnreserved) ?? ""
}
