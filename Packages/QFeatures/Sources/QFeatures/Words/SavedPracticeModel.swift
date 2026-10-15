import Foundation
import Combine
import QModel
import QDomain
import QNetwork

/// Picks the learner's most-due saved words with exercises from lessons that use them
/// (GET /v1/vocab/starred/practice). The production conformer is a thin wrapper over the vocab repository.
public protocol SavedPracticeSource: Sendable {
    func practice(count: Int) async throws -> StarredPracticeResponse
}

/// The remix's exercises, for the lesson screen: "unitKey/skillKey/ordinal", comma-separated, at `courseVersion`.
public struct SavedPracticeExercises: Equatable, Sendable {
    public var courseVersion: Int
    public var exercises: String
    public var count: Int

    public init(courseVersion: Int, exercises: String, count: Int) {
        self.courseVersion = courseVersion
        self.exercises = exercises
        self.count = count
    }
}

public enum SavedPracticeState: Equatable, Sendable {
    case loading
    case failed(String)
    /// No saved words from this course to practise.
    case empty
    /// The words' flashcards, one at a time.
    case cards(courseCode: String, cards: [FlashcardWord], results: [FlashcardResult])
    /// The cards are done; `exercises` (nil when the words have none) are next. `xp` is nil when it couldn't be saved.
    case cardsDone(known: Int, total: Int, xp: Int?, exercises: SavedPracticeExercises?)
}

/// The saved-words remix (web SavedPracticePage, Android SavedPracticeViewModel): flashcards for the
/// most-due saved words, each self-rated and sent with inRemix so it earns XP; the exercises then play
/// on the lesson screen. Unlike the web, the cards all come first.
@MainActor
public final class SavedPracticeModel: ObservableObject {
    /// How many saved words one remix covers.
    public static let practiceWords = 10

    @Published public private(set) var state: SavedPracticeState = .loading

    public let store: VocabularyStore
    private let source: SavedPracticeSource?
    private let submitter: FlashcardSubmitter?
    private let newId: () -> String
    private let now: () -> Date
    private let onUnauthorized: (@Sendable () -> Void)?
    private var generation = 0
    private var exercises: SavedPracticeExercises?
    private var submissionId = ""

    public init(
        store: VocabularyStore, source: SavedPracticeSource?, submitter: FlashcardSubmitter?,
        newId: @escaping () -> String = { UUID().uuidString },
        now: @escaping () -> Date = { Date() },
        onUnauthorized: (@Sendable () -> Void)? = nil
    ) {
        self.store = store
        self.source = source
        self.submitter = submitter
        self.newId = newId
        self.now = now
        self.onUnauthorized = onUnauthorized
    }

    /// The card being asked, if any.
    public var current: FlashcardWord? {
        if case .cards(_, let cards, let results) = state, results.count < cards.count { return cards[results.count] }
        return nil
    }

    public var courseCode: String? {
        if case .cards(let code, _, _) = state { return code }
        return nil
    }

    /// (Re)builds the remix. The newest call wins.
    public func load() async {
        generation += 1
        let mine = generation
        state = .loading
        exercises = nil
        await store.refresh()
        if mine != generation { return }
        guard let content = store.content, let source = source else {
            state = .failed(storeFailure())
            return
        }
        do {
            let practice = try await source.practice(count: SavedPracticeModel.practiceWords)
            if mine != generation { return }
            let cards = practice.words.compactMap {
                flashcardWords(savedTags: [$0.tag], lexemeIndex: content.lexemes).first
            }
            let picked = SavedPracticeModel.distinctRefs(practice.words.flatMap { $0.exercises })
            exercises = picked.isEmpty ? nil : SavedPracticeExercises(
                courseVersion: practice.courseVersion,
                exercises: picked.map { "\($0.unitKey)/\($0.skillKey)/\($0.ordinal)" }.joined(separator: ","),
                count: picked.count)
            submissionId = newId()
            if !cards.isEmpty {
                state = .cards(courseCode: content.courseCode, cards: cards, results: [])
            } else if exercises != nil {
                state = .cardsDone(known: 0, total: 0, xp: 0, exercises: exercises)
            } else {
                state = .empty
            }
        } catch {
            if isCancellation(error) { return }
            if isUnauthorizedError(error) { onUnauthorized?() }
            if mine != generation { return }
            state = .failed(AuthRules.message(for: error, fallback: "Couldn't put together your saved-words practice."))
        }
    }

    /// Records the current card; the last one sends the round.
    public func answer(knew: Bool) async {
        guard case .cards(let code, let cards, let results) = state, results.count < cards.count else { return }
        let next = results + [FlashcardResult(tag: cards[results.count].tag, correct: knew)]
        state = .cards(courseCode: code, cards: cards, results: next)
        if next.count < cards.count { return }
        let mine = generation
        var xp: Int?
        if let submitter = submitter {
            let request = SubmitFlashcardsRequest(
                submissionId: submissionId, courseCode: code, occurredAt: now(), inRemix: true,
                cards: next.map { SubmittedFlashcard(tag: $0.tag, kind: .selfRated, correct: $0.correct) })
            do {
                xp = try await submitter.submit(request).xp
            } catch {
                if isUnauthorizedError(error) { onUnauthorized?() }
            }
        }
        if mine != generation { return }
        state = .cardsDone(known: next.filter { $0.correct }.count, total: next.count, xp: xp, exercises: exercises)
    }

    private func storeFailure() -> String {
        if case .failed(let message) = store.status { return message }
        return "Couldn't put together your saved-words practice."
    }

    static func distinctRefs(_ refs: [StarredPracticeExercise]) -> [StarredPracticeExercise] {
        var seen: [StarredPracticeExercise] = []
        for ref in refs where !seen.contains(ref) { seen.append(ref) }
        return seen
    }

    public static func preview(store: VocabularyStore, state: SavedPracticeState) -> SavedPracticeModel {
        let model = SavedPracticeModel(store: store, source: nil, submitter: nil)
        model.state = state
        return model
    }
}
