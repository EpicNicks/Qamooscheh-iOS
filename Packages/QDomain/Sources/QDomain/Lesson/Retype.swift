import Foundation
import QModel

// Retyping the correct answer after a wrong typed one. Optional, and it never
// changes the answer's grade, score or requeueing: a match is only sent as that
// item's retypeText, which earns retype XP and nothing else.
// Port of web domain/retype.ts.

/// How many matching retypes of one exercise a run sends: the server credits the first two and nothing after.
public let maxCreditedRetypes = 2

/// Whether the review offers a retype: only a typed (type_in) answer, and only a wrong one.
public func needsRetype(renderType: ExerciseType, correct: Bool) -> Bool {
    return renderType == .typeIn && !correct
}

/// Whether a retype matches any accepted answer, compared exactly as the exercise's own answer was (checkAnswer), so a forgiven typo passes too. A pending result (no grader, or it errored) is not a match: nothing verified it.
public func retypeMatches(_ grader: Grader?, courseCode: String?, exercise: GradedExercise, retyped: String) -> Bool {
    if retyped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
    let verdict = checkAnswer(grader, courseCode: courseCode, exercise: exercise, submittedText: retyped).verdict
    return verdict == .correct || verdict == .acceptedWithCorrection
}
