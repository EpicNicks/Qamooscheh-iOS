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

/// What each attempt before the right one multiplies a lesson exercise's credit by.
public let lessonRetryCreditFactor: Double = 0.5

/// One attempt's lesson credit: the verdict weight halved per earlier attempt; 0 for an attempt below 1.
public func lessonAttemptCredit(_ verdict: AnswerVerdict, attempt: Int) -> Double {
    if attempt < 1 { return 0 }
    var credit = verdictWeight(verdict)
    var earlier = attempt - 1
    while earlier > 0 {
        credit *= lessonRetryCreditFactor
        earlier -= 1
    }
    return credit
}

/// One graded attempt at an exercise; `exerciseKey` is shared by every attempt (and tag) of the same exercise.
public struct LessonAttempt: Codable, Equatable, Sendable {
    public var exerciseKey: String
    public var attempt: Int
    public var verdict: AnswerVerdict

    public init(exerciseKey: String, attempt: Int, verdict: AnswerVerdict) {
        self.exerciseKey = exerciseKey
        self.attempt = attempt
        self.verdict = verdict
    }
}

/// A lesson's score, 0...1: each answered exercise's best attempt credit, averaged over the exercises answered; 0 when there are none. Attempts below 1 are ignored. Mirrors the backend's ExerciseScore.LessonScore.
public func lessonScore(_ attempts: [LessonAttempt]) -> Double {
    var best: [String: Double] = [:]
    for a in attempts where a.attempt >= 1 {
        let credit = lessonAttemptCredit(a.verdict, attempt: a.attempt)
        best[a.exerciseKey] = max(best[a.exerciseKey] ?? 0, credit)
    }
    if best.isEmpty { return 0 }
    return best.values.reduce(0, +) / Double(best.count)
}
