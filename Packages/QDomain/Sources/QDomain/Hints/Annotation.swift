import Foundation
import QModel

// How native-script text actually renders on screen, driven by the learner's
// script-display preference (prefs' scriptMode, plus Japanese's local
// showFurigana toggle). Port of web annotation.ts (Android shape).

/// The same three values as ScriptMode, kept distinct since this is a DISPLAY
/// decision, derived from (not identical in meaning to) the server-side
/// session-planning preference it's read from.
public enum ScriptDisplay: String, Equatable, Hashable, Sendable, CaseIterable {
    case native
    case romanized
    case both
}

/// What the base line shows, and whether a reading is printed above it,
/// derived from the learner's scriptMode preference plus Japanese's own local
/// furigana toggle (scriptMode alone has no place to encode "show readings"
/// independent of "which script does session planning prefer").
public func resolveScriptDisplay(scriptMode: ScriptMode?, language: String?, showFurigana: Bool) -> ScriptDisplay {
    if scriptMode == .romanized { return .romanized }
    if scriptMode == .both { return .both }
    // Native (or no preference yet, e.g. still loading): Japanese's furigana
    // toggle predates this preference and has to keep working through it.
    return language == "ja" && showFurigana ? .both : .native
}

/// Longest lexeme surface, in word tokens, across every shipped course (fa: 3,
/// e.g. "هر از گاهی"). Caps segmentAnnotatedText's greedy longest match.
/// Overshooting is harmless: a language with no multi-word lexemes never gets
/// a phrase hit.
public let maxPhraseTokens = 3

public struct TextPiece: Equatable, Sendable {
    public var text: String
    /// Word-like pieces get a hint lookup; the rest (spaces, punctuation) render as-is.
    public var isWord: Bool

    public init(text: String, isWord: Bool) {
        self.text = text
        self.isWord = isWord
    }
}

private let segZwnj: Unicode.Scalar = "\u{200C}"

private func isAllZwnj(_ s: String) -> Bool {
    return !s.isEmpty && s.unicodeScalars.allSatisfy { $0 == segZwnj }
}

/// Splits a run between two words into pieces: a whitespace run stays one
/// piece (as in UAX #29), every other character is its own piece.
private func gapPieces(_ gap: Substring) -> [TextPiece] {
    var pieces: [TextPiece] = []
    var whitespaceRun = ""
    func flush() {
        if !whitespaceRun.isEmpty {
            pieces.append(TextPiece(text: whitespaceRun, isWord: false))
            whitespaceRun = ""
        }
    }
    for ch in gap {
        if ch.unicodeScalars.allSatisfy({ isJSWhitespace($0) }) {
            whitespaceRun.append(ch)
        } else {
            flush()
            pieces.append(TextPiece(text: String(ch), isWord: false))
        }
    }
    flush()
    return pieces
}

/// Where a word ends, for lookup purposes. Whitespace can't answer that:
/// Japanese writes `こんにちは、元気ですか` with no spaces at all, so a
/// whitespace split hands the hint map one enormous "word" that matches
/// nothing. Foundation's word enumeration applies the platform's word
/// boundaries (ICU, with dictionary segmentation for the scripts that don't
/// space their words), which land where whitespace did for Persian and also
/// split off punctuation, so `سلام،` finds `سلام`. A ZWNJ stays inside its
/// word, so an isolated-letterform Persian spelling still looks up as one
/// surface (re-joined here if the platform splits there).
public func segmentWords(_ text: String) -> [TextPiece] {
    var wordRanges: [Range<String.Index>] = []
    text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { _, range, _, _ in
        wordRanges.append(range)
    }

    var pieces: [TextPiece] = []
    var cursor = text.startIndex
    for range in wordRanges {
        if cursor < range.lowerBound {
            let gap = text[cursor..<range.lowerBound]
            if isAllZwnj(String(gap)), let last = pieces.last, last.isWord {
                pieces[pieces.count - 1].text += String(gap) + String(text[range])
                cursor = range.upperBound
                continue
            }
            pieces.append(contentsOf: gapPieces(gap))
        }
        pieces.append(TextPiece(text: String(text[range]), isWord: true))
        cursor = range.upperBound
    }
    if cursor < text.endIndex {
        pieces.append(contentsOf: gapPieces(text[cursor..<text.endIndex]))
    }
    return pieces
}

/// One word's hint: its own entry; failing that, a known stem with endings
/// attached (مادرم = mother + -am); and either of those under an ezafe mark
/// (کتابِ = book + -e). Looked up without its reading aids (کِتاب is کتاب),
/// the ezafe mark first, since it's one of them. `tags` (the exercise's own)
/// say which stem and endings a word is made of.
private func wordHint(_ word: String, _ hintMap: [String: WordHint], _ tags: Set<String>) -> WordHint? {
    let lookup: (String) -> WordHint? = { bare in
        hintMap[bare] ?? attachedEndingsHint(bare, hintMap, tags: tags)
    }
    return ezafeHint(word, lookup: lookup) ?? lookup(PersianNormalize.stripReadingAids(word))
}

public struct AnnotatedSegment: Equatable, Sendable {
    /// The literal source substring this segment covers, spaces between phrase tokens included verbatim.
    public var text: String
    public var isWord: Bool
    public var hint: WordHint?

    public init(text: String, isWord: Bool, hint: WordHint?) {
        self.text = text
        self.isWord = isWord
        self.hint = hint
    }
}

/// Splits `text` into segments ready to render, with a greedy longest-match
/// phrase lookup on top of segmentWords: at each word-like piece, tries
/// joining forward across up to maxPhraseTokens word-like pieces (the pieces
/// between them joined verbatim from the source, never re-normalized) and
/// takes the longest run that hits `hintMap`. A hit emits ONE segment for the
/// whole phrase (so "آخر هفته" gets one reading, "ākhar-e hafte", not two); a
/// miss falls through to the single token, and a token with no hint renders
/// as plain native text. `tags` are the lexeme tags of the exercise the text
/// belongs to, when it has any: how a word with endings attached is split.
public func segmentAnnotatedText(_ text: String, _ hintMap: [String: WordHint], tags: [String] = []) -> [AnnotatedSegment] {
    let pieces = segmentWords(text)
    let tagSet = Set(tags)
    var segments: [AnnotatedSegment] = []

    var i = 0
    while i < pieces.count {
        let piece = pieces[i]
        if !piece.isWord {
            segments.append(AnnotatedSegment(text: piece.text, isWord: false, hint: nil))
            i += 1
            continue
        }

        // Every span tried is a legal stopping point, so the last (longest) hit wins.
        var bestEnd = i + 1
        var bestHint = wordHint(piece.text, hintMap, tagSet)
        var wordCount = 0
        var end = i
        var joined = ""
        while end < pieces.count && wordCount < maxPhraseTokens {
            joined += pieces[end].text
            if pieces[end].isWord { wordCount += 1 }
            end += 1
            // Only a span ending on a word token (not mid-trailing-space) is a candidate.
            if pieces[end - 1].isWord && end - i > 1 {
                // Phrases are keyed unmarked, and an ezafe inside one is already in
                // its authored romanization (آخرِ هفته -> "ākhar-e hafte").
                if let hit = hintMap[PersianNormalize.stripReadingAids(joined)] {
                    bestEnd = end
                    bestHint = hit
                }
            }
        }

        let segmentText = pieces[i..<bestEnd].map { $0.text }.joined()
        segments.append(AnnotatedSegment(text: segmentText, isWord: true, hint: bestHint))
        i = bestEnd
    }

    return segments
}

/// Persian punctuation, as it's written in a Latin line.
private func latinPunctuation(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
    switch scalar.value {
    case 0x061F: return "?"
    case 0x060C: return ","
    case 0x061B: return ";"
    default: return scalar
    }
}

/// A native-script sentence romanized word by word from the hint map: each
/// word's (or phrase's) romanization with its ezafe (ketāb-e man), a word the
/// map doesn't know left in the native script. The fallback for a sentence
/// with no authored romanization (ExerciseArtifact.promptRomanization); nil
/// when no word of it is known at all, so there's nothing useful to show.
public func romanizeSentence(_ text: String, _ hintMap: [String: WordHint], tags: [String] = []) -> String? {
    var known = false
    var out = ""
    for segment in segmentAnnotatedText(text, hintMap, tags: tags) {
        if !segment.isWord {
            var mapped = String.UnicodeScalarView()
            for scalar in segment.text.unicodeScalars { mapped.append(latinPunctuation(scalar)) }
            out += String(mapped)
        } else if let romanization = segment.hint?.romanization {
            known = true
            out += romanization + (segment.hint?.ezafe?.text ?? "")
        } else {
            out += PersianNormalize.stripReadingAids(segment.text)
        }
    }
    return known ? jsTrim(out) : nil
}

/// The direction a piece of text should render in, given the learner's
/// display preference, NOT simply detectScriptDirection(text): in "romanized"
/// display the base line is Latin whatever the source script, and an RTL
/// paragraph of Latin runs reorders as soon as punctuation or a fallback
/// native word appears in it.
public func displayDirection(_ text: String, display: ScriptDisplay) -> WritingDirection {
    return display == .romanized ? .ltr : Languages.detectScriptDirection(text)
}

/// JavaScript's `String.prototype.trim`: strips `\s` from both ends.
func jsTrim(_ s: String) -> String {
    var scalars = Array(s.unicodeScalars)
    while let last = scalars.last, isJSWhitespace(last) { scalars.removeLast() }
    var start = 0
    while start < scalars.count, isJSWhitespace(scalars[start]) { start += 1 }
    return scalarString(Array(scalars[start...]))
}
