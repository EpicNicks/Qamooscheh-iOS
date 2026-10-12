// Port of web:src/domain/persian/abjadSearch.ts (Android: AbjadSearch.kt).
//
// Parsing for the abjad glossary's letter search: each valid character typed
// becomes a token that selects one or more letters, and anything else is
// dropped. A Persian letter selects just itself; a Latin character selects
// every letter it romanizes to. The digraphs sh/kh/gh/zh are built when an "h"
// follows an s/k/g/z token, and "c" waits in `pending` for its "h".

import Foundation

public struct LetterSearchToken: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case persian, latin
    }

    /// Unique per token ("fa:ث" or "latin:s") so the same search can't be added twice.
    public let key: String
    public let kind: Kind
    /// What the chip shows: the letter itself, or the Latin text typed.
    public let label: String
    /// The letters this token selects, in alphabet order.
    public let letters: [String]

    public init(key: String, kind: Kind, label: String, letters: [String]) {
        self.key = key
        self.kind = kind
        self.label = label
        self.letters = letters
    }
}

public struct LetterSearchResult: Equatable, Sendable {
    public let tokens: [LetterSearchToken]
    /// What the input should keep showing.
    public let pending: String

    public init(tokens: [LetterSearchToken], pending: String) {
        self.tokens = tokens
        self.pending = pending
    }
}

private func bySound(_ sounds: SoundId...) -> [String] {
    abjadLetters.filter { sounds.contains($0.sound) }.map { $0.letter }
}

private let consonants: [SoundId] = [.b, .p, .t, .s, .j, .ch, .h, .kh, .d, .z, .r, .zh, .sh, .gh, .f, .k, .g, .l, .m, .n]

/// Latin text to the letters it can be spelled with.
public let latinSearch: [String: [String]] = {
    var map: [String: [String]] = [:]
    for sound in consonants { map[sound.rawValue] = bySound(sound) }
    map["a"] = bySound(.a)
    map["e"] = bySound(.a)
    map["o"] = bySound(.a, .v)
    map["u"] = bySound(.v)
    map["v"] = bySound(.v)
    map["w"] = bySound(.v)
    map["i"] = bySound(.y)
    map["y"] = bySound(.y)
    // ق specifically (the common "q" romanization), not غ as well.
    map["q"] = ["ق"]
    map["'"] = bySound(.glottal)
    map["\u{2019}"] = bySound(.glottal)
    return map
}()

private let digraphFirsts: Set<String> = ["s", "k", "g", "z"]
private let persianLetters: Set<String> = Set(abjadLetters.map { $0.letter })

// Arabic-keyboard look-alikes of Persian letters. NFD already splits
// آ/أ/إ/ؤ/ئ into a base letter plus a combining mark.
private let persianEquivalents: [String: String] = [
    "\u{064A}": "\u{06CC}", // Arabic yeh -> Persian yeh
    "\u{0649}": "\u{06CC}", // alef maksura -> Persian yeh
    "\u{0643}": "\u{06A9}", // Arabic kaf -> Persian kaf
    "\u{0629}": "\u{0647}", // teh marbuta -> heh
]

private func persianToken(_ letter: String) -> LetterSearchToken {
    LetterSearchToken(key: "fa:\(letter)", kind: .persian, label: letter, letters: [letter])
}

private func latinToken(_ text: String) -> LetterSearchToken {
    LetterSearchToken(key: "latin:\(text)", kind: .latin, label: text, letters: latinSearch[text] ?? [])
}

/// Appends `token`, or moves an identical existing one to the end.
private func add(_ tokens: [LetterSearchToken], _ token: LetterSearchToken) -> [LetterSearchToken] {
    tokens.filter { $0.key != token.key } + [token]
}

/// Folds newly typed `text` (the previous pending plus what was typed) into the existing tokens.
public func parseLetterSearch(_ text: String, _ tokens: [LetterSearchToken]) -> LetterSearchResult {
    var next = tokens
    var pending = ""

    // NFD splits ā into a + combining macron (dropped below), and آ into ا + madde.
    // Iterate unicode scalars (code points), like the web's for...of, not grapheme clusters.
    let normalized = text.decomposedStringWithCanonicalMapping.lowercased()
    for scalar in normalized.unicodeScalars {
        let raw = String(scalar)
        let char = persianEquivalents[raw] ?? raw

        if persianLetters.contains(char) {
            pending = ""
            next = add(next, persianToken(char))
            continue
        }

        if pending == "c" {
            pending = ""
            if char == "h" {
                next = add(next, latinToken("ch"))
                continue
            }
        }

        if char == "h", let last = next.last, last.kind == .latin, digraphFirsts.contains(last.label) {
            next = add(Array(next.dropLast()), latinToken("\(last.label)h"))
        } else if char == "c" {
            pending = "c"
        } else if latinSearch[char] != nil {
            next = add(next, latinToken(char))
        }
    }

    return LetterSearchResult(tokens: next, pending: pending)
}

/// The letters any token selects, distinct, in token order. nil when there are no tokens (no filter, not "nothing matches").
public func lettersMatching(_ tokens: [LetterSearchToken]) -> [String]? {
    if tokens.isEmpty { return nil }
    var seen = Set<String>()
    var result: [String] = []
    for letter in tokens.flatMap({ $0.letters }) where seen.insert(letter).inserted {
        result.append(letter)
    }
    return result
}
