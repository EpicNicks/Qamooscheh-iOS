import Foundation

// Word-by-word coloring for a typed answer on the review screen: which words
// the learner got right, which were right but traded places, and which were
// wrong. Not grading; AnswerFeedback decides the verdict. Port of web
// domain/typedAnswerMarks.ts.

public enum WordMark: Equatable, Sendable {
    case right
    case swapped
    case wrong
    /// A word the closest accepted answer has that the learner left out, placed where it belongs.
    case missing
}

public struct MarkedWord: Equatable, Sendable {
    /// The word exactly as the learner typed it, or, for a missing word, as the accepted answer writes it.
    public var text: String
    public var mark: WordMark

    public init(text: String, mark: WordMark) {
        self.text = text
        self.mark = mark
    }
}

/// A stretch of the matched answer; `gap` is a separator the learner got wrong (an empty one is a caret, where an extra one sat).
public struct SeparatorSpan: Equatable, Sendable {
    public var text: String
    public var gap: Bool

    public init(text: String, gap: Bool) {
        self.text = text
        self.gap = gap
    }
}

public enum TypedAnswerMarks {
    /// Close enough to show what's missing: at least half the closest answer's words typed in their right places.
    private static let minPlacedForMissing = 0.5

    private static func isPunctuationOrSymbol(_ s: Unicode.Scalar) -> Bool {
        switch s.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation,
             .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
            return true
        default:
            return false
        }
    }

    // Punctuation never decides whether a word is right, and neither do case or,
    // in Persian, an Arabic codepoint the comparator forgives. A half-space does.
    private static func wordKey(_ word: String, persian: Bool) -> String {
        var kept = String.UnicodeScalarView()
        for s in word.lowercased().unicodeScalars where !isPunctuationOrSymbol(s) { kept.append(s) }
        let base = String(kept)
        return persian ? PersianNormalize.foldCodepoints(PersianNormalize.normalizeStrict(base)) : base
    }

    private static func words(_ text: String) -> [String] {
        var result: [String] = []
        var current: [Unicode.Scalar] = []
        for s in text.unicodeScalars {
            if isJSWhitespace(s) {
                if !current.isEmpty {
                    result.append(scalarString(current))
                    current = []
                }
            } else {
                current.append(s)
            }
        }
        if !current.isEmpty { result.append(scalarString(current)) }
        return result
    }

    /// The learner's typed words, each marked against whichever accepted answer it comes closest to. A correct answer is all green. A wrong one that's close also gets the words it left out, in place, marked `.missing`.
    public static func markTypedAnswer(
        courseCode: String?,
        acceptedAnswers: [String],
        submitted: String,
        correct: Bool
    ) -> [MarkedWord] {
        let typed = words(submitted)
        if correct { return typed.map { MarkedWord(text: $0, mark: .right) } }
        let persian = Languages.isPersian(courseCode)
        let acceptedWords = acceptedAnswers.map(words)
        let orders = acceptedWords.map { answer in answer.map { wordKey($0, persian: persian) } }
        let typedKeys = typed.map { wordKey($0, persian: persian) }
        let closest = WordBankOrders.closestTileOrder(typedKeys, orders)
        let order = closest.order
        let marks = closest.marks
        let marked: [MarkedWord] = typed.enumerated().map { (i, text) in
            let mark: WordMark
            switch marks[i] {
            case .right: mark = .right
            case .swapped: mark = .swapped
            case .wrong: mark = .wrong
            }
            return MarkedWord(text: text, mark: mark)
        }

        // A swapped pair has every word there already; nothing to add.
        let placed = marks.filter { $0 == .right }.count
        if marks.contains(.swapped) || placed == order.count || Double(placed) < Double(order.count) * minPlacedForMissing {
            return marked
        }

        let orderBytes = order.map { Array($0.utf8) }
        guard let orderIndex = orders.firstIndex(where: { candidate in candidate.map { Array($0.utf8) } == orderBytes }) else { return marked }
        let answerWords = acceptedWords[orderIndex]
        var result: [MarkedWord] = []
        for run in unmatchedRuns(WordBankOrders.alignTiles(typedKeys, order)) {
            // A run with a typed word in it is that word standing in for the missing one: a
            // misspelling, already red. Only a run of nothing but missing words is a gap.
            let substitution = run.contains { step in
                if case .extra = step { return true }
                return false
            }
            for step in run {
                switch step {
                case let .match(s, _):
                    result.append(marked[s])
                case let .extra(s):
                    result.append(marked[s])
                case let .missing(a):
                    if !substitution { result.append(MarkedWord(text: answerWords[a], mark: .missing)) }
                }
            }
        }
        return result
    }

    private static func isMatch(_ step: AlignmentStep) -> Bool {
        if case .match = step { return true }
        return false
    }

    /// The alignment cut into its matches, each on its own, and the unmatched stretches between them.
    private static func unmatchedRuns(_ steps: [AlignmentStep]) -> [[AlignmentStep]] {
        var runs: [[AlignmentStep]] = []
        for step in steps {
            if !isMatch(step), let last = runs.last, !isMatch(last[0]) {
                runs[runs.count - 1].append(step)
            } else {
                runs.append([step])
            }
        }
        return runs
    }

    /// The accepted answer the grader matched, cut at the grader's separator edits so the review can point at each half-space or space the learner missed, mistyped or added. Edits are UTF-16 offsets into `matchedAnswer`, in index order; one that doesn't fit is skipped.
    public static func markSeparatorGaps(_ matchedAnswer: String, _ edits: [SeparatorEdit]) -> [SeparatorSpan] {
        let total = matchedAnswer.utf16.count
        var spans: [SeparatorSpan] = []
        var at = 0
        for edit in edits {
            if edit.index < at || edit.index + edit.length > total { continue }
            if edit.index > at { spans.append(SeparatorSpan(text: utf16Slice(matchedAnswer, at, edit.index), gap: false)) }
            spans.append(SeparatorSpan(text: utf16Slice(matchedAnswer, edit.index, edit.index + edit.length), gap: true))
            at = edit.index + edit.length
        }
        if at < total { spans.append(SeparatorSpan(text: utf16Slice(matchedAnswer, at, total), gap: false)) }
        return spans
    }
}
