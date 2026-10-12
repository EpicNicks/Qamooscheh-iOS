import Foundation

public struct PersianPhoneticState: Equatable, Sendable {
    /// A single Latin char that might still extend into a digraph. "" when idle.
    public var bufferedPrefix: String

    public init(bufferedPrefix: String = "") {
        self.bufferedPrefix = bufferedPrefix
    }

    public static let initial = PersianPhoneticState()
}

public struct PersianPhoneticStep: Equatable, Sendable {
    public var state: PersianPhoneticState
    /// Trailing characters to remove before appending `insertText`.
    public var deleteCount: Int
    public var insertText: String
    /// Set alongside a just-inserted ambiguous letter (insertText == candidates[0]).
    public var candidates: [String]?

    public init(state: PersianPhoneticState, deleteCount: Int, insertText: String, candidates: [String]?) {
        self.state = state
        self.deleteCount = deleteCount
        self.insertText = insertText
        self.candidates = candidates
    }
}

/// Incremental state machine for the Persian phonetic keyboard. Port of web phoneticEngine.ts.
public enum PersianPhoneticEngine {
    private static func eagerLength(for prefix: String) -> Int {
        return PersianPhoneticMap.resolveTrigger(prefix) != nil ? 1 : 0
    }

    private static func ambiguous(_ options: [String]?) -> [String]? {
        if let options = options, options.count > 1 { return options }
        return nil
    }

    public static func feedLatinChar(_ state: PersianPhoneticState, _ rawChar: Character) -> PersianPhoneticStep {
        let char = String(rawChar).lowercased()

        if !state.bufferedPrefix.isEmpty {
            if let digraph = PersianPhoneticMap.resolveTrigger(state.bufferedPrefix + char) {
                return PersianPhoneticStep(
                    state: .initial,
                    deleteCount: eagerLength(for: state.bufferedPrefix),
                    insertText: digraph[0],
                    candidates: ambiguous(digraph))
            }
            return feedLatinChar(.initial, rawChar)
        }

        let single = PersianPhoneticMap.resolveTrigger(char)
        let next: PersianPhoneticState = PersianPhoneticMap.digraphStarters.contains(char)
            ? PersianPhoneticState(bufferedPrefix: char) : .initial
        return PersianPhoneticStep(
            state: next,
            deleteCount: 0,
            insertText: single?[0] ?? "",
            candidates: ambiguous(single))
    }

    /// Call on space/blur/submit. A no-op edit: eager guesses are already in the text.
    public static func finalizeWord() -> PersianPhoneticStep {
        return PersianPhoneticStep(state: .initial, deleteCount: 0, insertText: "", candidates: nil)
    }
}
