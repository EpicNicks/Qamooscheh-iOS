import Foundation
import QModel

/// The race rules the device needs while a run is on screen (backend RaceRules, docs/repack-race.md). The server
/// recomputes the score at finish; this is only so the strike meter and the running score are right as it plays.
public enum RaceScoring {
    public static let maxStrikes = 3

    /// A strike is a card not answered correctly on attempt 1.
    public static func isStrike(_ result: ClozeResult) -> Bool {
        return !(result.correct && result.attempt == 1)
    }

    public static func strikes(_ results: [ClozeResult]) -> Int {
        return results.filter(isStrike).count
    }

    /// Perfect Delivery ends at the 3rd strike; Endless Practice only when the learner stops.
    public static func ended(_ mode: RaceMode, _ results: [ClozeResult]) -> Bool {
        return mode == .perfectDelivery && strikes(results) >= maxStrikes
    }

    /// The sum of the issued weights of the solved cards (right on any attempt).
    public static func score(_ results: [ClozeResult], weights: [String: Double]) -> Double {
        return results.filter { $0.correct }.reduce(0) { $0 + (weights[$1.tag] ?? 0) }
    }

    public static func solved(_ results: [ClozeResult]) -> Int {
        return results.filter { $0.correct }.count
    }

    /// Only words the server weighted may be dealt; a tag it did not weight is not a learned word.
    public static func dealable<T>(_ cards: [T], tagOf: (T) -> String, weights: [String: Double]) -> [T] {
        return cards.filter { weights[tagOf($0)] != nil }
    }

    /// A run's time as the boards show it: `m:ss`, or `m:ss.t` with `tenths`.
    public static func clock(ms: Int, tenths: Bool = false) -> String {
        let total = max(ms, 0)
        let seconds = total / 1000 % 60
        let base = "\(total / 60_000):" + (seconds < 10 ? "0" : "") + "\(seconds)"
        return tenths ? "\(base).\(total / 100 % 10)" : base
    }

    /// A weight total as a score: one decimal.
    public static func scoreText(_ score: Double) -> String {
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), score)
    }

    /// Why a run didn't reach the boards, in the learner's terms; the server's `heldReason` is the key.
    public static func heldMessage(_ reason: String?) -> String {
        switch reason {
        case "answer_too_fast", "missing_timing":
            return "Some answers came in faster than a person could type them, so this run isn't on the boards."
        case "claimed_time_exceeds_run", "answers_after_end":
            return "The timing on this run didn't add up, so it isn't on the boards."
        default:
            return "This run didn't pass a check, so it isn't on the boards."
        }
    }

    /// How the run ended, from the server's `endReason`.
    public static func endReasonText(_ reason: String) -> String {
        switch reason {
        case "third_strike": return "Ended at the third strike."
        case "deck_done": return "You cleared the whole deck."
        default: return "You stopped the run."
        }
    }

    /// Why a board might be empty, per scope.
    public static func emptyBoardText(_ scope: RaceScope) -> String {
        switch scope {
        case .global: return "No runs on this board yet. Be the first."
        case .country: return "No runs from your country yet. Set your country in your profile to join this board."
        case .weekly: return "No runs this week yet. The week starts Monday, UTC."
        case .friends: return "None of your friends have a run here yet. Add friends from your profile, then race."
        }
    }
}
