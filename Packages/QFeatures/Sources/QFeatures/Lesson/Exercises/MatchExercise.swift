import SwiftUI
import QDomain
import QModel

// Match (web MatchExercise). On Android a match exercise plays exactly like the word bank
// (Exercises.kt: match plays the same way), so this is the word bank under its own name:
// the tiles are put in order, and review marks them against the closest correct order.

public struct MatchExercise: View {
    private let exercise: ExerciseArtifact
    private let courseCode: String
    private let reviewed: ReviewedAnswer?
    private let shuffled: [Int]?
    private let preplaced: [Int]
    private let onTilePicked: (String) -> Void
    private let onAnswerChange: (String?) -> Void

    public init(
        exercise: ExerciseArtifact,
        courseCode: String,
        reviewed: ReviewedAnswer? = nil,
        shuffled: [Int]? = nil,
        preplaced: [Int] = [],
        onTilePicked: @escaping (String) -> Void = { _ in },
        onAnswerChange: @escaping (String?) -> Void = { _ in }
    ) {
        self.exercise = exercise
        self.courseCode = courseCode
        self.reviewed = reviewed
        self.shuffled = shuffled
        self.preplaced = preplaced
        self.onTilePicked = onTilePicked
        self.onAnswerChange = onAnswerChange
    }

    public var body: some View {
        WordBankExercise(
            exercise: exercise,
            courseCode: courseCode,
            reviewed: reviewed,
            shuffled: shuffled,
            preplaced: preplaced,
            onTilePicked: onTilePicked,
            onAnswerChange: onAnswerChange
        )
    }
}
