import Foundation

public struct JapanesePhoneticState: Equatable, Sendable {
    /// Romaji not yet resolved into kana: "", a consonant, a cluster ("ky"), or "n" (pending syllabic-n placeholder).
    public var buffer: String

    public init(buffer: String = "") {
        self.buffer = buffer
    }

    public static let initial = JapanesePhoneticState()
}

public struct RomajiStep: Equatable, Sendable {
    public var state: JapanesePhoneticState
    /// Trailing characters of the current answer text to remove before appending `insertText`.
    public var deleteCount: Int
    public var insertText: String

    public init(state: JapanesePhoneticState, deleteCount: Int, insertText: String) {
        self.state = state
        self.deleteCount = deleteCount
        self.insertText = insertText
    }
}

private let nPlaceholder = "ｎ" // FULLWIDTH LATIN SMALL LETTER N
private let romajiVowels: Set<Character> = ["a", "i", "u", "e", "o"]

public func feedRomajiChar(_ state: JapanesePhoneticState, _ rawChar: Character) -> RomajiStep {
    let char = Character(String(rawChar).lowercased())
    let buffer = state.buffer
    let placeholderDelete = buffer == "n" ? 1 : 0

    // "nn" always commits ん immediately, consuming both n's.
    if buffer == "n" && char == "n" {
        return RomajiStep(state: .initial, deleteCount: 1, insertText: "ん")
    }

    if char == "n" || romajiVowels.contains(char) || char == "y" {
        let candidate = buffer + String(char)
        if let exact = kanaTable[candidate] {
            return RomajiStep(state: .initial, deleteCount: placeholderDelete, insertText: exact)
        }
        if validRomajiPrefixes.contains(candidate) {
            return RomajiStep(state: JapanesePhoneticState(buffer: candidate),
                              deleteCount: placeholderDelete,
                              insertText: candidate == "n" ? nPlaceholder : "")
        }
        if !buffer.isEmpty {
            // Stale, unresolvable buffer: drop it and retry the char fresh.
            var fresh = feedRomajiChar(.initial, char)
            fresh.deleteCount += placeholderDelete
            return fresh
        }
        return RomajiStep(state: .initial, deleteCount: 0, insertText: "")
    }

    // A consonant (not n/y/vowel).
    if buffer == "n" {
        // Bare n followed by a consonant reads as syllabic ん.
        var fresh = feedRomajiChar(.initial, char)
        fresh.deleteCount = 1
        fresh.insertText = "ん" + fresh.insertText
        return fresh
    }

    if buffer == String(char) {
        // Sokuon: doubled consonant emits っ and restarts the buffer.
        return RomajiStep(state: JapanesePhoneticState(buffer: buffer), deleteCount: 0, insertText: "っ")
    }

    let candidate = buffer + String(char)
    if validRomajiPrefixes.contains(candidate) {
        return RomajiStep(state: JapanesePhoneticState(buffer: candidate), deleteCount: 0, insertText: "")
    }

    // Invalid cluster: drop the stale buffer, start fresh with this consonant.
    return RomajiStep(state: JapanesePhoneticState(buffer: String(char)), deleteCount: 0, insertText: "")
}

/// Call on space/blur/submit: a pending bare "n" resolves to ん (replacing its placeholder); any other buffer is dropped.
public func finalizeRomaji(_ state: JapanesePhoneticState) -> RomajiStep {
    if state.buffer == "n" {
        return RomajiStep(state: .initial, deleteCount: 1, insertText: "ん")
    }
    return RomajiStep(state: .initial, deleteCount: 0, insertText: "")
}
