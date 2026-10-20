import Foundation
import Combine
import QModel
import QDomain
import QNetwork
import QData

/// The lesson exercises a saved-words cloze round cuts its sentences from. The production conformer reads the pinned course from disk.
public protocol ClozeSentenceSource: Sendable {
    /// The exercises `refs` name, by `practiceExerciseKey`. Throws when the pinned course isn't the version the server picked
    /// them against (their ordinals could point at other exercises); one whose skill file or ordinal is gone is left out.
    func exercises(_ refs: [StarredPracticeExercise], courseVersion: Int) async throws -> [String: ExerciseArtifact]
}

public struct LiveClozeSentenceSource: ClozeSentenceSource {
    private let reader: CourseContentReader
    private let course: @Sendable () async throws -> CourseRef?

    public init(reader: CourseContentReader, course: @escaping @Sendable () async throws -> CourseRef?) {
        self.reader = reader
        self.course = course
    }

    public func exercises(_ refs: [StarredPracticeExercise], courseVersion: Int) async throws -> [String: ExerciseArtifact] {
        guard let found = try await course() else { throw LessonLoadError.noCourse }
        if found.version != courseVersion { throw LessonLoadError.courseVersionMismatch }
        var skills: [String: [ExerciseArtifact]] = [:]
        var result: [String: ExerciseArtifact] = [:]
        for ref in refs {
            let skillId = ref.unitKey + "/" + ref.skillKey
            if skills[skillId] == nil {
                skills[skillId] = try reader.skill(found, unitKey: ref.unitKey, skillKey: ref.skillKey)?.exercises ?? []
            }
            let list = skills[skillId] ?? []
            if ref.ordinal >= 0 && ref.ordinal < list.count { result[practiceExerciseKey(ref)] = list[ref.ordinal] }
        }
        return result
    }
}

/// The learner's settings a cloze round reads (how typed answers are entered, how the sentence looks) and the one it saves
/// (switching to the phone's keyboard). The production conformer is `ClozeSettings.live`.
public struct ClozeSettings: Sendable {
    public var load: @Sendable () async -> (prefs: LocalPrefs, server: LessonServerPrefs)
    public var save: @Sendable (LocalPrefs) -> Void

    public init(
        load: @escaping @Sendable () async -> (prefs: LocalPrefs, server: LessonServerPrefs),
        save: @escaping @Sendable (LocalPrefs) -> Void
    ) {
        self.load = load
        self.save = save
    }

    /// Defaults, saving nothing: previews and tests.
    public static let standard = ClozeSettings(load: { (LocalPrefs(), LessonServerPrefs()) }, save: { _ in })

    /// The device prefs of the signed-in user, and the server prefs last synced for the pinned course.
    public static func live(app: AppEnvironment, prefsStore: LocalPrefsStore = LocalPrefsStore()) -> ClozeSettings {
        return ClozeSettings(
            load: {
                guard let id = await app.currentUserId(), !id.isEmpty else { return (LocalPrefs(), LessonServerPrefs()) }
                var server = LessonServerPrefs()
                if let course = try? await app.pinnedCourse(), let synced = await app.makePrefsSync(id, course.code).prefs {
                    server = LessonServerPrefs(scriptMode: synced.scriptMode, keyboardMode: synced.keyboardMode, autoplayAudio: synced.autoplayAudio)
                }
                return (prefsStore.current(userId: id), server)
            },
            save: { next in
                Task {
                    if let id = await app.currentUserId(), !id.isEmpty { _ = prefsStore.update(userId: id) { $0 = next } }
                }
            })
    }
}

/// The cards a Repack built for its cloze contents, handed to the round to play (Android ClozeDeckHandoff).
public struct ClozeDeck: Equatable, Sendable {
    public var courseCode: String
    public var cards: [ClozeCard]

    public init(courseCode: String, cards: [ClozeCard]) {
        self.courseCode = courseCode
        self.cards = cards
    }
}

/// What a round needs to be built: the saved-words picker, the sentences, the vocabulary behind them and where it is sent.
public struct ClozeServices: @unchecked Sendable {
    public var practice: SavedPracticeSource?
    public var sentences: ClozeSentenceSource?
    public var settings: ClozeSettings

    public init(practice: SavedPracticeSource?, sentences: ClozeSentenceSource?, settings: ClozeSettings = .standard) {
        self.practice = practice
        self.sentences = sentences
        self.settings = settings
    }
}

public enum ClozePhase: Equatable, Sendable {
    case loading
    case failed(String)
    /// No saved word has a sentence to cut a blank from.
    case empty
    case playing
}

/// A round of fill-in-the-blank cards (web ClozeRound, Android ClozeViewModel) over the learner's most-due saved words:
/// `GET /v1/vocab/starred/practice` picks them, with the lessons' exercises that use each, and a sentence is cut from one
/// of those. A word with no usable sentence is left out, since a cloze round is all cloze cards. The round is submitted once,
/// when it ends, as kind "cloze": the server pays the XP and counts each answer as a review, so the XP shown is whatever it
/// returns. A round built with a `handed` deck (a Repack's cloze contents) plays those cards under exactly the same rules.
@MainActor
public final class ClozeRoundModel: ObservableObject {
    /// Saved words in one round, at most.
    public static let roundWords = 20

    public let store: VocabularyStore
    /// Hardcore mode: no typo is forgiven.
    public let hardcore: Bool
    @Published public private(set) var phase: ClozePhase = .loading
    @Published public private(set) var courseCode = ""
    @Published public private(set) var deck: [ClozeCard] = []
    @Published public private(set) var results: [ClozeResult] = []
    /// Nil until the last card is in.
    @Published public private(set) var xp: ClozeXp?
    @Published public private(set) var prefs = LocalPrefs()
    @Published public private(set) var serverPrefs = LessonServerPrefs()
    /// The course-wide hint map for the sentence's tap-a-word tips.
    @Published public private(set) var hints: [String: WordHint] = [:]

    private let services: ClozeServices
    private let submitter: FlashcardSubmitter?
    private let handed: ClozeDeck?
    private let pick: (Int) -> Int
    private let newId: () -> String
    private let now: () -> Date
    private let onUnauthorized: (@Sendable () -> Void)?
    private var generation = 0
    private var submissionId = ""
    private var roundEndedAt = Date(timeIntervalSince1970: 0)

    public init(
        store: VocabularyStore, services: ClozeServices, submitter: FlashcardSubmitter?, hardcore: Bool = false,
        handed: ClozeDeck? = nil,
        pick: @escaping (Int) -> Int = { Int.random(in: 0..<max($0, 1)) },
        newId: @escaping () -> String = { UUID().uuidString },
        now: @escaping () -> Date = { Date() },
        onUnauthorized: (@Sendable () -> Void)? = nil
    ) {
        self.store = store
        self.services = services
        self.submitter = submitter
        self.hardcore = hardcore
        self.handed = handed
        self.pick = pick
        self.newId = newId
        self.now = now
        self.onUnauthorized = onUnauthorized
    }

    /// Played from a Repack's cloze contents rather than from the flashcards start screen.
    public var repack: Bool { return handed != nil }

    /// The card being asked, if any.
    public var current: ClozeCard? {
        return results.count < deck.count ? deck[results.count] : nil
    }

    /// The learner's text settings for the sentence.
    public var textLook: LessonTextLook {
        return LessonScreenLogic.textLook(prefs: prefs, serverPrefs: serverPrefs, courseCode: courseCode, hints: hints)
    }

    /// True while the round's XP is being saved or has failed and is waiting on a retry or an explicit discard.
    public var isSettlingXp: Bool {
        switch xp {
        case .saving?, .failed?: return true
        case .saved?, nil: return false
        }
    }

    /// Picks the words and sentences for a fresh round. The newest call wins.
    public func load() async {
        generation += 1
        let mine = generation
        phase = .loading
        deck = []
        results = []
        xp = nil
        submissionId = newId()
        let settings = await services.settings.load()
        if mine != generation { return }
        prefs = settings.prefs
        serverPrefs = settings.server

        if let handed = handed {
            courseCode = handed.courseCode
            deck = handed.cards
            phase = handed.cards.isEmpty ? .failed("This Repack's round was interrupted. Start it again from the Repack.") : .playing
            return
        }

        await store.refresh()
        if mine != generation { return }
        guard let content = store.content, let practiceSource = services.practice, let sentences = services.sentences else {
            phase = .failed(storeFailure())
            return
        }
        do {
            let plan = try await practiceSource.practice(count: ClozeRoundModel.roundWords)
            if mine != generation { return }
            let refs = SavedPracticeModel.distinctRefs(plan.words.flatMap { $0.exercises })
            let exercises = try await sentences.exercises(refs, courseVersion: plan.courseVersion)
            if mine != generation { return }
            let hintMap = ClozeRoundModel.hintMap(content.lexemes)
            let cards = buildClozeDeck(
                sources: clozeSourcesFromPractice(plan.words, exercises: exercises),
                hintMap: hintMap, lexemeIndex: content.lexemes, pick: pick)
            hints = hintMap
            courseCode = content.courseCode
            if cards.isEmpty {
                phase = .empty
            } else {
                deck = cards
                phase = .playing
            }
        } catch {
            if isCancellation(error) { return }
            if isUnauthorizedError(error) { onUnauthorized?() }
            if mine != generation { return }
            phase = .failed(AuthRules.message(for: error, fallback: "Couldn't put together your fill-in-the-blank round."))
        }
    }

    /// The course-wide hint map from the lexeme index. A dictionary has lost lexemes.json's authored order, so the tags are
    /// sorted; only which homograph's romanization wins depends on the order, never where a word is found.
    nonisolated static func hintMap(_ lexemes: [String: LexemeIndexEntry]) -> [String: WordHint] {
        return buildLexemeHintMap(lexemes.keys.sorted().compactMap { tag in lexemes[tag].map { (tag: tag, entry: $0) } })
    }

    /// The device prefs changed mid-round (the switch to the phone's keyboard); the next card starts with them too.
    public func savePrefs(_ next: LocalPrefs) {
        prefs = next
        services.settings.save(next)
    }

    /// A card is done (right, or shown): the round is sent once the last one is in.
    public func finished(_ result: ClozeResult) async {
        guard phase == .playing, results.count < deck.count else { return }
        results.append(result)
        if results.count < deck.count { return }
        roundEndedAt = now()
        await submit()
    }

    /// Sends the finished round again after a failure; the same submission id keeps it from counting twice.
    public func retrySubmit() async {
        if xp == .failed { await submit() }
    }

    private func submit() async {
        guard let submitter = submitter, !courseCode.isEmpty else {
            xp = .failed
            return
        }
        let mine = generation
        xp = .saving
        let request = SubmitFlashcardsRequest(
            submissionId: submissionId, courseCode: courseCode, occurredAt: roundEndedAt, inRemix: false,
            hardcore: hardcore, cards: results.map { $0.submitted })
        do {
            let response = try await submitter.submit(request)
            if mine == generation { xp = .saved(response.xp) }
        } catch {
            if isUnauthorizedError(error) { onUnauthorized?() }
            if mine == generation { xp = .failed }
        }
    }

    private func storeFailure() -> String {
        if case .failed(let message) = store.status { return message }
        return "Couldn't put together your fill-in-the-blank round."
    }

    public static func preview(
        store: VocabularyStore, courseCode: String, deck: [ClozeCard], results: [ClozeResult] = [], xp: ClozeXp? = nil, hints: [String: WordHint] = [:]
    ) -> ClozeRoundModel {
        let model = ClozeRoundModel(store: store, services: ClozeServices(practice: nil, sentences: nil), submitter: nil)
        model.courseCode = courseCode
        model.deck = deck
        model.results = results
        model.xp = xp
        model.hints = hints
        model.phase = .playing
        return model
    }
}
