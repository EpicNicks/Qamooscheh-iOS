import Foundation

// How a typed answer differs from an accepted one, for the feedback note and
// for ordering the answers a learner is shown. Display only: whether an answer
// is right is the published grader's call. Port of web persian/answerDiff.ts.

public enum AnswerDiff {
    /// Levenshtein distance over UTF-16 code units, as the web computes it.
    public static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let x = Array(a.utf16)
        let y = Array(b.utf16)
        let rows = x.count + 1
        let cols = y.count + 1
        var dp = [[Int]](repeating: [Int](repeating: 0, count: cols), count: rows)
        for i in 0..<rows { dp[i][0] = i }
        for j in 0..<cols { dp[0][j] = j }
        if rows > 1 && cols > 1 {
            for i in 1..<rows {
                for j in 1..<cols {
                    let cost = x[i - 1] == y[j - 1] ? 0 : 1
                    dp[i][j] = min(dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + cost)
                }
            }
        }
        return dp[rows - 1][cols - 1]
    }

    /// Lowercased, whitespace runs collapsed to one space, trimmed.
    public static func normalizeCase(_ input: String) -> String {
        var out: [Unicode.Scalar] = []
        var lastWasSpace = false
        for ch in input.lowercased().unicodeScalars {
            if isJSWhitespace(ch) {
                if !lastWasSpace && !out.isEmpty { out.append(" ") }
                lastWasSpace = true
                continue
            }
            out.append(ch)
            lastWasSpace = false
        }
        while let last = out.last, isJSWhitespace(last) { out.removeLast() }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: out)
        return String(view)
    }

    private static let vowels: Set<Unicode.Scalar> = ["a", "e", "i", "o", "u"]

    /// Drops apostrophes and hyphens (hamza/ayin markers) and collapses doubled vowels.
    public static func foldLatinVariance(_ normalized: String) -> String {
        var out: [Unicode.Scalar] = []
        var lastAppended: Unicode.Scalar?
        for ch in normalized.unicodeScalars {
            if ch == "'" || ch == "-" { continue }
            if vowels.contains(ch) && ch == lastAppended { continue }
            out.append(ch)
            lastAppended = ch
        }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: out)
        return String(view)
    }
}
