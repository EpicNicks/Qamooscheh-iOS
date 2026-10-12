import Foundation
import QModel

public struct ExerciseReportReasonOption: Equatable, Sendable {
    public let value: ExerciseReportReason
    public let label: String

    public init(value: ExerciseReportReason, label: String) {
        self.value = value
        self.label = label
    }
}

public let exerciseReportReasons: [ExerciseReportReasonOption] = [
    ExerciseReportReasonOption(value: .audioWrong, label: "The audio sounded wrong"),
    ExerciseReportReasonOption(value: .answerShouldBeAccepted, label: "The answer should be accepted"),
    ExerciseReportReasonOption(value: .other, label: "Something else went wrong"),
]

/// Where the exercise stands when the learner opens the report.
public enum ExerciseReportStage: Equatable, Sendable {
    case unanswered
    case correct
    case incorrect
}

/// The reasons worth offering at that stage: an answer can only "should be accepted" once it's been marked wrong.
public func reportReasonsFor(_ stage: ExerciseReportStage) -> [ExerciseReportReasonOption] {
    if stage == .incorrect { return exerciseReportReasons }
    return exerciseReportReasons.filter { $0.value != .answerShouldBeAccepted }
}

/// An exercise's identity, the same one POST /v1/sessions/submit uses.
public struct ExerciseReportLocation: Equatable, Sendable {
    public var courseVersion: Int
    /// Nil for a theme lesson, which has no unit.
    public var unitKey: String?
    public var skillKey: String
    public var exerciseOrdinal: Int

    public init(courseVersion: Int, unitKey: String?, skillKey: String, exerciseOrdinal: Int) {
        self.courseVersion = courseVersion
        self.unitKey = unitKey
        self.skillKey = skillKey
        self.exerciseOrdinal = exerciseOrdinal
    }
}

/// Everything the Report control sends about the exercise under review.
public struct ExerciseReportContext: Equatable, Sendable {
    public var prompt: String
    public var exerciseTags: [String]
    /// What was graded, exactly as submitted; nil before an answer.
    public var submittedText: String?
    public var renderType: ExerciseType?
    public var location: ExerciseReportLocation?
    /// Version-root-relative paths of the takes this exercise actually played.
    public var audioFiles: [String]

    public init(prompt: String, exerciseTags: [String], submittedText: String? = nil, renderType: ExerciseType? = nil, location: ExerciseReportLocation? = nil, audioFiles: [String] = []) {
        self.prompt = prompt
        self.exerciseTags = exerciseTags
        self.submittedText = submittedText
        self.renderType = renderType
        self.location = location
        self.audioFiles = audioFiles
    }
}

/// The parts of a session's queue item a report can cite.
public struct ReportableItem: Equatable, Sendable {
    public var prompt: String
    public var tags: [String]
    public var renderType: ExerciseType
    public var unitKey: String?
    public var skillKey: String?
    public var ordinal: Int?

    public init(prompt: String, tags: [String], renderType: ExerciseType, unitKey: String? = nil, skillKey: String? = nil, ordinal: Int? = nil) {
        self.prompt = prompt
        self.tags = tags
        self.renderType = renderType
        self.unitKey = unitKey
        self.skillKey = skillKey
        self.ordinal = ordinal
    }
}

/// The report context for an item, answered or not. The location is included only when complete (the
/// backend rejects half a location), and played takes are de-duplicated in first-seen order.
public func reportContextFor(_ item: ReportableItem, submittedText: String?, courseVersion: Int?, playedPaths: [String?]) -> ExerciseReportContext {
    var location: ExerciseReportLocation? = nil
    if let version = courseVersion, let skillKey = item.skillKey, !skillKey.isEmpty, let ordinal = item.ordinal {
        location = ExerciseReportLocation(courseVersion: version, unitKey: item.unitKey, skillKey: skillKey, exerciseOrdinal: ordinal)
    }
    var seen = Set<String>()
    var audio: [String] = []
    for path in playedPaths {
        guard let path = path, !path.isEmpty, !seen.contains(path) else { continue }
        seen.insert(path)
        audio.append(path)
    }
    return ExerciseReportContext(prompt: item.prompt, exerciseTags: item.tags, submittedText: submittedText, renderType: item.renderType, location: location, audioFiles: audio)
}
