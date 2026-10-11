import Foundation


/// Skill and ordinals to test.
public struct CheckpointSkillPlan: Codable, Equatable, Sendable {
    public var unitKey: String
    public var skillKey: String
    public var exerciseOrdinals: [Int]

    public init(unitKey: String, skillKey: String, exerciseOrdinals: [Int]) {
        self.unitKey = unitKey
        self.skillKey = skillKey
        self.exerciseOrdinals = exerciseOrdinals
    }
}

/// A position skipped by a checkpoint.
public struct SkippedPosition: Codable, Equatable, Sendable {
    public var unitKey: String
    public var position: Int
    public var lessonKeys: [String]
    public var positionAlreadyCompleted: Bool

    public init(unitKey: String, position: Int, lessonKeys: [String], positionAlreadyCompleted: Bool) {
        self.unitKey = unitKey
        self.position = position
        self.lessonKeys = lessonKeys
        self.positionAlreadyCompleted = positionAlreadyCompleted
    }
}

/// GET /v1/checkpoint/{unit}/{skill}.
public struct CheckpointPlanResponse: Codable, Equatable, Sendable {
    public var courseVersion: Int
    public var targetUnitKey: String
    public var targetSkillKey: String
    public var skills: [CheckpointSkillPlan]
    public var skippedLessons: [SkippedPosition]
    public var skippedCount: Int
    public var alreadyCompletedCount: Int
    public var requiresTest: Bool

    public init(courseVersion: Int, targetUnitKey: String, targetSkillKey: String, skills: [CheckpointSkillPlan], skippedLessons: [SkippedPosition], skippedCount: Int, alreadyCompletedCount: Int, requiresTest: Bool) {
        self.courseVersion = courseVersion
        self.targetUnitKey = targetUnitKey
        self.targetSkillKey = targetSkillKey
        self.skills = skills
        self.skippedLessons = skippedLessons
        self.skippedCount = skippedCount
        self.alreadyCompletedCount = alreadyCompletedCount
        self.requiresTest = requiresTest
    }
}

/// Answers for one skill.
public struct CheckpointSkillAnswers: Codable, Equatable, Sendable {
    public var unitKey: String
    public var skillKey: String
    public var items: [SubmittedItem]

    public init(unitKey: String, skillKey: String, items: [SubmittedItem]) {
        self.unitKey = unitKey
        self.skillKey = skillKey
        self.items = items
    }
}

/// POST /v1/checkpoint/submit.
public struct SubmitCheckpointRequest: Codable, Equatable, Sendable {
    public var submissionId: String
    public var targetUnitKey: String
    public var targetSkillKey: String
    public var courseVersion: Int
    public var occurredAt: Date
    public var skills: [CheckpointSkillAnswers]

    public init(submissionId: String, targetUnitKey: String, targetSkillKey: String, courseVersion: Int, occurredAt: Date, skills: [CheckpointSkillAnswers]) {
        self.submissionId = submissionId
        self.targetUnitKey = targetUnitKey
        self.targetSkillKey = targetSkillKey
        self.courseVersion = courseVersion
        self.occurredAt = occurredAt
        self.skills = skills
    }
}

/// Checkpoint result.
public struct CheckpointSubmitResponse: Codable, Equatable, Sendable {
    public var passed: Bool
    public var score: Double
    public var cards: [CardState]
    public var skippedLessons: [SkippedPosition]
    public var skippedCount: Int
    public var alreadyCompletedCount: Int
    public var requiresTest: Bool
    public var applied: Bool
    public var xp: Int?

    public init(passed: Bool, score: Double, cards: [CardState], skippedLessons: [SkippedPosition], skippedCount: Int, alreadyCompletedCount: Int, requiresTest: Bool, applied: Bool, xp: Int? = nil) {
        self.passed = passed
        self.score = score
        self.cards = cards
        self.skippedLessons = skippedLessons
        self.skippedCount = skippedCount
        self.alreadyCompletedCount = alreadyCompletedCount
        self.requiresTest = requiresTest
        self.applied = applied
        self.xp = xp
    }
}
