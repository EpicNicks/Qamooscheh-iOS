import Foundation
import QModel

// A story chapter's transcript (web StoryTranscript, matching Android StoryTranscript.kt): the lines before the
// current one, each with its correct answer, marked by how the learner did. Pure, so swift test covers it.

/// A story chapter's lines: the screen shows those before the current one, answered.
public struct StoryChapter: Equatable, Sendable {
    public var title: String
    public var exercises: [ExerciseArtifact]

    public init(title: String, exercises: [ExerciseArtifact]) {
        self.title = title
        self.exercises = exercises
    }
}

/// How the learner did on a line; unmarked until the line has been answered.
public enum StoryMark: Equatable, Sendable {
    case correct
    case incorrect
    case unmarked
}

public struct StoryLine: Equatable, Sendable {
    public var ordinal: Int
    public var exercise: ExerciseArtifact
    /// The correct answer as shown under the prompt.
    public var answer: String
    public var mark: StoryMark

    public init(ordinal: Int, exercise: ExerciseArtifact, answer: String, mark: StoryMark) {
        self.ordinal = ordinal
        self.exercise = exercise
        self.answer = answer
        self.mark = mark
    }
}

public enum StoryTranscript {
    /// Word bank and match answers read as one sentence; the rest list their alternatives.
    public static func answerText(_ exercise: ExerciseArtifact) -> String {
        switch exercise.type {
        case .wordBank, .match: return exercise.answer.joined(separator: " ")
        case .typeIn, .speak: return exercise.answer.joined(separator: " / ")
        }
    }

    /// The chapter's lines before `upTo` (clamped to the chapter), in order.
    public static func lines(_ chapter: StoryChapter, upTo: Int, results: [Int: Bool]) -> [StoryLine] {
        let count = max(0, min(upTo, chapter.exercises.count))
        return (0..<count).map { ordinal in
            let exercise = chapter.exercises[ordinal]
            let mark: StoryMark
            switch results[ordinal] {
            case .some(true): mark = .correct
            case .some(false): mark = .incorrect
            case .none: mark = .unmarked
            }
            return StoryLine(ordinal: ordinal, exercise: exercise, answer: answerText(exercise), mark: mark)
        }
    }

    /// Whether a first answer shows as right: a correct or corrected answer, or one nothing could grade here.
    public static func countsAsRight(_ verdict: AnswerVerdict) -> Bool {
        switch verdict {
        case .correct, .acceptedWithCorrection, .pending: return true
        case .incorrect: return false
        }
    }

    /// Each line's first answer is kept; a later try of the same ordinal does not change its mark.
    public static func recording(_ results: [Int: Bool], ordinal: Int, verdict: AnswerVerdict) -> [Int: Bool] {
        if results[ordinal] != nil { return results }
        var next = results
        next[ordinal] = countsAsRight(verdict)
        return next
    }

    public static func glyph(_ mark: StoryMark) -> String {
        switch mark {
        case .correct: return "\u{2713}"
        case .incorrect: return "\u{2717}"
        case .unmarked: return ""
        }
    }

    public static func accessibilityLabel(_ line: StoryLine) -> String {
        let lead: String
        switch line.mark {
        case .correct: lead = "Answered correctly"
        case .incorrect: lead = "Answered incorrectly"
        case .unmarked: lead = "Line"
        }
        return "\(lead): \(line.exercise.prompt), \(line.answer)"
    }
}
