import Foundation

// Lexeme tags are the natural key both exercises and the lexeme index share
// (e.g. `سلام<interj><spoken>`): a display surface form followed by `<...>`
// attribute markers (part of speech, register). The markers are internal
// bookkeeping, never meant to reach the UI as text. Port of web lexemeTag.ts.

public struct ParsedLexemeTag: Equatable, Sendable {
    public var surface: String
    public var attributes: [String]

    public init(surface: String, attributes: [String]) {
        self.surface = surface
        self.attributes = attributes
    }
}

private let attributePattern = try! NSRegularExpression(pattern: "<([^>]+)>")

public func parseLexemeTag(_ tag: String) -> ParsedLexemeTag {
    let surface = tagSurface(tag)
    if surface.unicodeScalars.count == tag.unicodeScalars.count {
        return ParsedLexemeTag(surface: tag, attributes: [])
    }
    let ns = tag as NSString
    var attributes: [String] = []
    for match in attributePattern.matches(in: tag, range: NSRange(location: 0, length: ns.length)) {
        attributes.append(ns.substring(with: match.range(at: 1)))
    }
    return ParsedLexemeTag(surface: surface, attributes: attributes)
}

/// The tag's surface: everything before its first `<`, or the whole tag (web `tag.split("<", 1)[0]`).
func tagSurface(_ tag: String) -> String {
    var out = String.UnicodeScalarView()
    for scalar in tag.unicodeScalars {
        if scalar == "<" { break }
        out.append(scalar)
    }
    return String(out)
}
