import Foundation
import Combine
import QModel
import QDomain
import QNetwork

/// Submits a finished round (POST /v1/flashcards/submit). The production conformer also refreshes
/// the day's progress and streak, since the XP moves the goal, the streak and the league.
public protocol FlashcardSubmitter: Sendable {
    func submit(_ request: SubmitFlashcardsRequest) async throws -> SubmitFlashcardsResponse
}

public struct FlashcardResult: Equatable, Sendable {
    public var tag: String
    public var correct: Bool

    public init(tag: String, correct: Bool) {
        self.tag = tag
        self.correct = correct
    }
}

/// What a finished round's XP is doing: only a typed round is sent, since a flip round earns nothing standalone.
public enum RoundXp: Equatable, Sendable {
    case idle
    case saving
    case saved(Int)
    case failed(String)
}

/// Saved words as flashcards, outside any lesson (web FlashcardsPage, Android FlashcardsViewModel).
/// "Type the meaning" earns XP per right meaning, sent once when the round ends; "Flip cards" is
/// practice only. Neither touches review scheduling. A round remembers its own course and
/// submission id, so a course change or a new round never redirects or drops its result.
@MainActor
public final class FlashcardsModel: ObservableObject {
    /// Cards in one round, at most.
    public static let roundSize = 20

    public let store: VocabularyStore
    @Published public private(set) var kind: FlashcardKind = .translation
    /// The round being played; nil before one starts.
    @Published public private(set) var deck: [FlashcardWord]?
    @Published public private(set) var results: [FlashcardResult] = []
    @Published public private(set) var xp: RoundXp = .idle

    private let submitter: FlashcardSubmitter?
    private let shuffle: @MainActor ([FlashcardWord]) -> [FlashcardWord]
    private let newId: () -> String
    private let now: () -> Date
    private let onUnauthorized: (@Sendable () -> Void)?
    private var roundId = 0
    private var roundCourse: String?
    private var submissionId = ""
    private var roundEndedAt = Date(timeIntervalSince1970: 0)
    private var forwarding: AnyCancellable?

    public init(
        store: VocabularyStore, submitter: FlashcardSubmitter?,
        shuffle: @escaping @MainActor ([FlashcardWord]) -> [FlashcardWord] = { $0.shuffled() },
        newId: @escaping () -> String = { UUID().uuidString },
        now: @escaping () -> Date = { Date() },
        onUnauthorized: (@Sendable () -> Void)? = nil
    ) {
        self.store = store
        self.submitter = submitter
        self.shuffle = shuffle
        self.newId = newId
        self.now = now
        self.onUnauthorized = onUnauthorized
        forwarding = store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    public func refresh() async { await store.refresh() }

    /// This course's saved words, most recently saved first.
    public var words: [FlashcardWord] {
        flashcardWords(savedTags: store.starredTags, lexemeIndex: store.content?.lexemes)
    }

    public var courseCode: String? { roundCourse ?? store.content?.courseCode }

    public var current: FlashcardWord? {
        guard let deck = deck, results.count < deck.count else { return nil }
        return deck[results.count]
    }

    /// True while the round's XP is being saved or has failed and is waiting on a retry or an explicit
    /// discard; the screen keeps the learner on the result until then so the XP isn't lost silently.
    public var isSettlingXp: Bool {
        switch xp {
        case .saving, .failed: return true
        case .idle, .saved: return false
        }
    }

    /// Gives up on a round whose XP couldn't be saved; the learner chose to.
    public func discardRound() { stop() }

    /// The kind can't change mid-round.
    public func setKind(_ next: FlashcardKind) {
        if deck == nil { kind = next }
    }

    /// A fresh round: up to `roundSize` of the saved words, shuffled.
    public func start() {
        let pool = words
        guard !pool.isEmpty, let course = store.content?.courseCode else { return }
        roundId += 1
        roundCourse = course
        submissionId = newId()
        deck = Array(shuffle(pool).prefix(FlashcardsModel.roundSize))
        results = []
        xp = .idle
    }

    /// Leaves the round for the start screen. A round already being saved still lands on the server.
    public func stop() {
        roundId += 1
        roundCourse = nil
        deck = nil
        results = []
        xp = .idle
    }

    /// Records the current card; the last card of a typed round sends the round.
    public func answer(correct: Bool) async {
        guard let card = current, let deck = deck else { return }
        results.append(FlashcardResult(tag: card.tag, correct: correct))
        if results.count == deck.count && kind == .translation {
            roundEndedAt = now()
            await submit()
        }
    }

    /// Sends the finished round again after a failure; the same submission id keeps it from counting twice.
    public func retrySubmit() async {
        if case .failed = xp { await submit() }
    }

    private func submit() async {
        guard let submitter = submitter, let course = roundCourse else { return }
        let id = roundId
        xp = .saving
        let request = SubmitFlashcardsRequest(
            submissionId: submissionId, courseCode: course, occurredAt: roundEndedAt, inRemix: false,
            cards: results.map { SubmittedFlashcard(tag: $0.tag, kind: .translation, correct: $0.correct) })
        do {
            let response = try await submitter.submit(request)
            if id == roundId { xp = .saved(response.xp) }
        } catch {
            if isUnauthorizedError(error) { onUnauthorized?() }
            if id == roundId {
                // A cancelled send also lands on failed, so the XP stays held for a retry.
                xp = .failed(isCancellation(error)
                    ? "Saving was interrupted. Try again."
                    : AuthRules.message(for: error, fallback: "Couldn't save this round's XP."))
            }
        }
    }

    public static func preview(store: VocabularyStore, kind: FlashcardKind, deck: [FlashcardWord]) -> FlashcardsModel {
        let model = FlashcardsModel(store: store, submitter: nil)
        model.kind = kind
        model.deck = deck
        return model
    }
}
