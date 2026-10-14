import SwiftUI
import QDesign
import QDomain
import QModel

public enum ExerciseScenario: Sendable {
    case promptJapanese
    case promptPersian
    case bankEmpty
    case bankPartial
    case bankFull
    case bankPersianRtl
    case matchSelected
    case matchMatched
    case matchWrong
}

/// Gallery for snapshot tests: hand-made exercises so no course content is needed.
public struct ExerciseShowcase: View {
    private let scenario: ExerciseScenario
    @Environment(\.colorScheme) private var colorScheme

    public init(_ scenario: ExerciseScenario) {
        self.scenario = scenario
    }

    private static let japanese: [String: WordHint] = [
        "私": WordHint(translation: "I", romanization: "watashi", ruby: "わたし"),
        "学校": WordHint(translation: "school", romanization: "gakkou", ruby: "がっこう"),
        "行き": WordHint(translation: "go", romanization: "iki", ruby: "いき"),
    ]

    private static let persian: [String: WordHint] = [
        "کتاب": WordHint(translation: "book", romanization: "ketāb", ruby: "ketāb"),
        "من": WordHint(translation: "my, me", romanization: "man", ruby: "man"),
    ]

    private static let jaPrompt = ExerciseArtifact(type: .wordBank, scriptMode: .native, prompt: "私は学校に行きます", tiles: [], answer: [])
    private static let faPrompt = ExerciseArtifact(type: .wordBank, scriptMode: .native, prompt: "کتاب من خوب است", tiles: [], answer: [])
    private static let jaBank = ExerciseArtifact(
        type: .wordBank, scriptMode: .native, prompt: "I go to school",
        tiles: ["私は", "学校に", "行きます", "毎日"], answer: ["私は", "学校に", "行きます"]
    )
    private static let faBank = ExerciseArtifact(
        type: .wordBank, scriptMode: .native, prompt: "My book is good",
        tiles: ["کتاب", "من", "خوب", "است", "بد"], answer: ["کتاب", "من", "خوب", "است"]
    )
    private static let jaMatch = ExerciseArtifact(
        type: .match, scriptMode: .native, prompt: "I go to school",
        tiles: ["私は", "学校に", "行きます", "毎日"], answer: ["私は", "学校に", "行きます"]
    )

    private func look(_ hints: [String: WordHint]) -> LessonTextLook {
        return LessonTextLook(
            settings: TextDisplaySettings(
                display: .native,
                translationEnabled: true,
                romanizationEnabled: true,
                nativeEnabled: true,
                vowelMarks: true,
                sentenceRomanization: true
            ),
            courseHints: hints
        )
    }

    // A partial bank is a state a person reaches by tapping; here the exercise is rebuilt
    // already holding some tiles via a preset, so the picture needs no gestures.
    @ViewBuilder
    private var content: some View {
        switch scenario {
        case .promptJapanese:
            ExercisePrompt(exercise: ExerciseShowcase.jaPrompt, courseCode: "ja", hasVoice: true)
                .environment(\.lessonTextLook, look(ExerciseShowcase.japanese))
        case .promptPersian:
            ExercisePrompt(exercise: ExerciseShowcase.faPrompt, courseCode: "fa", hasVoice: false)
                .environment(\.lessonTextLook, look(ExerciseShowcase.persian))
        case .bankEmpty:
            WordBankExercise(exercise: ExerciseShowcase.jaBank, courseCode: "ja", shuffled: [3, 1, 0, 2])
                .environment(\.lessonTextLook, look(ExerciseShowcase.japanese))
        case .bankPartial:
            WordBankExercise(exercise: ExerciseShowcase.jaBank, courseCode: "ja", shuffled: [3, 1, 0, 2], preplaced: [0])
                .environment(\.lessonTextLook, look(ExerciseShowcase.japanese))
        case .bankFull:
            WordBankExercise(exercise: ExerciseShowcase.jaBank, courseCode: "ja", shuffled: [3, 1, 0, 2], preplaced: [0, 1, 2])
                .environment(\.lessonTextLook, look(ExerciseShowcase.japanese))
        case .bankPersianRtl:
            WordBankExercise(exercise: ExerciseShowcase.faBank, courseCode: "fa", shuffled: [4, 2, 0, 3, 1], preplaced: [0, 1])
                .environment(\.lessonTextLook, look(ExerciseShowcase.persian))
        case .matchSelected:
            MatchExercise(exercise: ExerciseShowcase.jaMatch, courseCode: "ja", shuffled: [3, 1, 0, 2], preplaced: [0])
                .environment(\.lessonTextLook, look(ExerciseShowcase.japanese))
        case .matchMatched:
            MatchExercise(exercise: ExerciseShowcase.jaMatch, courseCode: "ja", reviewed: ReviewedAnswer(text: "私は 学校に 行きます", correct: true), shuffled: [3, 1, 0, 2])
                .environment(\.lessonTextLook, look(ExerciseShowcase.japanese))
        case .matchWrong:
            MatchExercise(exercise: ExerciseShowcase.jaMatch, courseCode: "ja", reviewed: ReviewedAnswer(text: "学校に 私は 毎日", correct: false), shuffled: [3, 1, 0, 2])
                .environment(\.lessonTextLook, look(ExerciseShowcase.japanese))
        }
    }

    public var body: some View {
        let palette = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        content
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(argb: palette.bg))
    }
}
