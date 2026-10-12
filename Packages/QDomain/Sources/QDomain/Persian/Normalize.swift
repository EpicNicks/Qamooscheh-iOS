import Foundation

// Client-side mirror of Qamooscheh.Persian.Normalization.PersianNormalizer,
// for DISPLAY only (answer-feedback notes, reading aids, half-spaces).
// Whether an answer is right is the published grader's call. Port of web
// persian/normalize.ts. Works on Unicode scalars, as the JS does on code points.
//
// Codepoints: ZWNJ U+200C, Heh Goal U+06C0, Heh U+0647, Persian Yeh U+06CC,
// Arabic Yeh U+064A, Arabic Kaf U+0643, Keheh U+06A9, Teh Marbuta U+0629,
// Alef w/ Hamza Above U+0623, Alef U+0627, Alef w/ Hamza Below U+0625,
// Arabic-Indic digits U+0660-0669, Persian digits U+06F0-06F9,
// Kasra U+0650, Hamza Above U+0654.

public let ZWNJ = "\u{200C}"
/// The ezafe marks content writes: a kasra on the word, or a hamza above after a silent heh.
public let KASRA = "\u{0650}"
public let HAMZA_ABOVE = "\u{0654}"

private let zwnjScalar: Unicode.Scalar = "\u{200C}"
private let hehGoal: Unicode.Scalar = "\u{06C0}"
private let heh: Unicode.Scalar = "\u{0647}"
private let persianYeh: Unicode.Scalar = "\u{06CC}"
private let hamzaAbove: Unicode.Scalar = "\u{0654}"
/// Fatha (U+064E) through sukun (U+0652).
private let firstVowelMark: UInt32 = 0x064E
private let lastVowelMark: UInt32 = 0x0652

private let codepointFoldMap: [UInt32: Unicode.Scalar] = [
    0x064A: persianYeh, // Arabic Yeh -> Persian Yeh
    0x0643: "\u{06A9}", // Arabic Kaf -> Persian Keheh
    0x0629: heh, // Teh Marbuta -> Heh
    0x0623: "\u{0627}", // Alef with Hamza Above -> Alef
    0x0625: "\u{0627}", // Alef with Hamza Below -> Alef
]

private func isReadingAid(_ ch: Unicode.Scalar, previous: Unicode.Scalar?) -> Bool {
    return (ch.value >= firstVowelMark && ch.value <= lastVowelMark) || (ch == hamzaAbove && previous == heh)
}

private func foldDigit(_ ch: Unicode.Scalar) -> Unicode.Scalar {
    if ch.value >= 0x0660 && ch.value <= 0x0669 { return Unicode.Scalar(0x30 + ch.value - 0x0660)! }
    if ch.value >= 0x06F0 && ch.value <= 0x06F9 { return Unicode.Scalar(0x30 + ch.value - 0x06F0)! }
    return ch
}

private func string(from scalars: [Unicode.Scalar]) -> String {
    var view = String.UnicodeScalarView()
    view.append(contentsOf: scalars)
    return String(view)
}

public enum PersianNormalize {
    /// `input` without short vowels or the ezafe hamza (after a heh), otherwise untouched.
    public static func stripReadingAids(_ input: String) -> String {
        var out: [Unicode.Scalar] = []
        for ch in input.unicodeScalars where !isReadingAid(ch, previous: out.last) {
            out.append(ch)
        }
        return string(from: out)
    }

    /// NFC, digits folded to ASCII, whitespace collapsed and trimmed, reading aids dropped.
    public static func normalizeStrict(_ input: String) -> String {
        let composed = input.precomposedStringWithCanonicalMapping
        var out: [Unicode.Scalar] = []
        var lastWasSpace = false
        for ch in composed.unicodeScalars {
            if isReadingAid(ch, previous: out.last) { continue }
            let mapped = foldDigit(ch)
            if isJSWhitespace(mapped) {
                if !lastWasSpace && !out.isEmpty { out.append(" ") }
                lastWasSpace = true
                continue
            }
            out.append(mapped)
            lastWasSpace = false
        }
        while let last = out.last, isJSWhitespace(last) { out.removeLast() }
        return string(from: out)
    }

    /// Arabic-vs-Persian codepoint differences folded away. Expects `normalizeStrict`'d input.
    public static func foldCodepoints(_ strictlyNormalized: String) -> String {
        var out: [Unicode.Scalar] = []
        for ch in strictlyNormalized.unicodeScalars {
            if ch == hehGoal {
                out.append(heh)
                out.append(zwnjScalar)
                out.append(persianYeh)
            } else {
                out.append(codepointFoldMap[ch.value] ?? ch)
            }
        }
        return string(from: out)
    }

    /// An Arabic-only letter in Persian input, and the Persian one to use instead.
    public struct ArabicVariantHit: Equatable, Sendable {
        /// UTF-16 offset, as the web reports it.
        public var index: Int
        public var found: String
        public var suggested: String
        public var label: String

        public init(index: Int, found: String, suggested: String, label: String) {
            self.index = index
            self.found = found
            self.suggested = suggested
            self.label = label
        }
    }

    /// A diagnostic pass over raw input for an inline "did you mean ی, not ي?"
    /// note as the learner types. Never blocks submitting.
    public static func detectArabicVariants(_ rawInput: String) -> [ArabicVariantHit] {
        var hits: [ArabicVariantHit] = []
        var index = 0
        for ch in rawInput.unicodeScalars {
            let found = String(ch)
            switch ch.value {
            case 0x064A:
                hits.append(ArabicVariantHit(index: index, found: found, suggested: "\u{06CC}", label: "Arabic yeh \u{2014} Persian uses \u{06CC}"))
            case 0x0643:
                hits.append(ArabicVariantHit(index: index, found: found, suggested: "\u{06A9}", label: "Arabic kaf \u{2014} Persian uses \u{06A9}"))
            case 0x0629:
                hits.append(ArabicVariantHit(index: index, found: found, suggested: "\u{0647}", label: "Teh marbuta \u{2014} Persian uses \u{0647}"))
            case 0x0623, 0x0625:
                hits.append(ArabicVariantHit(index: index, found: found, suggested: "\u{0627}", label: "Hamza-marked alef \u{2014} Persian uses plain \u{0627}"))
            default:
                break
            }
            index += ch.value > 0xFFFF ? 2 : 1
        }
        return hits
    }
}
