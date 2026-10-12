import Foundation
import QModel

// API_SPEC.md section 2.5's "exercise resolution step", client half. An
// exercise is "composite" when it is type_in and also carries tiles. Its first
// showing is a word bank for a lexeme that is new or recently lapsed, typing
// once established. A placeholder rule until real FSRS state is on the client;
// the server re-derives the mode when grading, so this is UX, not correctness.
// Port of web domain/exerciseResolution.ts (same rule as Android Answers.kt).

public func isComposite(_ exercise: ExerciseArtifact) -> Bool {
    return exercise.type == .typeIn && !(exercise.tiles ?? []).isEmpty
}

/// Which mode to render a (possibly composite) exercise in, given the locally known card state for its primary tag (nil: a new card).
public func resolveExerciseType(_ exercise: ExerciseArtifact, cardState: CardState?) -> ExerciseType {
    if !isComposite(exercise) { return exercise.type }
    guard let card = cardState else { return .wordBank }
    let recentlyLapsed = card.lapseCount > 0 && card.reviewCount <= card.lapseCount + 1
    return recentlyLapsed ? .wordBank : .typeIn
}
