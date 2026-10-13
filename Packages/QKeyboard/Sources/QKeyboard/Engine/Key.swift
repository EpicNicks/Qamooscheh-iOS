import Foundation

/// What a key does. `letter`'s output is what the engine is fed: a Latin letter for phonetic layouts, the letter itself otherwise.
public enum KeyAction: Equatable, Sendable {
    case letter(String)
    case space
    case backspace
    /// The half-space; pressing it right after one removes it.
    case zwnj
    case shift
    case smallKana
    case scriptToggle
    case dakuten
    case handakuten
}

public struct Key: Equatable, Sendable {
    public var label: String
    public var action: KeyAction
    public var weight: Double
    public var enabled: Bool
    public var highlighted: Bool

    public init(label: String, action: KeyAction, weight: Double = 1, enabled: Bool = true, highlighted: Bool = false) {
        self.label = label
        self.action = action
        self.weight = weight
        self.enabled = enabled
        self.highlighted = highlighted
    }
}

public struct KeyboardLayout: Equatable, Sendable {
    public var rows: [[Key]]
    public var rtlCandidates: Bool

    public init(rows: [[Key]], rtlCandidates: Bool = false) {
        self.rows = rows
        self.rtlCandidates = rtlCandidates
    }
}

/// Latin row data shared by the phonetic, romaji and plain Latin layouts.
public enum LatinRows {
    public static let qwerty: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"],
    ]
}
