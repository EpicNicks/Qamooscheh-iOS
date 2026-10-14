import Foundation
import Combine
import QModel
import QDomain
import QNetwork

/// Everything the vocabulary screens build their lists from (Android CourseVocabularyContent).
public struct VocabContent: Equatable, Sendable {
    public var courseCode: String
    public var units: [UnitVocab]
    public var lexemes: [String: LexemeIndexEntry]

    public init(courseCode: String, units: [UnitVocab], lexemes: [String: LexemeIndexEntry]) {
        self.courseCode = courseCode
        self.units = units
        self.lexemes = lexemes
    }
}

public enum VocabLoad: Equatable, Sendable {
    case noCourse
    /// The pinned version isn't fully on disk yet; the Learn tab shows its progress.
    case notDownloaded
    case ready(VocabContent)
}

/// Where a vocabulary screen is in getting its words (Android VocabStatus).
public enum VocabStatus: Equatable, Sendable {
    case loading
    case noCourse
    case notDownloaded
    case failed(String)
    case ready
}

/// What the vocabulary screens read. The production conformer reads the pinned course from disk,
/// the current user's card mirror, and the starred endpoints.
public protocol VocabularySource: Sendable {
    func load() async throws -> VocabLoad
    /// The signed-in user's card mirror; empty when there is none.
    func cardStates() async -> [String: CardState]
    func starred() async throws -> StarredVocabResponse
    func setStarred(tag: String, starred: Bool) async throws -> StarredVocabResponse
}

/// The loading shared by the lesson vocabulary and flashcards screens: course content, the card
/// mirror and the starred list (refreshed on every appearance), and the optimistic star toggle.
@MainActor
public final class VocabularyStore: ObservableObject {
    @Published public private(set) var status: VocabStatus = .loading
    @Published public private(set) var content: VocabContent?
    @Published public private(set) var cards: [String: CardState] = [:]
    /// The server's saved tags (any course), most recently saved first.
    @Published private var savedTags: [String] = []
    /// Stars the learner has toggled that the server hasn't confirmed yet, by tag.
    @Published private var pending: [String: Bool] = [:]
    /// The server's words (or ours) when a star could not be saved, e.g. over the plan's cap.
    @Published public private(set) var starMessage: String?

    private let source: VocabularySource?
    private let onUnauthorized: (@Sendable () -> Void)?
    private var generation = 0
    private var starEpoch = 0
    private var requestSeq = 0
    private var appliedSeq = 0
    private var pendingToken: [String: Int] = [:]

    public init(source: VocabularySource?, onUnauthorized: (@Sendable () -> Void)? = nil) {
        self.source = source
        self.onUnauthorized = onUnauthorized
    }

    /// Saved tags with unconfirmed toggles applied, so a star fills at once and one word's rollback never touches another's.
    public var starredTags: [String] {
        var tags = savedTags.filter { pending[$0] != false }
        let added = pending.filter { $0.value && !tags.contains($0.key) }.map { $0.key }.sorted()
        tags.insert(contentsOf: added, at: 0)
        return tags
    }

    /// Safe on every appearance: loaded content, cards and stars stay up while reloading, and only the newest call lands.
    public func refresh() async {
        guard let source = source else { return }
        generation += 1
        let mine = generation
        let epoch = starEpoch
        if content == nil { status = .loading }
        do {
            let load = try await source.load()
            if mine != generation { return }
            switch load {
            case .noCourse:
                content = nil
                status = .noCourse
            case .notDownloaded:
                content = nil
                status = .notDownloaded
            case .ready(let loaded):
                content = loaded
                status = .ready
            }
        } catch {
            if isCancellation(error) { return }
            if isUnauthorizedError(error) { onUnauthorized?() }
            if mine != generation { return }
            if content == nil { status = .failed(AuthRules.message(for: error, fallback: "Couldn't read this course's vocabulary from the device.")) }
        }
        let latestCards = await source.cardStates()
        if mine != generation { return }
        cards = latestCards
        do {
            let response = try await source.starred()
            // A toggle that landed meanwhile is newer than this read.
            if mine == generation && epoch == starEpoch { savedTags = response.tags }
        } catch {
            // Offline, the last list stands; only a lost session is worth reporting.
            if isUnauthorizedError(error) { onUnauthorized?() }
        }
    }

    /// The star fills at once; a failure undoes only this word and says why.
    public func toggleStar(_ tag: String) async {
        guard let source = source else { return }
        let want = !starredTags.contains(tag)
        pending[tag] = want
        starMessage = nil
        starEpoch += 1
        requestSeq += 1
        let seq = requestSeq
        let token = (pendingToken[tag] ?? 0) + 1
        pendingToken[tag] = token
        do {
            let response = try await source.setStarred(tag: tag, starred: want)
            starEpoch += 1
            if seq > appliedSeq {
                appliedSeq = seq
                savedTags = response.tags
            }
            if pendingToken[tag] == token { pending[tag] = nil }
        } catch {
            starEpoch += 1
            if pendingToken[tag] == token { pending[tag] = nil }
            if isCancellation(error) { return }
            if isUnauthorizedError(error) { onUnauthorized?() }
            starMessage = AuthRules.message(for: error, fallback: "Couldn't update your saved words.")
        }
    }

    public static func preview(content: VocabContent, cards: [String: CardState], starred: [String]) -> VocabularyStore {
        let store = VocabularyStore(source: nil)
        store.content = content
        store.cards = cards
        store.savedTags = starred
        store.status = .ready
        return store
    }
}

/// A load cut short because its view went away (structured cancellation, or URLSession's cancelled error) is not a failure.
func isCancellation(_ error: Error) -> Bool {
    return error is CancellationError || (error as? URLError)?.code == .cancelled
}
