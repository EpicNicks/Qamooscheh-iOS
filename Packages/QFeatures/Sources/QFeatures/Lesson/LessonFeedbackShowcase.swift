import SwiftUI
import QDesign
import QDomain
import QModel

public enum LessonFeedbackScenario: Sendable {
    case correct
    case wrongWithMistakeHint
    case resultsWithStreakAndGoal
}

/// Gallery for snapshot tests: static (no animation), hand-made data, no course content needed.
public struct LessonFeedbackShowcase: View {
    private let scenario: LessonFeedbackScenario
    @Environment(\.colorScheme) private var colorScheme

    public init(_ scenario: LessonFeedbackScenario) {
        self.scenario = scenario
    }

    private static func instance() -> ExerciseInstance {
        let exercise = ExerciseArtifact(type: .typeIn, scriptMode: .native, prompt: "Hello", answer: ["salam", "salaam"], tags: ["salam"])
        return ExerciseInstance(key: "k", unitKey: "u1", skillKey: "greetings", ordinal: 0, exercise: exercise, renderType: .typeIn)
    }

    public var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        VStack(spacing: 0) {
            switch scenario {
            case .correct:
                SessionProgressBar(completed: 3, total: 8).padding(Spacing.standard.s3)
                Spacer()
                AnswerFeedbackView(
                    review: FeedbackReview(feedback: AnswerFeedback(verdict: .correct, note: nil, xp: 10, separators: nil), instance: Self.instance(), submittedText: "salam", xp: 10),
                    onContinue: {}, onPlayAnswer: {}, animated: false)
            case .wrongWithMistakeHint:
                SessionProgressBar(completed: 5, total: 8).padding(Spacing.standard.s3)
                Spacer()
                AnswerFeedbackView(
                    review: FeedbackReview(feedback: AnswerFeedback(verdict: .incorrect, note: "Check the vowel after the first consonant.", xp: 0, separators: nil), instance: Self.instance(), submittedText: "salom", xp: 0),
                    onContinue: {}, onPlayAnswer: {}, startRevealed: true, animated: false)
            case .resultsWithStreakAndGoal:
                LessonResultsView(
                    end: .saved(completed: true, alreadyRecorded: false),
                    stats: LessonResultsStats(correct: 7, total: 8, score: 0.875, xp: 70, streakDays: 5, goalXpToday: 40, goalXp: 50),
                    animated: false, onBack: {}, onShare: {}, onPracticeAgain: {})
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(argb: p.bg))
    }
}
