import Foundation
import QModel

// A word_bank/match exercise can have more than one correct tile order: the
// authored `answer` plus any `alternativeAnswers`. Instant feedback, tile
// colors and the revealed answer all consider every order and agree on which
// one a wrong answer is measured against. Port of web wordBankOrders.ts.
//
// Tokens are compared by UTF-8 bytes (exact scalar equality, like JS ===), not
// Swift String ==, which would treat canonically equivalent text as equal.

public enum TileMark: Equatable, Sendable {
    case right
    case swapped
    case wrong
}

/// One step through a submission measured against an answer: a submitted token in its right place, one that isn't, or an answer token left out.
public enum AlignmentStep: Equatable, Sendable {
    case match(submitted: Int, answer: Int)
    case extra(submitted: Int)
    case missing(answer: Int)
}

public struct ClosestTileOrder: Equatable, Sendable {
    /// The correct order the submission is closest to.
    public var order: [String]
    /// Each submitted tile graded against `order`.
    public var marks: [TileMark]

    public init(order: [String], marks: [TileMark]) {
        self.order = order
        self.marks = marks
    }
}

public enum WordBankOrders {
    private static func same(_ a: String, _ b: String) -> Bool {
        return Array(a.utf8) == Array(b.utf8)
    }

    /// Every correct tile order, the authored `answer` first.
    public static func acceptedTileOrders(_ exercise: ExerciseArtifact) -> [[String]] {
        return [exercise.answer] + (exercise.alternativeAnswers ?? [])
    }

    /// Which tiles (by index) a submitted string was built from. A backtracking
    /// search rather than splitting on spaces, since one tile can contain a
    /// space. Empty if nothing matches.
    public static func tilesForSubmission(_ tiles: [String], _ submitted: String) -> [Int] {
        let tileBytes = tiles.map { Array($0.utf8) }
        let space: UInt8 = 0x20
        var used = [Bool](repeating: false, count: tiles.count)
        var picked: [Int] = []

        func search(_ rest: [UInt8]) -> Bool {
            if rest.isEmpty { return true }
            for i in 0..<tileBytes.count {
                let tile = tileBytes[i]
                if used[i] || tile.isEmpty { continue }
                let exact = rest == tile
                let followedBySpace = rest.count > tile.count && Array(rest[0..<tile.count]) == tile && rest[tile.count] == space
                if exact || followedBySpace {
                    used[i] = true
                    picked.append(i)
                    var next = Array(rest[tile.count...])
                    if let first = next.first, first == space { next.removeFirst() }
                    if search(next) { return true }
                    used[i] = false
                    picked.removeLast()
                }
            }
            return false
        }

        return search(Array(submitted.utf8)) ? picked : []
    }

    /// Grades each submitted tile against one correct order. Off by exactly one
    /// swap marks that pair `.swapped`. Otherwise the tiles in the longest common
    /// subsequence are `.right`, so one extra tile doesn't turn every tile after
    /// it wrong.
    public static func gradeTiles(_ submitted: [String], _ answer: [String]) -> [TileMark] {
        let n = submitted.count
        if n == answer.count {
            var mismatches: [Int] = []
            for i in 0..<n where !same(submitted[i], answer[i]) { mismatches.append(i) }
            if mismatches.count == 2 {
                let a = mismatches[0]
                let b = mismatches[1]
                if same(submitted[a], answer[b]) && same(submitted[b], answer[a]) {
                    return (0..<n).map { ($0 == a || $0 == b) ? TileMark.swapped : TileMark.right }
                }
            }
        }
        var marks = [TileMark](repeating: .wrong, count: n)
        for step in alignTiles(submitted, answer) {
            if case let .match(s, _) = step { marks[s] = .right }
        }
        return marks
    }

    /// `gradeTiles`'s longest-common-subsequence alignment, step by step in
    /// reading order, so a caller can also say where each left-out answer token
    /// belonged.
    public static func alignTiles(_ submitted: [String], _ answer: [String]) -> [AlignmentStep] {
        let n = submitted.count
        let m = answer.count
        var lcs = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    lcs[i][j] = same(submitted[i], answer[j])
                        ? lcs[i + 1][j + 1] + 1
                        : max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }
        var steps: [AlignmentStep] = []
        var i = 0
        var j = 0
        while i < n && j < m {
            if same(submitted[i], answer[j]) {
                steps.append(.match(submitted: i, answer: j))
                i += 1
                j += 1
            } else if lcs[i + 1][j] >= lcs[i][j + 1] {
                steps.append(.extra(submitted: i))
                i += 1
            } else {
                steps.append(.missing(answer: j))
                j += 1
            }
        }
        while i < n {
            steps.append(.extra(submitted: i))
            i += 1
        }
        while j < m {
            steps.append(.missing(answer: j))
            j += 1
        }
        return steps
    }

    /// The correct order a submission comes closest to, and its tiles graded
    /// against it: fewest wrong tiles first, then fewest of that order's tiles
    /// left unplaced, then fewest swapped. Ties go to the earlier order, so the
    /// authored answer wins unless an alternative is strictly closer.
    public static func closestTileOrder(_ submitted: [String], _ orders: [[String]]) -> ClosestTileOrder {
        var best: (result: ClosestTileOrder, score: [Int])?
        for order in orders {
            let marks = gradeTiles(submitted, order)
            let wrong = marks.filter { $0 == .wrong }.count
            let placed = marks.count - wrong
            let swapped = marks.filter { $0 == .swapped }.count
            let score = [wrong, order.count - placed, swapped]
            if best == nil || isLower(score, best!.score) {
                best = (ClosestTileOrder(order: order, marks: marks), score)
            }
        }
        return best?.result ?? ClosestTileOrder(order: [], marks: submitted.map { _ in TileMark.wrong })
    }

    private static func isLower(_ a: [Int], _ b: [Int]) -> Bool {
        for i in 0..<a.count where a[i] != b[i] {
            return a[i] < b[i]
        }
        return false
    }

    /// The correct order to show for a submission: the one its tiles were graded
    /// against, so the revealed answer and tile colors never disagree.
    public static func revealedTileOrder(_ exercise: ExerciseArtifact, submittedText: String?) -> [String] {
        let orders = acceptedTileOrders(exercise)
        guard let text = submittedText, orders.count > 1 else { return exercise.answer }
        let tiles = exercise.tiles ?? []
        let submitted = tilesForSubmission(tiles, text).map { tiles[$0] }
        if submitted.isEmpty { return exercise.answer }
        return closestTileOrder(submitted, orders).order
    }

    /// The bank tiles (by tile index) the learner left out but the correct order
    /// needed: each of `order`'s tokens that no right or swapped submitted tile
    /// accounts for claims one unused bank tile with the same text.
    public static func missingBankTiles(tiles: [String], bankIndices: [Int], submitted: [String], marks: [TileMark], order: [String]) -> Set<Int> {
        var needed: [[UInt8]: Int] = [:]
        for token in order { needed[Array(token.utf8), default: 0] += 1 }
        for (i, token) in submitted.enumerated() {
            let key = Array(token.utf8)
            if marks[i] != .wrong, let count = needed[key], count > 0 { needed[key] = count - 1 }
        }
        var missing = Set<Int>()
        for index in bankIndices {
            let key = Array(tiles[index].utf8)
            if let count = needed[key], count > 0 {
                missing.insert(index)
                needed[key] = count - 1
            }
        }
        return missing
    }
}
