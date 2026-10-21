import SwiftUI
import QModel
import QDomain
import QData
import QDesign

/// The screens of the Repack contents picker, the fill-in-the-blank card and the race, in fixed states, for the snapshots job
/// (a person reviews the PNGs).
public enum ClozeRaceScenario: String, CaseIterable, Sendable {
    case picker
    case card
    case cardAnswered
    case lobby
    case run
    case results
    case resultsHeld
    case boards
}

public struct ClozeRaceShowcase: View {
    private let scenario: ClozeRaceScenario

    public init(_ scenario: ClozeRaceScenario) {
        self.scenario = scenario
    }

    public var body: some View {
        switch scenario {
        case .picker:
            RemixContentsPickerView(
                options: remixContentsOptions(hasFlashcards: true), selected: .cloze, noneOfThat: true, hardcore: true,
                onSelect: { _ in }, onStart: {}, onBack: {})
        case .card:
            ClozeCardView(model: ClozeRaceShowcase.cardModel(), look: ClozeRaceShowcase.look)
        case .cardAnswered:
            ClozeCardView(model: ClozeRaceShowcase.cardModel(answer: "\u{0686}\u{0627}\u{06CC}"), look: ClozeRaceShowcase.look)
        case .lobby:
            RaceLobbyView(
                mode: .perfectDelivery, hardcore: true, message: RaceModel.nothingToRace,
                onMode: { _ in }, onHardcore: { _ in }, onStart: {}, onBoards: {}, onBack: {})
        case .run:
            RaceHud(run: ClozeRaceShowcase.run, now: { 112.5 }, onClose: {})
                .frame(maxHeight: .infinity, alignment: .top)
        case .results:
            RaceResultsView(
                mode: .perfectDelivery,
                response: FinishRaceResponse(
                    score: 7.3, timeMs: 83_400, solved: 5, strikes: 2, endReason: "third_strike", xp: 21, rank: 12,
                    personalBest: RacePersonalBest(score: 8.1, timeMs: 90_000)),
                onAgain: {}, onBoards: {}, onExit: {}, onEffect: { _ in })
        case .resultsHeld:
            RaceResultsView(
                mode: .perfectDelivery,
                response: FinishRaceResponse(
                    score: 3.0, timeMs: 1_900, solved: 2, strikes: 0, endReason: "deck_done", xp: 0, held: true,
                    heldReason: "answer_too_fast"),
                onAgain: {}, onBoards: {}, onExit: {}, onEffect: { _ in })
        case .boards:
            VStack(spacing: 0) {
                ForEach(ClozeRaceShowcase.entries, id: \.userId) { RaceBoardRow(entry: $0) }
            }
            .padding(Spacing.standard.s3)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private static let look = LessonScreenLogic.textLook(prefs: LocalPrefs(), serverPrefs: LessonServerPrefs(), courseCode: "fa", hints: [:])

    private static let card = ClozeCard(
        tag: "\u{0686}\u{0627}\u{06CC}<n>", before: "\u{0645}\u{0646} ", after: " \u{0645}\u{06CC}\u{200C}\u{062E}\u{0648}\u{0631}\u{0645}",
        blankText: "\u{0686}\u{0627}\u{06CC}", accepted: ["\u{0686}\u{0627}\u{06CC}"], gapLabel: "tea",
        english: "I drink tea", contextTags: [])

    @MainActor
    private static func cardModel(answer: String? = nil) -> ClozeCardModel {
        let model = ClozeCardModel(card: card, courseCode: "fa", hardcore: false, prefs: LocalPrefs(), keyboardMode: nil)
        if let answer = answer {
            model.setTyped(answer)
            model.check { _ in }
        }
        return model
    }

    private static let run = RaceRun(
        runId: "run", courseCode: "fa", mode: .perfectDelivery, hardcore: false, deck: [card, card, card, card, card, card, card],
        weights: ["\u{0686}\u{0627}\u{06CC}<n>": 1.5],
        results: [
            ClozeResult(tag: "\u{0686}\u{0627}\u{06CC}<n>", correct: true, attempt: 1, elapsedMs: 2_000),
            ClozeResult(tag: "x", correct: true, attempt: 2, elapsedMs: 3_000),
        ],
        startedAt: 100)

    private static let entries = [
        RaceBoardEntry(rank: 1, userId: "a", displayName: "Maryam", country: "CA", score: 24.6, timeMs: 151_000),
        RaceBoardEntry(rank: 2, userId: "b", displayName: "Sam", country: "US", score: 22.1, timeMs: 140_200),
        RaceBoardEntry(rank: 14, userId: "c", displayName: "You", country: "CA", score: 9.4, timeMs: 88_000, isYou: true),
    ]
}
