import Foundation

// A deliberately crude, language-agnostic "is this answer right" for instant
// in-lesson UI feedback when no grader is published. Never authoritative: the
// server re-grades every submission. Port of web lib/textMatch.ts.

public enum TextMatch {
    /// Whether `submitted` equals any of `accepted` after trimming, lowercasing and collapsing whitespace.
    public static func looksCorrect(_ submitted: String, _ accepted: [String]) -> Bool {
        let target = Array(AnswerDiff.normalizeCase(submitted).utf8)
        return accepted.contains { Array(AnswerDiff.normalizeCase($0).utf8) == target }
    }
}
