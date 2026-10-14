import Foundation
import QModel
import QDomain

// Pure logic behind the answer feedback panel, the session progress bar, the report form and the
// results screen (SwiftUI-free so `swift test` covers it). Ports Android feature/lesson
// LessonScreen.kt (FeedbackPanel, ProgressBar, Results) and ExerciseReport.kt.

/// How the panel presents a verdict: accepted-with-correction counts as correct, as on Android.
public enum FeedbackKind: Equatable, Sendable {
    case pending
    case correct
    case incorrect
}

public func feedbackKind(_ verdict: AnswerVerdict) -> FeedbackKind {
    switch verdict {
    case .pending: return .pending
    case .correct, .acceptedWithCorrection: return .correct
    case .incorrect: return .incorrect
    }
}

/// 0...1 for the session progress bar; 0 for an empty lesson.
public func sessionProgressFraction(completed: Int, total: Int) -> Double {
    if total <= 0 { return 0 }
    return min(1, max(0, Double(completed) / Double(total)))
}

/// The results score as a whole percent (rounds half away from zero, like Math.round for positives).
public func scorePercent(_ score: Double) -> Int {
    return Int((score * 100).rounded())
}

/// The accepted answer lines to reveal after a wrong answer, closest to the submission first. Word bank
/// and match answers are tokens of one selection, so they collapse to a single space-joined line.
public func revealedAnswerLines(_ exercise: ExerciseArtifact, submittedText: String) -> [String] {
    if exercise.type == .wordBank || exercise.type == .match {
        return [WordBankOrders.revealedTileOrder(exercise, submittedText: submittedText).joined(separator: " ")]
    }
    return closestAnswerFirst(submittedText, exercise.answer)
}

/// Match and speak answers are not typed, so the revealed answer also echoes what was submitted.
public func showsYourAnswer(_ renderType: ExerciseType) -> Bool {
    return renderType == .match || renderType == .speak
}

public func yourAnswerLine(_ submittedText: String) -> String {
    return "Your answer: " + (submittedText.isEmpty ? "(nothing submitted)" : submittedText)
}

public func alsoAcceptedTitle(count: Int) -> String {
    return "Also accepted (\(count))"
}

// MARK: Report

public let maxReportDetails = 4000
public let maxReportAnswer = 1000
public let maxReportAudioFiles = 10

/// Whether the form can be sent: a reason picked, and "Something else" explained.
public func canSendReport(reasons: Set<ExerciseReportReason>, details: String) -> Bool {
    if reasons.isEmpty { return false }
    if reasons.contains(.other) && details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
    return true
}

/// The report for the answer under review (Android exerciseReport): the exercise and its tags, the
/// reasons in the form's order, what was graded, how it was shown, its location (all or nothing,
/// needs a course version >= 1) and the recordings it played. Details go only with "Something else".
public func exerciseReportRequest(
    instance: ExerciseInstance,
    submittedText: String,
    reasons: Set<ExerciseReportReason>,
    details: String,
    courseVersion: Int?,
    audioFiles: [String]
) -> SubmitExerciseReportRequest {
    var located: Int? = nil
    if let version = courseVersion, version >= 1 { located = version }
    let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
    var detailText: String? = nil
    if reasons.contains(.other) && !trimmed.isEmpty { detailText = String(trimmed.prefix(maxReportDetails)) }
    var answerText: String? = nil
    if !submittedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        answerText = String(submittedText.prefix(maxReportAnswer))
    }
    var seen = Set<String>()
    var audio: [String] = []
    for file in audioFiles where !seen.contains(file) {
        seen.insert(file)
        audio.append(file)
    }
    let limitedAudio = Array(audio.prefix(maxReportAudioFiles))
    return SubmitExerciseReportRequest(
        exercisePrompt: instance.exercise.prompt,
        exerciseTags: instance.exercise.tags,
        reasons: exerciseReportReasons.map { $0.value }.filter { reasons.contains($0) },
        details: detailText,
        submittedAnswer: answerText,
        renderType: instance.renderType,
        courseVersion: located,
        unitKey: located == nil ? nil : instance.unitKey,
        skillKey: located == nil ? nil : instance.skillKey,
        exerciseOrdinal: located == nil ? nil : instance.ordinal,
        audioFiles: limitedAudio.isEmpty ? nil : limitedAudio
    )
}

public enum ReportStatus: Equatable, Sendable {
    case idle
    case sending
    case failed
    case sent
}

/// State of the report form. `submit` is injected (POST /v1/exercise-reports is wired by the app).
@MainActor
public final class ReportIssueModel: ObservableObject {
    @Published public var reasons: Set<ExerciseReportReason> = []
    @Published public var details: String = ""
    @Published public private(set) var status: ReportStatus = .idle

    private let build: (Set<ExerciseReportReason>, String) -> SubmitExerciseReportRequest
    private let submit: (SubmitExerciseReportRequest) async throws -> Void

    public init(
        build: @escaping (Set<ExerciseReportReason>, String) -> SubmitExerciseReportRequest,
        submit: @escaping (SubmitExerciseReportRequest) async throws -> Void
    ) {
        self.build = build
        self.submit = submit
    }

    public var canSend: Bool {
        return status != .sending && status != .sent && canSendReport(reasons: reasons, details: details)
    }

    public func toggle(_ reason: ExerciseReportReason) {
        if reasons.contains(reason) { reasons.remove(reason) } else { reasons.insert(reason) }
    }

    /// Sends the report; true when it landed.
    @discardableResult
    public func send() async -> Bool {
        if !canSend { return false }
        status = .sending
        do {
            try await submit(build(reasons, details))
            status = .sent
            return true
        } catch {
            status = .failed
            return false
        }
    }

    public var statusMessage: String? {
        switch status {
        case .failed: return "Couldn't send that \u{2014} try again?"
        case .sent: return "Thanks \u{2014} we'll look into it."
        case .idle, .sending: return nil
        }
    }
}

// MARK: Results

/// How a finished lesson ended (Android LessonEnd).
public enum LessonEndKind: Equatable, Sendable {
    case saving
    case saved(completed: Bool?, alreadyRecorded: Bool)
    case queued(completed: Bool?)
    case practice
    case rejected(partial: Bool, reason: String?)
}

/// The results screen's text and which parts show, from Android Results/EndScreen.
public struct LessonResultsCopy: Equatable, Sendable {
    public var title: String
    public var body: String
    public var showsScore: Bool
    /// 0...1 tick on the score bar, or nil.
    public var passMark: Double?
    public var passed: Bool
}

public func lessonResultsCopy(end: LessonEndKind, savedPractice: Bool = false) -> LessonResultsCopy {
    let passPercent = Int((lessonPassThreshold * 100).rounded())
    var completed: Bool? = nil
    var queued = false
    var already = false
    var practice = false
    switch end {
    case .saving:
        return LessonResultsCopy(title: "Saving your progress\u{2026}", body: "", showsScore: false, passMark: nil, passed: false)
    case .rejected(let partial, let reason):
        return LessonResultsCopy(
            title: partial ? "Only part of this lesson was saved" : "This lesson wasn't saved",
            body: reason ?? "The server didn't record this session, so it won't count toward your review schedule.",
            showsScore: true, passMark: nil, passed: false)
    case .saved(let c, let a):
        completed = c
        already = a
    case .queued(let c):
        completed = c
        queued = true
    case .practice:
        practice = true
    }
    if savedPractice {
        return LessonResultsCopy(title: "Saved words practised!", body: queued ? "Your answers will sync when you're back online." : "", showsScore: true, passMark: nil, passed: true)
    }
    if completed == false {
        return LessonResultsCopy(
            title: "Not passed yet",
            body: "You need \(passPercent)% on your first tries to pass this lesson and unlock the next one. Your answers still count toward your reviews \u{2014} take it again to pass.",
            showsScore: true, passMark: lessonPassThreshold, passed: false)
    }
    var notes: [String] = []
    if completed == true { notes.append("The next lesson is unlocked.") }
    if queued { notes.append("You're offline, so this lesson is saved on your phone. It'll sync when you're back online.") }
    if already { notes.append("Already recorded.") }
    if practice { notes.append("Practice round \u{2014} doesn't count toward your review schedule.") }
    return LessonResultsCopy(title: "Lesson complete!", body: notes.joined(separator: "\n"), showsScore: true, passMark: completed == nil ? nil : lessonPassThreshold, passed: true)
}

/// "5 day streak" / "1 day streak".
public func streakLine(days: Int) -> String {
    return days == 1 ? "1 day streak" : "\(days) day streak"
}

/// "30 of 50 XP today. Nice work." (Android GoalCelebration).
public func goalCelebrationLine(xpToday: Int, goalXp: Int) -> String {
    return "\(xpToday) of \(goalXp) XP today. Nice work."
}
