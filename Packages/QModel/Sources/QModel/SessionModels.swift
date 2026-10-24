import Foundation


/// A skill, unitKey null for a theme lesson.
public struct SkillRef: Codable, Equatable, Sendable {
    public var unitKey: String?
    public var skillKey: String

    public init(unitKey: String? = nil, skillKey: String) {
        self.unitKey = unitKey
        self.skillKey = skillKey
    }
}

/// GET /v1/sessions/next and for-lesson.
public struct SessionPlanResponse: Codable, Equatable, Sendable {
    public var courseVersion: Int
    public var skills: [SkillRef]
    public var reviewTags: [String]
    public var newTags: [String]
    public var prefetchTags: [String]

    public init(courseVersion: Int, skills: [SkillRef], reviewTags: [String], newTags: [String], prefetchTags: [String]) {
        self.courseVersion = courseVersion
        self.skills = skills
        self.reviewTags = reviewTags
        self.newTags = newTags
        self.prefetchTags = prefetchTags
    }
}

/// One graded answer.
public struct SubmittedItem: Codable, Equatable, Sendable {
    public var exerciseOrdinal: Int
    public var lexemeTag: String
    public var exerciseType: ExerciseType
    public var scriptMode: ExerciseScriptMode
    public var submittedText: String
    public var usedHint: Bool
    public var latencyMs: Int?
    public var attempt: Int
    public var retypeText: String?

    public init(exerciseOrdinal: Int, lexemeTag: String, exerciseType: ExerciseType, scriptMode: ExerciseScriptMode, submittedText: String, usedHint: Bool, latencyMs: Int? = nil, attempt: Int, retypeText: String? = nil) {
        self.exerciseOrdinal = exerciseOrdinal
        self.lexemeTag = lexemeTag
        self.exerciseType = exerciseType
        self.scriptMode = scriptMode
        self.submittedText = submittedText
        self.usedHint = usedHint
        self.latencyMs = latencyMs
        self.attempt = attempt
        self.retypeText = retypeText
    }
}

/// One finished lesson, idempotent by submissionId.
public struct SubmittedSession: Codable, Equatable, Sendable {
    public var submissionId: String
    public var courseCode: String
    public var unitKey: String?
    public var skillKey: String
    public var courseVersion: Int
    public var occurredAt: Date
    public var completed: Bool
    public var items: [SubmittedItem]

    public init(submissionId: String, courseCode: String, unitKey: String? = nil, skillKey: String, courseVersion: Int, occurredAt: Date, completed: Bool, items: [SubmittedItem]) {
        self.submissionId = submissionId
        self.courseCode = courseCode
        self.unitKey = unitKey
        self.skillKey = skillKey
        self.courseVersion = courseVersion
        self.occurredAt = occurredAt
        self.completed = completed
        self.items = items
    }
}

/// POST /v1/sessions/submit.
public struct SubmitSessionsRequest: Codable, Equatable, Sendable {
    public var sessions: [SubmittedSession]

    public init(sessions: [SubmittedSession]) {
        self.sessions = sessions
    }
}

/// Server FSRS state for one lexeme.
public struct CardState: Codable, Equatable, Sendable {
    public var lexemeTag: String
    public var stability: Double
    public var difficulty: Double
    public var lastReviewedAt: Date?
    public var dueAt: Date?
    public var reviewCount: Int
    public var lapseCount: Int

    public init(lexemeTag: String, stability: Double, difficulty: Double, lastReviewedAt: Date? = nil, dueAt: Date? = nil, reviewCount: Int, lapseCount: Int) {
        self.lexemeTag = lexemeTag
        self.stability = stability
        self.difficulty = difficulty
        self.lastReviewedAt = lastReviewedAt
        self.dueAt = dueAt
        self.reviewCount = reviewCount
        self.lapseCount = lapseCount
    }
}

/// Per-session submit result.
public struct SubmittedSessionResponse: Codable, Equatable, Sendable {
    public var submissionId: String
    public var outcome: SessionOutcome
    public var rejectionReason: String?
    public var cards: [CardState]
    public var score: Double?
    public var lessonCompleted: Bool?
    public var xp: Int?
    /// Lesson key of a stowed lesson this pass cleared; the client drops it from its Stowage.
    public var stowCleared: String?

    public init(submissionId: String, outcome: SessionOutcome, rejectionReason: String? = nil, cards: [CardState], score: Double? = nil, lessonCompleted: Bool? = nil, xp: Int? = nil, stowCleared: String? = nil) {
        self.submissionId = submissionId
        self.outcome = outcome
        self.rejectionReason = rejectionReason
        self.cards = cards
        self.score = score
        self.lessonCompleted = lessonCompleted
        self.xp = xp
        self.stowCleared = stowCleared
    }
}

/// Submit response.
public struct SubmitSessionsResponse: Codable, Equatable, Sendable {
    public var sessions: [SubmittedSessionResponse]

    public init(sessions: [SubmittedSessionResponse]) {
        self.sessions = sessions
    }
}
