import Foundation


/// GET /v1/vocab/starred.
public struct StarredVocabResponse: Codable, Equatable, Sendable {
    public var tags: [String]
    public var limit: Int
    public var refused: [String]

    public init(tags: [String], limit: Int, refused: [String]) {
        self.tags = tags
        self.limit = limit
        self.refused = refused
    }
}

/// Star or unstar one tag.
public struct SetStarredRequest: Codable, Equatable, Sendable {
    public var tag: String
    public var starred: Bool

    public init(tag: String, starred: Bool) {
        self.tag = tag
        self.starred = starred
    }
}

/// Star and unstar in bulk.
public struct BatchSetStarredRequest: Codable, Equatable, Sendable {
    public var star: [String]
    public var unstar: [String]

    public init(star: [String], unstar: [String]) {
        self.star = star
        self.unstar = unstar
    }
}

/// An exercise by skill keys and ordinal.
public struct StarredPracticeExercise: Codable, Equatable, Sendable {
    public var unitKey: String
    public var skillKey: String
    public var ordinal: Int

    public init(unitKey: String, skillKey: String, ordinal: Int) {
        self.unitKey = unitKey
        self.skillKey = skillKey
        self.ordinal = ordinal
    }
}

/// A starred word and its exercises.
public struct StarredPracticeWord: Codable, Equatable, Sendable {
    public var tag: String
    public var exercises: [StarredPracticeExercise]

    public init(tag: String, exercises: [StarredPracticeExercise]) {
        self.tag = tag
        self.exercises = exercises
    }
}

/// Starred practice plan.
public struct StarredPracticeResponse: Codable, Equatable, Sendable {
    public var courseVersion: Int
    public var words: [StarredPracticeWord]

    public init(courseVersion: Int, words: [StarredPracticeWord]) {
        self.courseVersion = courseVersion
        self.words = words
    }
}

/// One flashcard result.
public struct SubmittedFlashcard: Codable, Equatable, Sendable {
    public var tag: String
    public var kind: FlashcardKind
    public var correct: Bool

    public init(tag: String, kind: FlashcardKind, correct: Bool) {
        self.tag = tag
        self.kind = kind
        self.correct = correct
    }
}

/// POST /v1/flashcards/submit.
public struct SubmitFlashcardsRequest: Codable, Equatable, Sendable {
    public var submissionId: String
    public var courseCode: String
    public var occurredAt: Date
    public var inRemix: Bool
    public var cards: [SubmittedFlashcard]

    public init(submissionId: String, courseCode: String, occurredAt: Date, inRemix: Bool, cards: [SubmittedFlashcard]) {
        self.submissionId = submissionId
        self.courseCode = courseCode
        self.occurredAt = occurredAt
        self.inRemix = inRemix
        self.cards = cards
    }
}

/// Flashcard submit result.
public struct SubmitFlashcardsResponse: Codable, Equatable, Sendable {
    public var alreadyProcessed: Bool
    public var xp: Int

    public init(alreadyProcessed: Bool, xp: Int) {
        self.alreadyProcessed = alreadyProcessed
        self.xp = xp
    }
}
