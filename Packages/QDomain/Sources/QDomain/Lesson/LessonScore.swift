import Foundation

// The lesson pass mark, mirroring the backend's ExerciseScore: a lesson
// completes its skill only when every exercise was answered and the first
// attempts score at least 75%, each weighted Correct = 1,
// AcceptedWithCorrection = 0.5, otherwise 0. The server's verdict is what
// counts; this lets the recap say the same without waiting on it.
// Port of web domain/lessonScore.ts.

public let lessonPassThreshold: Double = 0.75

/// A pending verdict (nothing could grade it here) weighs 0, as Android counts only checked first attempts.
public func verdictWeight(_ verdict: AnswerVerdict) -> Double {
    switch verdict {
    case .correct: return 1
    case .acceptedWithCorrection: return 0.5
    case .incorrect, .pending: return 0
    }
}
