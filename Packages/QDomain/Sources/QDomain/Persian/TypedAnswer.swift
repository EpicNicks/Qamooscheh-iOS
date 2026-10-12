import Foundation

// What a typed Persian answer is submitted as. Isolated keyboard mode writes a
// ZWNJ after every letter so each shows in its isolated form: a way of seeing
// the letters, not a spelling. Those come out before grading. Port of web
// persian/typedAnswer.ts, done by hand over scalars to match its two regexes.

public enum TypedAnswer {
    private static let zwnj: Unicode.Scalar = "\u{200C}"

    /// `text` as the learner meant it: without the ZWNJ isolated mode put after
    /// each letter (when `isolatedLetters`), and without any half-space that
    /// can't be part of a word.
    public static func submittedSpelling(_ text: String, isolatedLetters: Bool) -> String {
        let scalars = Array(text.unicodeScalars)
        let spelled = isolatedLetters ? dropIsolatingZwnj(scalars) : scalars
        let cleaned = dropStrayZwnj(spelled)
        var view = String.UnicodeScalarView()
        view.append(contentsOf: cleaned)
        return String(view)
    }

    /// Regex ([^ZWNJ\s])ZWNJ replaced by the letter: a letter's own isolating ZWNJ goes; a second one beside it stays.
    private static func dropIsolatingZwnj(_ s: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        var i = 0
        while i < s.count {
            let c = s[i]
            if c != zwnj && !isJSWhitespace(c) && i + 1 < s.count && s[i + 1] == zwnj {
                out.append(c)
                i += 2
            } else {
                out.append(c)
                i += 1
            }
        }
        return out
    }

    /// Regex ^Z+ | Z+$ | Z*(\s+)Z* replaced by the whitespace run or nothing: a ZWNJ at either end, or beside whitespace, is dropped.
    private static func dropStrayZwnj(_ s: [Unicode.Scalar]) -> [Unicode.Scalar] {
        let n = s.count
        var out: [Unicode.Scalar] = []
        var p = 0
        while p < n {
            let c = s[p]
            if c == zwnj {
                var r = p
                while r < n && s[r] == zwnj { r += 1 }
                if p == 0 || r == n {
                    p = r
                } else if isJSWhitespace(s[r]) {
                    var w = r
                    while w < n && isJSWhitespace(s[w]) { w += 1 }
                    out.append(contentsOf: s[r..<w])
                    p = w
                    while p < n && s[p] == zwnj { p += 1 }
                } else {
                    out.append(c)
                    p += 1
                }
            } else if isJSWhitespace(c) {
                var w = p
                while w < n && isJSWhitespace(s[w]) { w += 1 }
                out.append(contentsOf: s[p..<w])
                p = w
                while p < n && s[p] == zwnj { p += 1 }
            } else {
                out.append(c)
                p += 1
            }
        }
        return out
    }
}
