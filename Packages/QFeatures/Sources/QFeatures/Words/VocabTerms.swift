import Foundation
import QModel
import QDomain

/// How well a word is known, from the local mirror of its FSRS card (Android VocabStrength).
public enum VocabStrength: Equatable, Sendable {
    /// No card yet: never graded on this device.
    case new
    /// `level` 1...maxLevel; `due` once the card's review date has passed.
    case practiced(level: Int, due: Bool)

    public static let maxLevel = 4
}

/// FSRS stability (days) treated as fully known: the web's rough proxy (deepDiveRemix MASTERY_STABILITY_CAP).
private let masteryStabilityDays = 30.0

public func vocabStrength(_ card: CardState?, now: Date) -> VocabStrength {
    guard let card = card else { return .new }
    let mastery = min(max(card.stability / masteryStabilityDays, 0), 1)
    let level = min(max(Int((mastery * Double(VocabStrength.maxLevel)).rounded(.up)), 1), VocabStrength.maxLevel)
    let due = card.dueAt.map { $0 <= now } ?? false
    return .practiced(level: level, due: due)
}

/// One row of a vocabulary list (web VocabTermCard's props, resolved).
public struct VocabTerm: Equatable, Sendable {
    public var tag: String
    /// The tag's display form, its `<...>` markers dropped.
    public var surface: String
    public var gloss: String
    public var romanization: String?
    public var starred: Bool
    public var strength: VocabStrength

    public init(tag: String, surface: String, gloss: String, romanization: String?, starred: Bool, strength: VocabStrength) {
        self.tag = tag
        self.surface = surface
        self.gloss = gloss
        self.romanization = romanization
        self.starred = starred
        self.strength = strength
    }
}

/// `tags` in order, skipping any the lexeme index doesn't gloss (as the web does).
public func vocabTerms(
    tags: [String], lexemes: [String: LexemeIndexEntry], cards: [String: CardState], starred: Set<String>, now: Date
) -> [VocabTerm] {
    var terms: [VocabTerm] = []
    for tag in tags {
        guard let entry = lexemes[tag] else { continue }
        terms.append(VocabTerm(
            tag: tag, surface: parseLexemeTag(tag).surface, gloss: entry.gloss, romanization: entry.romanization,
            starred: starred.contains(tag), strength: vocabStrength(cards[tag], now: now)))
    }
    return terms
}

/// Folds text for vocabulary search (web foldForSearch, Android foldForSearch): case, accents and Arabic
/// diacritics are ignored (Japanese dakuten are kept: か and が differ), and the Arabic-keyboard yeh and
/// kaf match their Persian forms.
public func foldForSearch(_ text: String) -> String {
    var kept = String.UnicodeScalarView()
    for scalar in text.decomposedStringWithCanonicalMapping.unicodeScalars {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark:
            if scalar.value == 0x3099 || scalar.value == 0x309A { kept.append(scalar) }
        default:
            kept.append(scalar)
        }
    }
    let composed = String(kept).precomposedStringWithCanonicalMapping
        .replacingOccurrences(of: "\u{064A}", with: "\u{06CC}")
        .replacingOccurrences(of: "\u{0643}", with: "\u{06A9}")
        .lowercased()
    return composed.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

/// `terms` whose written form, gloss or romanization contains `query`; a blank query keeps them all.
public func filterVocabTerms(_ terms: [VocabTerm], query: String) -> [VocabTerm] {
    let needle = foldForSearch(query)
    if needle.isEmpty { return terms }
    return terms.filter { term in
        [term.surface, term.gloss, term.romanization ?? ""].contains { foldForSearch($0).contains(needle) }
    }
}

/// Lesson and unit titles share one segmented row, so a long one is shortened (Android scopeLabel).
public func scopeLabel(_ title: String) -> String {
    let max = 18
    if title.count <= max { return title }
    let head = String(title.prefix(max - 1)).trimmingCharacters(in: .whitespaces)
    return head + "\u{2026}"
}
