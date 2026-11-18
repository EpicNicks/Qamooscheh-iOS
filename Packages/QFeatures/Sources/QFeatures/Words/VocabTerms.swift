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
    /// The word is a verb's base form: saved, its practice pulls in sentences with any form of the verb.
    public var isBaseVerb: Bool
    /// The verb this form belongs to, offered to save beside the form itself; nil when it isn't a verb form.
    public var baseVerb: BaseVerbTerm?
    /// For an infinitive, its `lemma` when verbs.json has that verb (the key of its forms table); else nil.
    public var verbKey: String?

    public init(tag: String, surface: String, gloss: String, romanization: String?, starred: Bool, strength: VocabStrength, isBaseVerb: Bool = false, baseVerb: BaseVerbTerm? = nil, verbKey: String? = nil) {
        self.tag = tag
        self.surface = surface
        self.gloss = gloss
        self.romanization = romanization
        self.starred = starred
        self.strength = strength
        self.isBaseVerb = isBaseVerb
        self.baseVerb = baseVerb
        self.verbKey = verbKey
    }
}

/// A verb form's infinitive, as its row offers it (API_SPEC 2.4, Qamooscheh-Backend#102).
public struct BaseVerbTerm: Equatable, Sendable {
    public var tag: String
    public var surface: String
    public var gloss: String
    public var starred: Bool
    /// The infinitive's `lemma` when verbs.json has that verb (the key of its forms table); else nil.
    public var verbKey: String?

    public init(tag: String, surface: String, gloss: String, starred: Bool, verbKey: String? = nil) {
        self.tag = tag
        self.surface = surface
        self.gloss = gloss
        self.starred = starred
        self.verbKey = verbKey
    }
}

/// An infinitive entry's `lemma` when `verbs` has it; nil for anything else.
private func infinitiveVerbKey(_ entry: LexemeIndexEntry, verbs: [String: VerbIndexEntry]) -> String? {
    guard isBaseVerb(entry), let lemma = entry.lemma, !lemma.isEmpty, verbs[lemma] != nil else { return nil }
    return lemma
}

/// `tags` in order, skipping any the lexeme index doesn't gloss (as the web does).
public func vocabTerms(
    tags: [String], lexemes: [String: LexemeIndexEntry], cards: [String: CardState], starred: Set<String>, now: Date,
    verbs: [String: VerbIndexEntry] = [:]
) -> [VocabTerm] {
    let baseIndex = baseVerbIndex(lexemes)
    var terms: [VocabTerm] = []
    for tag in tags {
        guard let entry = lexemes[tag] else { continue }
        let base = baseVerbTag(of: tag, lexemes: lexemes, index: baseIndex).flatMap { baseTag in
            lexemes[baseTag].map {
                BaseVerbTerm(
                    tag: baseTag, surface: parseLexemeTag(baseTag).surface, gloss: $0.gloss, starred: starred.contains(baseTag),
                    verbKey: infinitiveVerbKey($0, verbs: verbs))
            }
        }
        terms.append(VocabTerm(
            tag: tag, surface: parseLexemeTag(tag).surface, gloss: entry.gloss, romanization: entry.romanization,
            starred: starred.contains(tag), strength: vocabStrength(cards[tag], now: now),
            isBaseVerb: isBaseVerb(entry), baseVerb: base, verbKey: infinitiveVerbKey(entry, verbs: verbs)))
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

/// A vocabulary search (vocab-search-verbs): the scope's taught terms that match `query`, then every course
/// infinitive (lexemes with `isBaseVerb`) whose written form, gloss or romanization matches, in tag order,
/// skipping any tag already listed. A blank query returns `taught` unchanged.
public func searchVocabTerms(
    taught: [VocabTerm], query: String, lexemes: [String: LexemeIndexEntry], verbs: [String: VerbIndexEntry],
    cards: [String: CardState], starred: Set<String>, now: Date
) -> [VocabTerm] {
    let needle = foldForSearch(query)
    if needle.isEmpty { return taught }
    let matched = filterVocabTerms(taught, query: query)
    let listed = Set(matched.map { $0.tag })
    var extraTags: [String] = []
    for tag in lexemes.keys.sorted() where !listed.contains(tag) {
        guard let entry = lexemes[tag], isBaseVerb(entry) else { continue }
        let fields = [parseLexemeTag(tag).surface, entry.gloss, entry.romanization ?? ""]
        if fields.contains(where: { foldForSearch($0).contains(needle) }) { extraTags.append(tag) }
    }
    let extras = vocabTerms(tags: extraTags, lexemes: lexemes, cards: cards, starred: starred, now: now, verbs: verbs)
    return matched + extras
}

/// Lesson and unit titles share one segmented row, so a long one is shortened (Android scopeLabel).
public func scopeLabel(_ title: String) -> String {
    let max = 18
    if title.count <= max { return title }
    let head = String(title.prefix(max - 1)).trimmingCharacters(in: .whitespaces)
    return head + "\u{2026}"
}
