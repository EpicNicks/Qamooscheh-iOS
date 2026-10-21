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

    /// `exercises` parsed back into references; malformed entries are skipped.
    public var refs: [StarredPracticeExercise] {
        var result: [StarredPracticeExercise] = []
        for part in exercises.split(separator: ",") {
            let pieces = part.split(separator: "/", omittingEmptySubsequences: false)
            guard pieces.count == 3, !pieces[0].isEmpty, !pieces[1].isEmpty, let ordinal = Int(pieces[2]) else { continue }
            result.append(StarredPracticeExercise(unitKey: String(pieces[0]), skillKey: String(pieces[1]), ordinal: ordinal))
        }
        return result
    }
}

public enum SavedPracticeState: Equatable, Sendable {
    case loading
    case failed(String)
    /// No saved words from this course to practise.
    case empty
    /// What the Repack should hold (web RemixContentsPicker), over everything the picked words brought. `noneOfThat` after a Start that found nothing.
    case choosing(options: [RemixContents], selected: RemixContents, noneOfThat: Bool, hardcore: Bool)
    /// The words' flashcards, one at a time.
    case cards(courseCode: String, cards: [FlashcardWord], results: [FlashcardResult])
    /// The cards are done; `exercises` (nil when the words have none) are next. `xp` is nil when it couldn't be saved.
    case cardsDone(known: Int, total: Int, xp: Int?, exercises: SavedPracticeExercises?)
}

/// The saved-words remix (web SavedPracticePage, Android SavedPracticeViewModel): flashcards for the
/// most-due saved words, each self-rated and sent with inRemix so it earns XP; the exercises then play
/// on the lesson screen. Unlike the web, the cards all come first. Before any of that the learner chooses what it holds:
/// flashcards, exercises, or both, or a round of fill-in-the-blank cards, which `clozeRound` plays: its deck is built
/// here and handed to the round.
@MainActor
public final class SavedPracticeModel: ObservableObject {
    /// How many saved words one remix covers.
    public static let practiceWords = 10

    @Published public private(set) var state: SavedPracticeState = .loading
    /// Set while a fill-in-the-blank round is being played.
    @Published public private(set) var clozeRound: ClozeRoundModel?

    public let store: VocabularyStore
    private let source: SavedPracticeSource?
    private let submitter: FlashcardSubmitter?
    private let cloze: ClozeServices?
    private let newId: () -> String
    private let now: () -> Date
    private let onUnauthorized: (@Sendable () -> Void)?
    private var generation = 0
    private var exercises: SavedPracticeExercises?
    private var submissionId = ""
    /// Everything the picked words brought, before the choice narrows it.
    private var builtCards: [FlashcardWord] = []
    private var builtRefs: [StarredPracticeExercise] = []
    private var practiceWords: [StarredPracticeWord] = []
    private var courseVersion = 0
    private var builtCourseCode = ""

    public init(
        store: VocabularyStore, source: SavedPracticeSource?, submitter: FlashcardSubmitter?, cloze: ClozeServices? = nil,
        newId: @escaping () -> String = { UUID().uuidString },
        now: @escaping () -> Date = { Date() },
        onUnauthorized: (@Sendable () -> Void)? = nil
    ) {
        self.store = store
        self.source = source
        self.submitter = submitter
        self.cloze = cloze
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
        clozeRound = nil
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
            submissionId = newId()
            builtCards = cards
            builtRefs = picked
            practiceWords = practice.words
            courseVersion = practice.courseVersion
            builtCourseCode = content.courseCode
            exercises = nil
            if cards.isEmpty && picked.isEmpty {
                state = .empty
            } else {
                // The flashcards come too unless the learner narrows it, as before the choice existed.
                state = .choosing(
                    options: remixContentsOptions(hasFlashcards: !cards.isEmpty), selected: cards.isEmpty ? .all : .flashcardsAndAll,
                    noneOfThat: false, hardcore: false)
            }
        } catch {
            if isCancellation(error) { return }
            if isUnauthorizedError(error) { onUnauthorized?() }
            if mine != generation { return }
            state = .failed(AuthRules.message(for: error, fallback: "Couldn't put together your saved-words practice."))
        }
    }

    public func selectContents(_ contents: RemixContents) {
        if case .choosing(let options, _, _, let hardcore) = state {
            state = .choosing(options: options, selected: contents, noneOfThat: false, hardcore: hardcore)
        }
    }

    public func setHardcore(_ hardcore: Bool) {
        if case .choosing(let options, let selected, let none, _) = state {
            state = .choosing(options: options, selected: selected, noneOfThat: none, hardcore: hardcore)
        }
    }

    /// Back to the choice from a finished or abandoned fill-in-the-blank round.
    public func leaveCloze() {
        clozeRound = nil
    }

    /// Starts the Repack with what was chosen; stays on the choice, with a message, when the words have none of it (web `start`).
    public func start() async {
        guard case .choosing(let options, let selected, _, let hardcore) = state else { return }
        if isClozeContents(selected) {
            await startCloze(options: options, hardcore: hardcore)
            return
        }
        let mine = generation
        let types = await renderTypes()
        if mine != generation { return }
        let kept = selectSavedRemix(cards: builtCards, exercises: builtRefs, contents: selected, renderType: { types[practiceExerciseKey($0)] })
        if kept.isEmpty {
            state = .choosing(options: options, selected: selected, noneOfThat: true, hardcore: hardcore)
            return
        }
        exercises = kept.exercises.isEmpty ? nil : SavedPracticeExercises(
            courseVersion: courseVersion,
            exercises: kept.exercises.map { "\($0.unitKey)/\($0.skillKey)/\($0.ordinal)" }.joined(separator: ","),
            count: kept.exercises.count)
        if kept.cards.isEmpty {
            state = .cardsDone(known: 0, total: 0, xp: 0, exercises: exercises)
        } else {
            state = .cards(courseCode: builtCourseCode, cards: kept.cards, results: [])
        }
    }

    /// How each picked exercise will show, by `practiceExerciseKey`; empty when the lessons can't be read (the unknown ones then
    /// stay only in the choices that keep everything). A composite exercise is judged as for a word with no card.
    private func renderTypes() async -> [String: ExerciseType] {
        guard let sentences = cloze?.sentences, !builtRefs.isEmpty,
              let found = try? await sentences.exercises(builtRefs, courseVersion: courseVersion) else { return [:] }
        return found.mapValues { resolveExerciseType($0, cardState: nil) }
    }

    /// The picked words' fill-in-the-blank round; words with no usable sentence are dropped, and none left is the empty choice.
    private func startCloze(options: [RemixContents], hardcore: Bool) async {
        guard let services = cloze, let sentences = services.sentences, let content = store.content else {
            state = .failed("Couldn't put together your fill-in-the-blank round.")
            return
        }
        let mine = generation
        do {
            let found = try await sentences.exercises(builtRefs, courseVersion: courseVersion)
            if mine != generation { return }
            let deck = buildClozeDeck(
                sources: clozeSourcesFromPractice(practiceWords, exercises: found),
                hintMap: ClozeRoundModel.hintMap(content.lexemes), lexemeIndex: content.lexemes,
                pick: { Int.random(in: 0..<max($0, 1)) })
            if deck.isEmpty {
                state = .choosing(options: options, selected: .cloze, noneOfThat: true, hardcore: hardcore)
                return
            }
            clozeRound = ClozeRoundModel(
                store: store, services: services, submitter: submitter, hardcore: hardcore,
                handed: ClozeDeck(courseCode: content.courseCode, cards: Array(deck.prefix(maxClozeSubmitCards))),
                onUnauthorized: onUnauthorized)
        } catch {
            if isCancellation(error) { return }
            if isUnauthorizedError(error) { onUnauthorized?() }
            if mine != generation { return }
            state = .failed(AuthRules.message(for: error, fallback: "Couldn't put together your fill-in-the-blank round."))
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
