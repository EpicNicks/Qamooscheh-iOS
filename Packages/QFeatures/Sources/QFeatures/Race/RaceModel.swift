import Foundation
import Combine
import QModel
import QDomain
import QNetwork
import QData

/// The race endpoints (API_SPEC 2.8b). The production conformer is `LiveRaceService`.
public protocol RaceService: Sendable {
    func start(courseCode: String, mode: RaceMode, hardcore: Bool, tags: [String]) async throws -> StartRaceResponse
    func finish(runId: String, answers: [RaceAnswer], deckDone: Bool) async throws -> FinishRaceResponse
    func board(courseCode: String, scope: RaceScope, hardcore: Bool) async throws -> RaceBoardResponse
}

/// The race over `RaceRepository`; `afterFinish` lets the caller refresh the day's progress and streak, since every answer pays.
public struct LiveRaceService: RaceService {
    private let repository: RaceRepository
    private let afterFinish: (@Sendable () async -> Void)?

    public init(repository: RaceRepository, afterFinish: (@Sendable () async -> Void)? = nil) {
        self.repository = repository
        self.afterFinish = afterFinish
    }

    public func start(courseCode: String, mode: RaceMode, hardcore: Bool, tags: [String]) async throws -> StartRaceResponse {
        return try await repository.start(courseCode: courseCode, mode: mode, hardcore: hardcore, tags: tags)
    }

    public func finish(runId: String, answers: [RaceAnswer], deckDone: Bool) async throws -> FinishRaceResponse {
        let response = try await repository.finish(runId: runId, answers: answers, deckDone: deckDone)
        await afterFinish?()
        return response
    }

    public func board(courseCode: String, scope: RaceScope, hardcore: Bool) async throws -> RaceBoardResponse {
        return try await repository.board(courseCode: courseCode, scope: scope, hardcore: hardcore)
    }
}

/// A run on screen: the cards dealt, the answers so far, and whether it is over and being sent.
public struct RaceRun: Equatable, Sendable {
    public var runId: String
    public var courseCode: String
    public var mode: RaceMode
    public var hardcore: Bool
    public var deck: [ClozeCard]
    public var weights: [String: Double]
    public var results: [ClozeResult]
    /// When the run began on this device, in `ProcessInfo.systemUptime` seconds: for the on-screen clock only (the server times the run).
    public var startedAt: TimeInterval
    public var finishing = false
    /// Why the finish didn't go through; the answers are kept so it can be sent again.
    public var sendFailed: String?

    public init(
        runId: String, courseCode: String, mode: RaceMode, hardcore: Bool, deck: [ClozeCard], weights: [String: Double],
        results: [ClozeResult] = [], startedAt: TimeInterval
    ) {
        self.runId = runId
        self.courseCode = courseCode
        self.mode = mode
        self.hardcore = hardcore
        self.deck = deck
        self.weights = weights
        self.results = results
        self.startedAt = startedAt
    }

    /// The card being asked, if any.
    public var current: ClozeCard? { return finishing ? nil : (results.count < deck.count ? deck[results.count] : nil) }
    public var strikes: Int { return RaceScoring.strikes(results) }
    public var score: Double { return RaceScoring.score(results, weights: weights) }
}

public enum RaceStage: Equatable, Sendable {
    /// Choosing the mode; `message` is why the last start didn't happen.
    case lobby(mode: RaceMode, hardcore: Bool, message: String?)
    case starting
    case run(RaceRun)
    case done(mode: RaceMode, hardcore: Bool, response: FinishRaceResponse)
}

/// The Repack race (docs/repack-race.md; web, Android RaceViewModel). The deck is built and graded here like a cloze round;
/// the server issues the FSRS weights at start and times and scores the run at finish. Both ends need the network, and a
/// finish that fails keeps the answers so it can be sent again. Leaving a run unfinished just abandons it: the next start closes it.
@MainActor
public final class RaceModel: ObservableObject {
    /// The most saved words one race deals: the practice endpoint's ceiling.
    public static let raceWords = 30
    public static let nothingToRace =
        "No saved word has a sentence and a review yet. Finish a unit, save its words, then come back. Each unit you finish unlocks more cards."

    @Published public private(set) var stage: RaceStage = .lobby(mode: .perfectDelivery, hardcore: false, message: nil)
    @Published public private(set) var prefs = LocalPrefs()
    @Published public private(set) var serverPrefs = LessonServerPrefs()
    /// The course-wide hint map for the sentence's tap-a-word tips.
    @Published public private(set) var hints: [String: WordHint] = [:]

    public let store: VocabularyStore
    private let race: RaceService?
    private let services: ClozeServices
    private let pick: (Int) -> Int
    private let clock: () -> TimeInterval
    private let onUnauthorized: (@Sendable () -> Void)?

    public init(
        store: VocabularyStore, race: RaceService?, services: ClozeServices,
        pick: @escaping (Int) -> Int = { Int.random(in: 0..<max($0, 1)) },
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        onUnauthorized: (@Sendable () -> Void)? = nil
    ) {
        self.store = store
        self.race = race
        self.services = services
        self.pick = pick
        self.clock = clock
        self.onUnauthorized = onUnauthorized
    }

    /// The uptime the on-screen clock reads.
    public func now() -> TimeInterval { return clock() }

    /// The learner's text settings for the sentence.
    public var textLook: LessonTextLook {
        let code: String
        if case .run(let run) = stage { code = run.courseCode } else { code = store.content?.courseCode ?? "" }
        return LessonScreenLogic.textLook(prefs: prefs, serverPrefs: serverPrefs, courseCode: code, hints: hints)
    }

    public func selectMode(_ mode: RaceMode) {
        if case .lobby(_, let hardcore, _) = stage { stage = .lobby(mode: mode, hardcore: hardcore, message: nil) }
    }

    public func setHardcore(_ hardcore: Bool) {
        if case .lobby(let mode, _, _) = stage { stage = .lobby(mode: mode, hardcore: hardcore, message: nil) }
    }

    /// The device prefs changed mid-run (the switch to the phone's keyboard); the next card starts with them too.
    public func savePrefs(_ next: LocalPrefs) {
        prefs = next
        services.settings.save(next)
    }

    /// Builds the deck, asks the server for the run and the weights, and deals only the words it weighted.
    public func start() async {
        guard case .lobby(let mode, let hardcore, _) = stage else { return }
        stage = .starting
        let lobby = RaceStage.lobby(mode: mode, hardcore: hardcore, message: nil)
        do {
            let settings = await services.settings.load()
            prefs = settings.prefs
            serverPrefs = settings.server
            await store.refresh()
            guard let content = store.content, let practice = services.practice, let sentences = services.sentences, let race = race else {
                stage = .lobby(mode: mode, hardcore: hardcore, message: storeFailure())
                return
            }
            let plan = try await practice.practice(count: RaceModel.raceWords)
            let refs = SavedPracticeModel.distinctRefs(plan.words.flatMap { $0.exercises })
            let found = try await sentences.exercises(refs, courseVersion: plan.courseVersion)
            let hintMap = ClozeRoundModel.hintMap(content.lexemes)
            let cards = buildClozeDeck(
                sources: clozeSourcesFromPractice(plan.words, exercises: found),
                hintMap: hintMap, lexemeIndex: content.lexemes, pick: pick)
            hints = hintMap
            if cards.isEmpty {
                stage = .lobby(mode: mode, hardcore: hardcore, message: RaceModel.nothingToRace)
                return
            }
            let started = try await race.start(courseCode: content.courseCode, mode: mode, hardcore: hardcore, tags: cards.map { $0.tag })
            let dealt = RaceScoring.dealable(cards, tagOf: { $0.tag }, weights: started.weights)
            if dealt.isEmpty {
                stage = .lobby(mode: mode, hardcore: hardcore, message: RaceModel.nothingToRace)
                return
            }
            stage = .run(RaceRun(
                runId: started.runId, courseCode: content.courseCode, mode: mode, hardcore: hardcore,
                deck: Array(dealt.prefix(maxClozeSubmitCards)), weights: started.weights, startedAt: clock()))
        } catch {
            if isCancellation(error) { stage = lobby; return }
            if isUnauthorizedError(error) { onUnauthorized?() }
            stage = .lobby(mode: mode, hardcore: hardcore, message: AuthRules.message(for: error, fallback: "Couldn't start the race."))
        }
    }

    /// A card is done (right, or shown). The run ends at the third strike in Perfect Delivery, or when the deck is out.
    public func finished(_ result: ClozeResult) async {
        guard case .run(var run) = stage, !run.finishing else { return }
        run.results.append(result)
        stage = .run(run)
        if RaceScoring.ended(run.mode, run.results) || run.results.count >= run.deck.count { await send() }
    }

    /// Endless Practice: the learner stops, and what they did is banked.
    public func stop() async {
        guard case .run(let run) = stage, !run.results.isEmpty, !run.finishing else { return }
        await send()
    }

    /// Sends the same answers again after a failure; the server answers a repeat with what it banked.
    public func retrySend() async {
        guard case .run(let run) = stage, run.finishing, run.sendFailed != nil else { return }
        await send()
    }

    /// Back to choosing a mode, after a result.
    public func again() {
        if case .done(let mode, let hardcore, _) = stage { stage = .lobby(mode: mode, hardcore: hardcore, message: nil) }
    }

    /// Whether leaving now would bank the run (Endless Practice with answers in) rather than throw it away.
    public var leavingBanksTheRun: Bool {
        if case .run(let run) = stage { return run.mode == .endlessPractice && !run.results.isEmpty }
        return false
    }

    private func send() async {
        guard case .run(var run) = stage, let race = race else { return }
        run.finishing = true
        run.sendFailed = nil
        stage = .run(run)
        let answers = run.results.map { RaceAnswer(tag: $0.tag, attempt: $0.attempt, correct: $0.correct, elapsedMs: $0.elapsedMs) }
        do {
            let response = try await race.finish(runId: run.runId, answers: answers, deckDone: run.results.count >= run.deck.count)
            stage = .done(mode: run.mode, hardcore: run.hardcore, response: response)
        } catch {
            if isUnauthorizedError(error) { onUnauthorized?() }
            if case .run(var failed) = stage {
                failed.sendFailed = AuthRules.message(for: error, fallback: "Couldn't send your run.")
                stage = .run(failed)
            }
        }
    }

    private func storeFailure() -> String {
        if case .failed(let message) = store.status { return message }
        return "Couldn't start the race."
    }
}
