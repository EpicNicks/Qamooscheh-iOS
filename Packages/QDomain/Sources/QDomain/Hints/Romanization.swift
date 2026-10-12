import Foundation
import QModel

// Course-wide native word -> hover hint, derived straight from lexemes.json's
// own tag format (tag is always "<surface><pos>[<register>]", e.g.
// "سلام<interj><spoken>" -> gloss "hello"). The surface text before the first
// "<" IS the literal word every tile/prompt renders, so no per-exercise
// alignment against `tags`/`answer` is needed: any native word anywhere in the
// course (a word-bank tile, including a decoy borrowed from another exercise,
// or a prompt written in the target language) gets its hint the moment its
// lexeme exists. Built once per lexeme index and reused across every exercise.
// Port of web romanization.ts.

/// What a hovered/focused word can offer, plus what an annotated rendering
/// needs to show a reading above (or substitute for) the native surface.
/// Which of these actually renders is up to the viewer's TextDisplaySettings.
public struct WordHint: Equatable, Sendable {
    public var translation: String
    /// Latin transliteration: the tooltip's phonetic line, and the on-screen base text in "romanized" display.
    public var romanization: String?
    /// The small text printed above this surface in "both" display. Persian has no separate reading, so for fa they're the same.
    public var ruby: String?
    /// Shown after the translation in the tooltip ("house [informal]"). `.both` or nil means it isn't specific to one, so nothing is shown.
    public var register: Register?
    /// Set when the word as written carries an ezafe mark. Kept apart from `romanization` (the bare word's) so the display can show it as its own piece.
    public var ezafe: Ezafe?
    /// Every lexeme written this way, with its part of speech: how attached endings tell an ending's senses apart (ـم "my" after a noun, "am" after an adjective).
    public var senses: [WordSense]?
    /// The infinitive to look up in the verb index, when a verb lexeme is written this way.
    public var verbLemma: String?

    public init(
        translation: String,
        romanization: String?,
        ruby: String?,
        register: Register? = nil,
        ezafe: Ezafe? = nil,
        senses: [WordSense]? = nil,
        verbLemma: String? = nil
    ) {
        self.translation = translation
        self.romanization = romanization
        self.ruby = ruby
        self.register = register
        self.ezafe = ezafe
        self.senses = senses
        self.verbLemma = verbLemma
    }
}

public struct WordSense: Equatable, Sendable {
    /// The lexeme's whole tag, e.g. "ـم<poss>", also on an entry for one of its `forms`, so an exercise's `tags` can pick it out.
    public var tag: String
    /// The tag's part-of-speech markers, e.g. "<poss>" or "<v><spoken>".
    public var pos: String
    public var translation: String
    public var romanization: String?

    public init(tag: String, pos: String, translation: String, romanization: String?) {
        self.tag = tag
        self.pos = pos
        self.translation = translation
        self.romanization = romanization
    }
}

/// The tooltip label for a register; nothing for a word that isn't specific to one.
public func registerLabel(_ register: Register?) -> String? {
    switch register {
    case .spoken: return "informal"
    case .written: return "formal"
    default: return nil
    }
}

/// The infinitive whose forms a lexeme can show: its `lemma`, when it's a verb.
private func verbLemmaOf(_ entry: LexemeIndexEntry) -> String? {
    guard entry.pos == "verb", let lemma = entry.lemma, !lemma.isEmpty else { return nil }
    return lemma
}

/// Builds the hint map from lexemes.json's entries IN AUTHORED ORDER (a JSON
/// object keeps its keys' order on the web; a Swift Dictionary does not, and the
/// order decides which homograph's romanization wins and the order of senses).
public func buildLexemeHintMap(_ lexemeIndex: [(tag: String, entry: LexemeIndexEntry)]?) -> [String: WordHint] {
    var map: [String: WordHint] = [:]
    guard let lexemeIndex = lexemeIndex else { return map }
    for (tag, entry) in lexemeIndex {
        let surface = tagSurface(tag)
        if surface.isEmpty { continue }
        let posStart = tag.unicodeScalars.index(tag.unicodeScalars.startIndex, offsetBy: surface.unicodeScalars.count)
        let pos = String(tag.unicodeScalars[posStart...])
        let sense = WordSense(tag: tag, pos: pos, translation: entry.gloss, romanization: entry.romanization)
        for written in [surface] + (entry.forms ?? []) {
            // Two lexemes can share a surface (the same word tagged as a noun and
            // a verb, or in two registers): merge onto what's already there, so a
            // homograph missing a romanization can never clobber a sibling that has one.
            let existing = map[written]
            let register: Register?
            if let existing = existing, existing.register != entry.register {
                // The same surface in two registers is used in both, so it gets
                // no label rather than whichever sibling happened to come first.
                register = .both
            } else {
                register = entry.register
            }
            map[written] = WordHint(
                translation: existing?.translation ?? entry.gloss,
                // The iOS lexeme contract has no separate `reading` (Japanese furigana), so ruby is the romanization.
                romanization: existing?.romanization ?? entry.romanization,
                ruby: existing?.ruby ?? entry.romanization,
                register: register,
                senses: (existing?.senses ?? []) + [sense],
                verbLemma: existing?.verbLemma ?? verbLemmaOf(entry)
            )
        }
    }
    return map
}

/// Shared empty instance for "hints are off/not applicable right now".
public let emptyHintMap: [String: WordHint] = [:]

/// Everything that decides how a word/tile/prompt renders: which script is the
/// base line (and whether a reading is printed above it), and the learner's
/// independent local hint toggles. Threaded down alongside the hint map so the
/// renderer decides per word what to show, rather than this module
/// pre-formatting strings for it.
public struct TextDisplaySettings: Equatable, Sendable {
    public var display: ScriptDisplay
    public var translationEnabled: Bool
    public var romanizationEnabled: Bool
    /// Hovering an English prompt word shows the course-language word for it (showNativeHints).
    public var nativeEnabled: Bool
    /// Show native text's reading aids (vowel and ezafe marks) rather than stripping them (showVowelMarks).
    public var vowelMarks: Bool
    /// Show a native sentence's whole romanization above it (showSentenceRomanization).
    public var sentenceRomanization: Bool

    public init(
        display: ScriptDisplay,
        translationEnabled: Bool,
        romanizationEnabled: Bool,
        nativeEnabled: Bool,
        vowelMarks: Bool,
        sentenceRomanization: Bool
    ) {
        self.display = display
        self.translationEnabled = translationEnabled
        self.romanizationEnabled = romanizationEnabled
        self.nativeEnabled = nativeEnabled
        self.vowelMarks = vowelMarks
        self.sentenceRomanization = sentenceRomanization
    }

    /// "Nothing enabled, native display": the matched pair to `emptyHintMap` for a caller that passes no settings.
    public static let plain = TextDisplaySettings(
        display: .native,
        translationEnabled: false,
        romanizationEnabled: false,
        nativeEnabled: false,
        vowelMarks: false,
        sentenceRomanization: false
    )
}

/// Whether the course-wide hint map should be handed to this exercise's
/// components, or the shared empty one. It's needed for the learner's hint
/// toggles, or for a non-native display (romanized substitution and ruby both
/// need the map), and moot when this exercise's own scriptMode isn't native (a
/// romanized-authored exercise is already Latin).
///
/// Deliberately NOT gated on the learner's own scriptMode preference: stories,
/// conversations and songs are served in authored order whatever that
/// preference is, so a "romanized" display doesn't mean no native text is on
/// screen. Whether native text is present is a fact about THIS exercise.
public func gateLexemeHintMap(
    _ courseMap: [String: WordHint],
    settings: TextDisplaySettings,
    exerciseScriptMode: ExerciseScriptMode
) -> [String: WordHint] {
    // The sentence romanization needs it too, for a sentence with no authored
    // romanization (romanizeSentence).
    let nothingToShow = !settings.translationEnabled
        && !settings.romanizationEnabled
        && !settings.sentenceRomanization
        && settings.display == .native
    // The English side's hovers look lexemes up here too, whatever script the exercise itself is in.
    if settings.nativeEnabled { return courseMap }
    if nothingToShow || exerciseScriptMode != .native { return emptyHintMap }
    return courseMap
}
