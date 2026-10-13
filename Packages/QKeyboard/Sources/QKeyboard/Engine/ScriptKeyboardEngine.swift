import Foundation

/// One input method's behaviour: turns key presses into `Edit`s and offers candidates where a
/// sound has several spellings. Engines are plain value types holding explicit state, with no
/// assumption about a composing region, so a host (in-app field, keyboard extension) just applies
/// each returned `Edit` to its own text.
public protocol ScriptKeyboardEngine: Sendable {
    var layout: KeyboardLayout { get }
    /// Alternatives for the letter just typed; the first is already in the text.
    var candidates: [String]? { get }
    /// Typed but not yet in the text (a romaji consonant waiting for its vowel).
    var pending: String? { get }
    /// `textBefore` is the text before the cursor, for keys that change the last character.
    mutating func press(_ action: KeyAction, textBefore: String) -> Edit
    /// Swap the provisional letter for candidate `index`.
    mutating func pick(_ index: Int) -> Edit
    /// Commit anything pending (before Check, or switching away).
    mutating func finalize() -> Edit
}

public extension ScriptKeyboardEngine {
    var candidates: [String]? { nil }
    var pending: String? { nil }
    mutating func pick(_ index: Int) -> Edit { .none }
    mutating func finalize() -> Edit { .none }
}

func zwnjToggle(textBefore: String) -> Edit {
    if textBefore.unicodeScalars.last == "\u{200C}" {
        return Edit(delete: 1, insert: "")
    }
    return Edit(delete: 0, insert: "\u{200C}")
}

func lastScalarString(_ text: String) -> String? {
    guard let scalar = text.unicodeScalars.last else { return nil }
    return String(scalar)
}
