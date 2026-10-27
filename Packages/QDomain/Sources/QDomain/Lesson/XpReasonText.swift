import Foundation

// The words under an answer's XP. The text is the grader's own (GraderResponse.xpLines,
// one per xpReasons code, owned by the backend); the client keeps no code-to-text table
// and never re-derives a reason. Only an unknown code, or a line the grader left out,
// gets the generic fallback below. Copy here is placeholder.

/// Client-side XP wording, all in one place.
public enum XpReasonCopy {
    /// Shown for a reason code this client does not know, or whose line the grader left out.
    public static let fallbackLine = "Reduced XP"
}

public enum XpReasonText {
    /// The codes the grader defines today (API_SPEC 2.3 point 8). Used only to decide when to fall back.
    public static let knownCodes: Set<String> = ["first_try", "corrected", "retry", "retype", "second_retype", "hint_halved"]

    /// One line per reason, in the grader's order. A known code shows its grader line; an unknown code, or a line missing or empty in a short `lines`, shows the fallback. No `reasons` or no `lines` at all (an older grader) gives no line.
    public static func lines(reasons: [String]?, lines: [String]?) -> [String] {
        guard let reasons = reasons, let lines = lines else { return [] }
        var out: [String] = []
        for (i, code) in reasons.enumerated() {
            if knownCodes.contains(code), i < lines.count, !lines[i].isEmpty {
                out.append(lines[i])
            } else {
                out.append(XpReasonCopy.fallbackLine)
            }
        }
        return out
    }
}
