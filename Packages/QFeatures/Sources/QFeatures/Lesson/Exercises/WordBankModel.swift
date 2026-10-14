import Foundation
import CoreGraphics
import QModel
import QDomain

// The word bank's rules, decided without any UI so swift test proves them. Port of Android
// Exercises.kt (WordBankExercise: tap in, tap out, review marks), which ports web WordBankExercise.tsx.
// Match plays the same way on Android, so MatchExercise reuses all of this.

/// What a submitted answer looks like on review: the learner's text and whether it was right.
public struct ReviewedAnswer: Equatable, Sendable {
    public var text: String
    public var correct: Bool

    public init(text: String, correct: Bool) {
        self.text = text
        self.correct = correct
    }
}

/// The tiles in play, by index into `exercise.tiles`: the one-time shuffle, the answer so far
/// and the bank's current order.
public struct WordBankState: Equatable, Sendable {
    /// The bank's order when nothing is placed; fixed per exercise so it never gives the answer away.
    public let shuffled: [Int]
    public private(set) var chosen: [Int]
    public private(set) var bankOrder: [Int]

    /// `shuffled` nil shuffles at random; pass an order for screenshots and tests.
    public init(tileCount: Int, shuffled: [Int]? = nil) {
        let order = shuffled ?? Array(0..<tileCount).shuffled()
        self.shuffled = order
        self.chosen = []
        self.bankOrder = order
    }

    /// Where `tile` goes back into the bank when tapped out of the answer (web
    /// reinsertAtOriginalPosition): its place in the shuffle.
    public static func reinsert(_ bank: [Int], tile: Int, shuffled: [Int]) -> [Int] {
        let home = shuffled.firstIndex(of: tile) ?? 0
        let at = bank.firstIndex(where: { (shuffled.firstIndex(of: $0) ?? 0) > home }) ?? bank.count
        var result = bank
        result.insert(tile, at: at)
        return result
    }

    /// Taps a tile: from the bank into the answer's end, or back out of the answer. True when it was picked from the bank.
    @discardableResult
    public mutating func tap(_ tile: Int) -> Bool {
        if chosen.contains(tile) {
            chosen.removeAll { $0 == tile }
            bankOrder = WordBankState.reinsert(bankOrder, tile: tile, shuffled: shuffled)
            return false
        }
        chosen.append(tile)
        bankOrder.removeAll { $0 == tile }
        return true
    }

    /// The answer as submitted text, tiles joined by a space; nil while nothing is placed.
    public func answer(tiles: [String]) -> String? {
        if chosen.isEmpty { return nil }
        return chosen.map { tiles[$0] }.joined(separator: " ")
    }
}

/// A finished word bank laid out for review: which tiles are placed, which stay in the bank,
/// how each placed tile is marked and which bank tiles the closest correct order still needed.
public struct WordBankReview: Equatable, Sendable {
    public var placed: [Int]
    public var bank: [Int]
    public var marks: [TileMark]
    public var missing: Set<Int>

    public static func make(exercise: ExerciseArtifact, shuffled: [Int], reviewed: ReviewedAnswer) -> WordBankReview {
        let tiles = exercise.tiles ?? []
        let placed = WordBankOrders.tilesForSubmission(tiles, reviewed.text)
        let placedSet = Set(placed)
        let bank = shuffled.filter { !placedSet.contains($0) }
        let placedText = placed.map { tiles[$0] }
        if reviewed.correct {
            return WordBankReview(placed: placed, bank: bank, marks: placedText.map { _ in TileMark.right }, missing: [])
        }
        // A composite type_in exercise lists whole accepted answers rather than one tile order.
        let orders: [[String]]
        if exercise.type == .typeIn {
            orders = exercise.answer.map { $0.split(separator: " ", omittingEmptySubsequences: false).map(String.init) }
        } else {
            orders = WordBankOrders.acceptedTileOrders(exercise)
        }
        let closest = WordBankOrders.closestTileOrder(placedText, orders)
        let missing = WordBankOrders.missingBankTiles(tiles: tiles, bankIndices: bank, submitted: placedText, marks: closest.marks, order: closest.order)
        return WordBankReview(placed: placed, bank: bank, marks: closest.marks, missing: missing)
    }
}

/// Which colors a tile takes (Android tileColors).
public enum TileLook: Equatable, Sendable {
    case right
    case swapped
    case wrong
    /// A bank tile the correct order still needed, outlined on review.
    case missing
    case plain

    public static func of(mark: TileMark?, missing: Bool) -> TileLook {
        if let m = mark {
            switch m {
            case .right: return .right
            case .swapped: return .swapped
            case .wrong: return .wrong
            }
        }
        return missing ? .missing : .plain
    }
}

/// Whether the word bank flows right to left: a right-to-left course with any tile in its own script.
public func wordBankIsRtl(courseCode: String, tiles: [String]) -> Bool {
    return Languages.writingDirection(courseCode) == .rtl && tiles.contains { Languages.isNativeText(courseCode, $0) }
}

/// Wraps tiles into lines of `width`, each line starting at the reading edge (right in RTL),
/// or centered. Pure so swift test proves it; TileFlowLayout feeds it measured sizes.
public enum TileFlowGeometry {
    public static func frames(sizes: [CGSize], width: CGFloat, rtl: Bool, centered: Bool, spacing: CGFloat) -> [CGRect] {
        var lines: [[Int]] = [[]]
        var used: CGFloat = 0
        for (i, size) in sizes.enumerated() {
            let needed = lines[lines.count - 1].isEmpty ? size.width : used + spacing + size.width
            if needed > width && !lines[lines.count - 1].isEmpty {
                lines.append([i])
                used = size.width
            } else {
                lines[lines.count - 1].append(i)
                used = needed
            }
        }
        var frames = [CGRect](repeating: .zero, count: sizes.count)
        var y: CGFloat = 0
        for line in lines {
            if line.isEmpty { continue }
            let lineWidth = line.reduce(CGFloat(0)) { $0 + sizes[$1].width } + spacing * CGFloat(line.count - 1)
            let lineHeight = line.reduce(CGFloat(0)) { max($0, sizes[$1].height) }
            var x: CGFloat = centered ? max(0, (width - lineWidth) / 2) : 0
            for i in line {
                let w = sizes[i].width
                let originX = rtl ? width - x - w : x
                frames[i] = CGRect(x: originX, y: y, width: w, height: sizes[i].height)
                x += w + spacing
            }
            y += lineHeight + spacing
        }
        return frames
    }

    public static func height(of frames: [CGRect]) -> CGFloat {
        return frames.reduce(CGFloat(0)) { max($0, $1.maxY) }
    }
}
