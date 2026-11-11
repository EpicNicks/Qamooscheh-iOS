import Foundation
import QModel
import QDomain

/// The star toggle a word tap goes through (the vocabulary store's existing save call).
@MainActor
public protocol StoryStarring: AnyObject {
    var starredTags: [String] { get }
    func toggleStar(_ tag: String) async
}

extension VocabularyStore: StoryStarring {}

/// What tapping a word in the story reader shows and does: the hint, and save or unsave. It never marks the word seen on the Journey.
public struct StoryWordTap: Equatable {
    public var tag: String
    public var hint: String
    public var isSaved: Bool
    public var highlight: StoryWordHighlight

    @MainActor
    public static func make(tag: String, lexemes: [String: LexemeIndexEntry], starred: StoryStarring) -> StoryWordTap {
        let saved = Set(starred.starredTags)
        return StoryWordTap(
            tag: tag,
            hint: lexemes[tag]?.gloss ?? "",
            isSaved: saved.contains(tag),
            highlight: StoryWords.highlight(tag: tag, saved: saved, lexemes: lexemes))
    }

    @MainActor
    public func toggleSaved(on starred: StoryStarring) async {
        await starred.toggleStar(tag)
    }
}
