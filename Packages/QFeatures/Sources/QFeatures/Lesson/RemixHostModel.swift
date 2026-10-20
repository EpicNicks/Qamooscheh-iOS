import Foundation
import Combine
import QModel
import QDomain
import QNetwork

/// The step before a topics Repack plays (web RemixContentsPicker, Android LessonViewModel's Choosing): which kinds of
/// exercise it holds, or a round of fill-in-the-blank cards. A kind the Repack has none of stays on the choice with a
/// message. SwiftUI-free so swift test covers it; `RemixHostView` binds it.
@MainActor
public final class RemixHostModel: ObservableObject {
    public enum Stage {
        case choosing(selected: RemixContents, noneOfThat: Bool, hardcore: Bool)
        case working
        case failed(String)
        case lesson(LessonSession)
        case cloze(ClozeRoundModel)
    }

    @Published public private(set) var stage: Stage = .choosing(selected: .all, noneOfThat: false, hardcore: false)

    /// A topics Repack has no flashcards, so those two choices aren't offered.
    public let options = remixContentsOptions(hasFlashcards: false)

    private let route: LessonRoute
    private let environment: LessonEnvironment
    private let store: VocabularyStore
    private let makeRound: (ClozeDeck, Bool) -> ClozeRoundModel
    private let pick: (Int) -> Int

    public init(
        route: LessonRoute, environment: LessonEnvironment, store: VocabularyStore,
        makeRound: @escaping (ClozeDeck, Bool) -> ClozeRoundModel,
        pick: @escaping (Int) -> Int = { Int.random(in: 0..<max($0, 1)) }
    ) {
        self.route = route
        self.environment = environment
        self.store = store
        self.makeRound = makeRound
        self.pick = pick
    }

    public func select(_ contents: RemixContents) {
        if case .choosing(_, _, let hardcore) = stage {
            stage = .choosing(selected: contents, noneOfThat: false, hardcore: hardcore)
        }
    }

    public func setHardcore(_ hardcore: Bool) {
        if case .choosing(let selected, let none, _) = stage {
            stage = .choosing(selected: selected, noneOfThat: none, hardcore: hardcore)
        }
    }

    /// Starts the Repack with what was chosen, or says it has none of that kind and stays on the choice.
    public func start() async {
        guard case .choosing(let selected, _, let hardcore) = stage else { return }
        stage = .working
        do {
            if isClozeContents(selected) {
                try await startCloze(hardcore: hardcore)
            } else if let session = try await environment.makeSession(for: route.choosing(selected, hardcore: false)) {
                stage = .lesson(session)
            } else {
                stage = .choosing(selected: selected, noneOfThat: true, hardcore: hardcore)
            }
        } catch {
            stage = .failed(LessonScreenLogic.loadFailureMessage(for: error))
        }
    }

    /// Back to the choice after a failure.
    public func retry() {
        stage = .choosing(selected: .all, noneOfThat: false, hardcore: false)
    }

    /// One card per due word of the Repack's lessons, those due for review first, from the exercises it holds, at most
    /// `remixClozeMaxCards`; a word with no usable sentence is dropped, and none left is the empty choice.
    private func startCloze(hardcore: Bool) async throws {
        guard let pool = try await environment.loader.remixCloze(for: route) else {
            stage = .choosing(selected: .cloze, noneOfThat: true, hardcore: hardcore)
            return
        }
        await store.refresh()
        guard let content = store.content else {
            if case .failed(let message) = store.status {
                stage = .failed(message)
            } else {
                stage = .failed("Couldn't put together your fill-in-the-blank round.")
            }
            return
        }
        let deck = buildClozeDeck(
            sources: clozeSourcesForTags(pool.tags, exercises: pool.exercises),
            hintMap: ClozeRoundModel.hintMap(content.lexemes), lexemeIndex: content.lexemes, pick: pick)
        let cards = Array(deck.prefix(remixClozeMaxCards))
        if cards.isEmpty {
            stage = .choosing(selected: .cloze, noneOfThat: true, hardcore: hardcore)
            return
        }
        stage = .cloze(makeRound(ClozeDeck(courseCode: pool.courseCode, cards: cards), hardcore))
    }
}
