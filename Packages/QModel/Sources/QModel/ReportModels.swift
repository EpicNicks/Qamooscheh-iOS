import Foundation


/// POST /v1/exercise-reports (learner).
public struct SubmitExerciseReportRequest: Codable, Equatable, Sendable {
    public var exercisePrompt: String
    public var exerciseTags: [String]
    public var reasons: [ExerciseReportReason]
    public var details: String?
    public var submittedAnswer: String?
    public var renderType: ExerciseType?
    public var courseVersion: Int?
    public var unitKey: String?
    public var skillKey: String?
    public var exerciseOrdinal: Int?
    public var audioFiles: [String]?

    public init(exercisePrompt: String, exerciseTags: [String], reasons: [ExerciseReportReason], details: String? = nil, submittedAnswer: String? = nil, renderType: ExerciseType? = nil, courseVersion: Int? = nil, unitKey: String? = nil, skillKey: String? = nil, exerciseOrdinal: Int? = nil, audioFiles: [String]? = nil) {
        self.exercisePrompt = exercisePrompt
        self.exerciseTags = exerciseTags
        self.reasons = reasons
        self.details = details
        self.submittedAnswer = submittedAnswer
        self.renderType = renderType
        self.courseVersion = courseVersion
        self.unitKey = unitKey
        self.skillKey = skillKey
        self.exerciseOrdinal = exerciseOrdinal
        self.audioFiles = audioFiles
    }
}

/// Report accepted.
public struct SubmitExerciseReportResponse: Codable, Equatable, Sendable {
    public var id: Int
    public var createdAt: Date

    public init(id: Int, createdAt: Date) {
        self.id = id
        self.createdAt = createdAt
    }
}
