import Foundation
import QModel

// Word behaviour in the story reader: when tapping or hovering a word may speak it, and how saved words show.

public enum StoryWordHighlight: Equatable, Sendable {
    case none
    case saved
    case savedVerb
}

public enum StoryWords {
    /// Word speech is allowed only with the setting on and the main player silent.
    public static func canSpeakWord(speakHoveredWords: Bool, mainPlaying: Bool) -> Bool {
        return speakHoveredWords && !mainPlaying
    }

    /// A saved word is saved; a saved verb (its infinitive, or a form of a verb whose infinitive is saved) is savedVerb; else none. Never the new-word colour.
    public static func highlight(tag: String, saved: Set<String>, lexemes: [String: LexemeIndexEntry]) -> StoryWordHighlight {
        if saved.contains(tag) {
            return isBaseVerb(lexemes[tag]) ? .savedVerb : .saved
        }
        let index = baseVerbIndex(lexemes)
        if let base = baseVerbTag(of: tag, lexemes: lexemes, index: index), saved.contains(base) {
            return .savedVerb
        }
        return .none
    }
}
