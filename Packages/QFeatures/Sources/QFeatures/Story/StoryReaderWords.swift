import Foundation
import QModel
import QDomain

/// One piece of a story line: a word the learner can tap (with its hint and, when the course knows it, its lexeme tag) or text between words.
public struct StoryLineWord: Equatable, Sendable {
    public var index: Int
    public var text: String
    public var isWord: Bool
    /// The lexeme tag to save, when the word has one.
    public var tag: String?
    /// The word's gloss; nil for a word with no hint.
    public var hint: String?

    public var isTappable: Bool { return isWord && hint != nil }
}

public enum StoryReaderWords {
    /// The hint map a line is split with, built once per chapter. Keys are sorted so homographs resolve the same way every time.
    public static func hintMap(_ lexemes: [String: LexemeIndexEntry]) -> [String: WordHint] {
        let ordered = lexemes.keys.sorted().compactMap { key -> (tag: String, entry: LexemeIndexEntry)? in
            guard let entry = lexemes[key] else { return nil }
            return (tag: key, entry: entry)
        }
        return buildLexemeHintMap(ordered)
    }

    /// A line cut into words and the text between them. A word's tag is the sense the exercise tagged, else the first sense.
    public static func words(_ line: StoryReaderLine, hintMap: [String: WordHint]) -> [StoryLineWord] {
        let segments = segmentAnnotatedText(line.text, hintMap, tags: line.tags)
        var out: [StoryLineWord] = []
        for (index, segment) in segments.enumerated() {
            var tag: String?
            var hint: String?
            if segment.isWord, let found = segment.hint {
                let senses = found.senses ?? []
                let sense = senses.first(where: { line.tags.contains($0.tag) }) ?? senses.first
                tag = sense?.tag
                let gloss = sense?.translation ?? found.translation
                hint = gloss.isEmpty ? nil : gloss
            }
            out.append(StoryLineWord(index: index, text: segment.text, isWord: segment.isWord, tag: tag, hint: hint))
        }
        return out
    }
}
