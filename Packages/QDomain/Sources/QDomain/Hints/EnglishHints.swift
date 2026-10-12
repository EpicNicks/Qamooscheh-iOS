import Foundation

// Hover hints the other way round: an English word in a prompt shows the
// Persian for it. Matched only against the lexemes THIS exercise is tagged
// with, since its `tags` are exactly the words it drills, so "you" or "is"
// can't pick up one of the dozens of lexemes whose gloss mentions them
// course-wide. For "My mother is tired" tagged مادر, خسته, ـم and است,
// "mother" -> مادر, "tired" -> خسته, "my" -> ـم, "is" -> است.
// Port of web englishHints.ts (which is ahead of the Android port: it also
// reads a present-tense verb gloss as the progressive, and takes -ing back to
// its verb).

/// What an English word's hover shows: the lexeme as it's written, and its romanization.
public struct NativeHint: Equatable, Sendable {
    public var native: String
    public var romanization: String?

    public init(native: String, romanization: String?) {
        self.native = native
        self.romanization = romanization
    }
}

public struct EnglishCandidate: Equatable, Sendable {
    /// The gloss alternative, lowercased, as words ("thank you" -> ["thank", "you"]).
    public var words: [String]
    /// For a progressive reading (progressiveForms), its last word must be written with -ing: "is open" is a state, not "is opening".
    public var progressive: Bool
    public var hint: NativeHint

    public init(words: [String], progressive: Bool = false, hint: NativeHint) {
        self.words = words
        self.progressive = progressive
        self.hint = hint
    }
}

/// Longest English phrase tried as one match ("thank you very much").
private let maxPhraseWords = 4

/// JavaScript's `\s`, spelled out for use inside a regex character class.
private let jsSpaceClass = "\\t\\n\\u000B\\f\\r \\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000\\uFEFF"

private func isLetterOrNumber(_ s: Unicode.Scalar) -> Bool {
    switch s.properties.generalCategory {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
         .decimalNumber, .letterNumber, .otherNumber:
        return true
    default:
        return false
    }
}

private func isLetter(_ s: Unicode.Scalar) -> Bool {
    switch s.properties.generalCategory {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
        return true
    default:
        return false
    }
}

/// `text` split on JavaScript whitespace, empty pieces dropped.
private func splitOnSpace(_ text: String) -> [String] {
    var out: [String] = []
    var current = String.UnicodeScalarView()
    for scalar in text.unicodeScalars {
        if isJSWhitespace(scalar) {
            if !current.isEmpty {
                out.append(String(current))
                current = String.UnicodeScalarView()
            }
        } else {
            current.append(scalar)
        }
    }
    if !current.isEmpty { out.append(String(current)) }
    return out
}

private func words(_ text: String) -> [String] {
    let lowered = text.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
    var out: [String] = []
    for part in splitOnSpace(lowered) {
        let scalars = Array(part.unicodeScalars)
        var start = 0
        var end = scalars.count
        while start < end && !(isLetterOrNumber(scalars[start]) || scalars[start] == "'") { start += 1 }
        while end > start && !(isLetterOrNumber(scalars[end - 1]) || scalars[end - 1] == "'") { end -= 1 }
        if start < end {
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars[start..<end])
            out.append(String(view))
        }
    }
    return out
}

private let alternativeSeparator = try! NSRegularExpression(
    pattern: "[\(jsSpaceClass)]*[;,][\(jsSpaceClass)]*|[\(jsSpaceClass)]+/[\(jsSpaceClass)]+"
)
private let parenthesized = try! NSRegularExpression(pattern: "\\([^)]*\\)")

private func splitByRegex(_ text: String, _ regex: NSRegularExpression) -> [String] {
    let ns = text as NSString
    var out: [String] = []
    var cursor = 0
    for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
        out.append(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
        cursor = match.range.location + match.range.length
    }
    out.append(ns.substring(from: cursor))
    return out
}

/// A gloss's alternative phrasings, each as words. Alternatives are split on
/// ";", "," and a spaced " / " ("I / me"), and a shorter one borrows the last
/// one's trailing words ("he / she came" -> "he came", "she came"); a slash
/// inside a word ("he/she wants") gives every combination. Parenthesized
/// words drop out ("(that) you go" -> "you go").
private func glossPhrases(_ gloss: String) -> [[String]] {
    var pieces: [[String]] = []
    for piece in splitByRegex(gloss, alternativeSeparator) {
        let range = NSRange(location: 0, length: (piece as NSString).length)
        let stripped = parenthesized.stringByReplacingMatches(in: piece, range: range, withTemplate: " ")
        let split = splitOnSpace(stripped)
        if !split.isEmpty { pieces.append(split) }
    }
    let last = pieces.last ?? []
    var phrases: [[String]] = []
    for piece in pieces {
        let full = piece.count < last.count ? piece + Array(last[piece.count...]) : piece
        var combos: [[String]] = [[]]
        for word in full {
            let alternatives = word.components(separatedBy: "/").filter { !$0.isEmpty }
            var next: [[String]] = []
            for combo in combos {
                for alternative in alternatives { next.append(combo + [alternative]) }
            }
            combos = next
        }
        for combo in combos { phrases.append(words(combo.joined(separator: " "))) }
    }
    return phrases
}

/// Extra English a prompt uses for a single-word gloss. یک "one" is usually the
/// article "a" / "an"; a pronoun after an ezafe is a possessive (برادرِ من, "my
/// brother"); and a few glosses have an everyday English twin (در "in" / "at",
/// خوب "good" / "well", خانه "home" / "house"). Safe to be generous here: only
/// the exercise's own lexemes are ever matched.
private let promptEquivalents: [String: [String]] = [
    "one": ["a", "an"],
    "i": ["my", "me"],
    "me": ["my"],
    "we": ["our", "us"],
    "you": ["your"],
    "he": ["his", "him"],
    "she": ["her"],
    "they": ["their", "them"],
    "in": ["at", "inside"],
    "good": ["well", "fine"],
    "home": ["house"],
]

/// The "be" a subject pronoun takes, for a verb gloss's progressive reading.
private let beForSubject: [String: String] = ["i": "am", "you": "are", "we": "are", "they": "are", "he": "is", "she": "is", "it": "is"]

/// A third-person verb back to its base form ("buys" -> buy, "watches" -> watch, "carries" -> carry, "has" -> have).
private func baseVerb(_ verb: String) -> String {
    if verb == "has" { return "have" }
    if verb.hasSuffix("ies") { return String(verb.dropLast(3)) + "y" }
    for suffix in ["ses", "xes", "zes", "ches", "shes", "oes"] where verb.hasSuffix(suffix) {
        return String(verb.dropLast(2))
    }
    if verb.hasSuffix("s") && !verb.hasSuffix("ss") { return String(verb.dropLast(1)) }
    return verb
}

/// Persian's present tense is English's simple and progressive present both:
/// می‌خرم, glossed "I buy", is just as much "I am buying". So a
/// subject-and-verb gloss also reads as subject + be + verb, and as be + verb
/// alone for "I'm buying" (whose "I'm" stands for "am"), and an infinitive
/// gloss ("to build") reads as any be + verb ("are building"). The verb is left
/// in its base form; wordForms takes a prompt's "buying" back to it.
private func progressiveForms(_ phrase: [String], _ pos: String) -> [[String]] {
    if !pos.hasPrefix("<v>") || phrase.count != 2 { return [] }
    // An infinitive gloss ("to build") has no subject to agree with: any "be" will do.
    if phrase[0] == "to" { return ["am", "is", "are"].map { [$0, phrase[1]] } }
    guard let be = beForSubject[phrase[0]] else { return [] }
    let subject = phrase[0]
    let verb = phrase[1]
    let base = be == "is" ? baseVerb(verb) : verb
    return [
        [subject, be, base],
        [be, base],
    ]
}

/// Every English phrasing of this exercise's lexemes. A gloss is trimmed of
/// its authoring notes (tidyGloss) and split into its alternatives
/// (glossPhrases), a verb's "to" is optional ("to have" also matches "have"),
/// and "I buy" also matches "I am buying" (progressiveForms). A tag's own sense
/// is used when its surface has several (ـم is both "my" and "am"). Suffix-only
/// alternatives ("-er") are skipped: no English word is spelled that way.
public func englishCandidates(_ tags: [String], _ hintMap: [String: WordHint]) -> [EnglishCandidate] {
    var own: [EnglishCandidate] = []
    var borrowed: [EnglishCandidate] = []
    for tag in tags {
        let surface = tagSurface(tag)
        guard !surface.isEmpty, let hint = hintMap[surface] else { continue }
        let scalars = tag.unicodeScalars
        let posStart = scalars.index(scalars.startIndex, offsetBy: surface.unicodeScalars.count)
        let pos = String(scalars[posStart...])
        let sense = hint.senses?.first { $0.pos == pos }
        let translation = sense?.translation ?? hint.translation
        let romanization = sense != nil ? sense?.romanization : hint.romanization
        let native = NativeHint(native: surface, romanization: romanization)
        for phrase in glossPhrases(tidyGloss(translation)) {
            if phrase.isEmpty || phrase[0].hasPrefix("-") { continue }
            let forms: [[String]] = (phrase[0] == "to" && phrase.count > 1) ? [phrase, Array(phrase.dropFirst())] : [phrase]
            for form in forms { own.append(EnglishCandidate(words: form, hint: native)) }
            for form in progressiveForms(phrase, pos) {
                own.append(EnglishCandidate(words: form, progressive: true, hint: native))
            }
            if phrase.count == 1 {
                for w in promptEquivalents[phrase[0]] ?? [] { borrowed.append(EnglishCandidate(words: [w], hint: native)) }
            }
        }
    }
    // A lexeme whose own gloss says the word beats one that only borrows it:
    // in "for my mother", "my" is ـم ("my"), not من ("I", which also reads "my").
    var candidates: [EnglishCandidate] = []
    var seen = Set<String>()
    for candidate in own + borrowed {
        let key = candidate.words.joined(separator: " ")
        if seen.contains(key) { continue }
        seen.insert(key)
        candidates.append(candidate)
    }
    return candidates
}

/// The second half of a contraction, spelled out.
private let contractions: [String: String] = ["m": "am", "s": "is", "re": "are", "ve": "have", "ll": "will", "d": "would"]

private func isAsciiLower(_ s: String) -> Bool {
    return !s.isEmpty && s.unicodeScalars.allSatisfy { $0.value >= 0x61 && $0.value <= 0x7A }
}

/// A prompt word and the base forms it could be ("books" -> book, "watches" ->
/// watch, "cities" -> city, "buying" -> buy, "making" -> make, "running" ->
/// run, "lying" -> lie), and either half of a contraction ("I'm" -> I or am,
/// "it's" -> it or is, "we're" -> we or are).
private func wordForms(_ word: String) -> [String] {
    var forms = [word]
    let halves = word.components(separatedBy: "'")
    if halves.count == 2, isAsciiLower(halves[0]), isAsciiLower(halves[1]), let spelled = contractions[halves[1]] {
        forms.append(halves[0])
        forms.append(spelled)
    }
    if word.hasSuffix("ies") { forms.append(String(word.dropLast(3)) + "y") }
    if word.hasSuffix("es") { forms.append(String(word.dropLast(2))) }
    if word.hasSuffix("s") && !word.hasSuffix("ss") { forms.append(String(word.dropLast(1))) }
    if word.hasSuffix("ing") && word.utf16.count > 4 {
        let stem = String(word.dropLast(3))
        forms.append(stem)
        forms.append(stem + "e")
        let tail = Array(stem)
        if tail.count >= 2, tail[tail.count - 1] == tail[tail.count - 2], !"aeiouy".contains(tail[tail.count - 1]) {
            forms.append(String(stem.dropLast(1)))
        }
        if word.hasSuffix("ying") { forms.append(String(word.dropLast(4)) + "ie") }
    }
    return forms
}

public struct EnglishSegment: Equatable, Sendable {
    public var text: String
    public var isWord: Bool
    public var hint: NativeHint?

    public init(text: String, isWord: Bool, hint: NativeHint?) {
        self.text = text
        self.isWord = isWord
        self.hint = hint
    }
}

private struct RunWord {
    var forms: [String]
    var end: Int
}

/// Anything but whitespace, an apostrophe or a hyphen: a phrase never spans it.
private func breaksPhrase(_ text: String) -> Bool {
    return text.unicodeScalars.contains { !(isJSWhitespace($0) || $0 == "'" || $0 == "\u{2019}" || $0 == "-") }
}

/// `text` split for rendering, the same way segmentAnnotatedText splits native
/// text: greedy longest phrase match (up to maxPhraseWords words), everything
/// between words passed through as-is, and a word with no match left plain.
public func segmentEnglish(_ text: String, _ candidates: [EnglishCandidate]) -> [EnglishSegment] {
    let pieces = segmentWords(text)
    var segments: [EnglishSegment] = []
    var i = 0
    while i < pieces.count {
        if !pieces[i].isWord {
            segments.append(EnglishSegment(text: pieces[i].text, isWord: false, hint: nil))
            i += 1
            continue
        }
        // The word pieces from i on, and where each one ends.
        var run: [RunWord] = []
        var j = i
        while j < pieces.count && run.count < maxPhraseWords {
            if !pieces[j].isWord {
                if breaksPhrase(pieces[j].text) { break }
                j += 1
                continue
            }
            guard let word = words(pieces[j].text).first else { break }
            run.append(RunWord(forms: wordForms(word), end: j + 1))
            j += 1
        }
        var matchEnd: Int? = nil
        var matchHint: NativeHint? = nil
        var length = run.count
        while length > 0 && matchEnd == nil {
            let fits = candidates.filter { c in
                guard c.words.count == length else { return false }
                for (k, word) in c.words.enumerated() where !run[k].forms.contains(word) { return false }
                return !c.progressive || run[length - 1].forms[0].hasSuffix("ing")
            }
            // A word as written beats a form derived from it: "evening" is the
            // evening's lexeme before it's "even" + -ing.
            let asWritten = fits.first { c in
                for (k, word) in c.words.enumerated() where run[k].forms[0] != word { return false }
                return true
            }
            if let hit = asWritten ?? fits.first {
                matchEnd = run[length - 1].end
                matchHint = hit.hint
            }
            length -= 1
        }
        let end = matchEnd ?? (i + 1)
        segments.append(EnglishSegment(
            text: pieces[i..<end].map { $0.text }.joined(),
            isWord: true,
            hint: matchHint
        ))
        i = end
    }
    return segments
}

private let nonLatinLetter = try! NSRegularExpression(pattern: "[^\\p{script=Latin}\\P{L}]")

/// Whether `text` is written in Latin letters only: an English (or romanized) prompt, not a native one.
public func isLatinText(_ text: String) -> Bool {
    guard text.unicodeScalars.contains(where: { isLetter($0) }) else { return false }
    let range = NSRange(location: 0, length: (text as NSString).length)
    return nonLatinLetter.firstMatch(in: text, range: range) == nil
}
