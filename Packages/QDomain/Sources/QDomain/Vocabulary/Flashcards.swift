import Foundation
import QModel

// Saved-word flashcards: self-rated and translation (type the meaning). A
// translation card is graded on the device against the lexeme's English gloss;
// glosses are written for reading, so the gloss is first turned into the
// answers it implies and a typed answer only has to match one loosely.
// Port of web flashcards.ts (Android Flashcards.kt).

// JS `\s`, spelled out (ICU's own \s differs).
private let jsSpace = "\\t\\n\\u000B\\f\\r \\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000\\uFEFF"

private let apostrophes = try! NSRegularExpression(pattern: "[\u{2019}']")
private let notWord = try! NSRegularExpression(pattern: "[^\\p{L}\\p{N}\(jsSpace)]")
private let spaces = try! NSRegularExpression(pattern: "[\(jsSpace)]+")
private let aside = try! NSRegularExpression(pattern: "\\([^)]*\\)")
private let quotes = try! NSRegularExpression(pattern: "[\"\u{201C}\u{201D}]")
private let edgeQuote = try! NSRegularExpression(pattern: "^[\(jsSpace)]*'|'[\(jsSpace)]*$")
private let alternatives = try! NSRegularExpression(pattern: "[/;,]")
private let wordSlash = try! NSRegularExpression(pattern: "(\\S+)[\(jsSpace)]*/[\(jsSpace)]*(\\S+)")

private func replacing(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
    let range = NSRange(location: 0, length: (text as NSString).length)
    return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
}

private func splitting(_ regex: NSRegularExpression, _ text: String) -> [String] {
    let ns = text as NSString
    var parts: [String] = []
    var start = 0
    for match in regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
        parts.append(ns.substring(with: NSRange(location: start, length: match.range.location - start)))
        start = match.range.location + match.range.length
    }
    parts.append(ns.substring(from: start))
    return parts
}

/// Lowercased, punctuation and extra spaces gone, articles and a leading infinitive "to" dropped: "To the Bazaar!" and "bazaar" compare equal.
public func normalizeMeaning(_ text: String) -> String {
    var s = text.lowercased()
    s = replacing(apostrophes, in: s, with: "")
    s = replacing(notWord, in: s, with: " ")
    let words = splitting(spaces, s).filter { !$0.isEmpty && $0 != "a" && $0 != "an" && $0 != "the" }
    let joined = words.joined(separator: " ")
    return joined.hasPrefix("to ") ? String(joined.dropFirst(3)) : joined
}

/// Every answer a gloss accepts, normalized. Parenthesized asides and quotes
/// are dropped; alternatives split on "/", ";" and ","; and a slash between two
/// single words is also expanded in place ("he / she cooks" accepts "he cooks"
/// and "she cooks" as well as the whole phrase).
public func glossAnswers(_ gloss: String) -> [String] {
    var cleaned = replacing(aside, in: gloss, with: " ")
    cleaned = replacing(quotes, in: cleaned, with: " ")
    cleaned = replacing(edgeQuote, in: cleaned, with: " ")

    var answers: [String] = []
    func add(_ text: String) {
        let normalized = normalizeMeaning(text)
        if !normalized.isEmpty && !answers.contains(normalized) { answers.append(normalized) }
    }

    add(cleaned)
    for part in splitting(alternatives, cleaned) { add(part) }

    let ns = cleaned as NSString
    if let match = wordSlash.firstMatch(in: cleaned, options: [], range: NSRange(location: 0, length: ns.length)) {
        let before = ns.substring(to: match.range.location)
        let after = ns.substring(from: match.range.location + match.range.length)
        add(before + ns.substring(with: match.range(at: 1)) + after)
        add(before + ns.substring(with: match.range(at: 2)) + after)
    }
    return answers
}

/// Whether two strings are at most one edit apart: an insertion, deletion, substitution, or two neighbouring letters swapped (the commonest typo). Compared by UTF-16 unit, like the web and Android.
private func withinOneEdit(_ left: String, _ right: String) -> Bool {
    if left == right { return true }
    let a = Array(left.utf16)
    let b = Array(right.utf16)
    if abs(a.count - b.count) > 1 { return false }
    if a.count == b.count {
        var diffs: [Int] = []
        for k in 0..<a.count where a[k] != b[k] { diffs.append(k) }
        if diffs.count == 2 && diffs[1] == diffs[0] + 1 && a[diffs[0]] == b[diffs[1]] && a[diffs[1]] == b[diffs[0]] {
            return true
        }
    }
    var i = 0
    var j = 0
    var edits = 0
    while i < a.count && j < b.count {
        if a[i] == b[j] {
            i += 1
            j += 1
            continue
        }
        edits += 1
        if edits > 1 { return false }
        if a.count > b.count {
            i += 1
        } else if b.count > a.count {
            j += 1
        } else {
            i += 1
            j += 1
        }
    }
    return edits + (a.count - i) + (b.count - j) <= 1
}

/// Whether a typed meaning answers a translation card. One typo is forgiven in an answer of five letters or more.
public func gradeTranslation(_ typed: String, gloss: String) -> Bool {
    let answer = normalizeMeaning(typed)
    if answer.isEmpty { return false }
    return glossAnswers(gloss).contains { accepted in
        accepted == answer || (accepted.utf16.count >= 5 && withinOneEdit(accepted, answer))
    }
}

/// A saved word as a card: `surface` is the word as written, attributes stripped.
public struct FlashcardWord: Equatable, Sendable {
    public var tag: String
    public var surface: String
    public var entry: LexemeIndexEntry

    public init(tag: String, surface: String, entry: LexemeIndexEntry) {
        self.tag = tag
        self.surface = surface
        self.entry = entry
    }
}

/// The saved words this course can show as cards: saved tags (in the order
/// given, most recently saved first) that are in the course's lexeme index. An
/// attached ending (leading tatweel, e.g. "my") is a lexeme but not a word
/// you'd drill on its own, so it's left out.
public func flashcardWords(savedTags: [String], lexemeIndex: [String: LexemeIndexEntry]?) -> [FlashcardWord] {
    guard let lexemeIndex = lexemeIndex else { return [] }
    var words: [FlashcardWord] = []
    for tag in savedTags {
        guard let entry = lexemeIndex[tag] else { continue }
        let surface = parseLexemeTag(tag).surface
        if surface.isEmpty || surface.unicodeScalars.first == "\u{0640}" { continue }
        words.append(FlashcardWord(tag: tag, surface: surface, entry: entry))
    }
    return words
}

/// XP a correct card earns, mirroring the server's SavedWords:FlashcardXp: for the recap's estimate only; the server's award is what counts.
public let flashcardXP = 5
