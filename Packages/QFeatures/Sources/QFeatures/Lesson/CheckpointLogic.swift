import Foundation
import QModel
import QDomain
import QData

// The decisions behind the checkpoint ("test out") flow, SwiftUI-free so swift test covers them. Port of
// the checkpoint half of Android LessonViewModel (planSession / submitCheckpoint) and LessonScreen
// (SkipSummary, CheckpointResults); where web CheckpointPage differs, Android wins.

/// What a checkpoint's plan says about the attempt, kept on the `LessonSetup` for the submit and the screens.
public struct CheckpointPlanInfo: Equatable, Sendable {
    public var courseVersion: Int
    public var targetUnitKey: String
    public var targetSkillKey: String
    public var skippedCount: Int
    public var alreadyCompletedCount: Int
    /// False when every skipped position is already satisfied: nothing is asked and the submit just moves the learner on.
    public var requiresTest: Bool

    public init(courseVersion: Int, targetUnitKey: String, targetSkillKey: String, skippedCount: Int, alreadyCompletedCount: Int, requiresTest: Bool) {
        self.courseVersion = courseVersion
        self.targetUnitKey = targetUnitKey
        self.targetSkillKey = targetSkillKey
        self.skippedCount = skippedCount
        self.alreadyCompletedCount = alreadyCompletedCount
        self.requiresTest = requiresTest
    }

    public init(plan: CheckpointPlanResponse) {
        self.init(
            courseVersion: plan.courseVersion, targetUnitKey: plan.targetUnitKey, targetSkillKey: plan.targetSkillKey,
            skippedCount: plan.skippedCount, alreadyCompletedCount: plan.alreadyCompletedCount, requiresTest: plan.requiresTest
        )
    }
}

/// The server's verdict on a submitted checkpoint (Android LessonEnd.Checkpoint).
public struct CheckpointOutcome: Equatable, Sendable {
    public var passed: Bool
    public var score: Double
    /// False when the learner was already past the target: a pass that moved nothing.
    public var applied: Bool

    public init(passed: Bool, score: Double, applied: Bool) {
        self.passed = passed
        self.score = score
        self.applied = applied
    }

    public init(_ response: CheckpointSubmitResponse) {
        self.init(passed: response.passed, score: response.score, applied: response.applied)
    }
}

/// The words on the checkpoint's last screens.
public struct CheckpointScreenCopy: Equatable, Sendable {
    public var title: String
    public var body: String
}

public enum CheckpointLogic {
    public static let submitLabel = "Submit checkpoint"
    public static let continueLabel = "Continue"
    public static let submittingLabel = "Submitting\u{2026}"
    public static let exitLabel = "Exit without submitting"
    public static let cancelLabel = "Cancel"
    public static let backToPath = "Back to path"
    public static let submitFailure = "Couldn't submit your checkpoint. Check your connection and try again."

    /// "Skipping 3 lessons - 1 already done via deep dive." Nil when nothing is skipped.
    public static func skipSummary(skippedCount: Int, alreadyCompletedCount: Int) -> String? {
        if skippedCount <= 0 { return nil }
        let lessons = skippedCount == 1 ? "lesson" : "lessons"
        let done = alreadyCompletedCount > 0 ? " \u{2014} \(alreadyCompletedCount) already done via deep dive" : ""
        return "Skipping \(skippedCount) \(lessons)\(done)."
    }

    /// The sampled exercises, in the skills' authored order: only the ordinals the plan named for each skill.
    public static func instances(plan: CheckpointPlanResponse, skills: [(ref: SkillRef, skill: SkillArtifact)], cards: [String: CardState]) -> [ExerciseInstance] {
        var wanted: [String: Set<Int>] = [:]
        for entry in plan.skills {
            wanted[planKey(unitKey: entry.unitKey, skillKey: entry.skillKey), default: []].formUnion(entry.exerciseOrdinals)
        }
        return buildInstances(skills: skills, cards: cards).filter { instance in
            wanted[planKey(unitKey: instance.unitKey ?? "", skillKey: instance.skillKey)]?.contains(instance.ordinal) ?? false
        }
    }

    /// Everything the lesson screen needs to play a checkpoint.
    public static func setup(courseCode: String, plan: CheckpointPlanResponse, skills: [(ref: SkillRef, skill: SkillArtifact)], cards: [String: CardState]) -> LessonSetup {
        let info = CheckpointPlanInfo(plan: plan)
        return LessonSetup(
            courseCode: courseCode,
            courseVersion: plan.courseVersion,
            instances: instances(plan: plan, skills: skills, cards: cards),
            checkpointSummary: skipSummary(skippedCount: info.skippedCount, alreadyCompletedCount: info.alreadyCompletedCount),
            checkpoint: info
        )
    }

    /// The single request that carries every answer, grouped by skill in the order first answered. An exercise that was
    /// not answered contributes nothing (the server scores what was answered); every tag of an exercise gets an item.
    public static func request(info: CheckpointPlanInfo, instances: [ExerciseInstance], answers: [String: String], submissionId: String, occurredAt: Date) -> SubmitCheckpointRequest {
        var order: [String] = []
        var units: [String: String] = [:]
        var skillKeys: [String: String] = [:]
        var items: [String: [SubmittedItem]] = [:]
        for instance in instances {
            guard let text = answers[instance.key] else { continue }
            let unitKey = instance.unitKey ?? ""
            let key = planKey(unitKey: unitKey, skillKey: instance.skillKey)
            if items[key] == nil {
                items[key] = []
                units[key] = unitKey
                skillKeys[key] = instance.skillKey
                order.append(key)
            }
            for tag in instance.exercise.tags {
                items[key, default: []].append(SubmittedItem(
                    exerciseOrdinal: instance.ordinal, lexemeTag: tag, exerciseType: instance.renderType,
                    scriptMode: instance.exercise.scriptMode, submittedText: text, usedHint: false, latencyMs: nil, attempt: 1
                ))
            }
        }
        var skills: [CheckpointSkillAnswers] = []
        for key in order {
            skills.append(CheckpointSkillAnswers(unitKey: units[key] ?? "", skillKey: skillKeys[key] ?? "", items: items[key] ?? []))
        }
        return SubmitCheckpointRequest(
            submissionId: submissionId, targetUnitKey: info.targetUnitKey, targetSkillKey: info.targetSkillKey,
            courseVersion: info.courseVersion, occurredAt: occurredAt, skills: skills
        )
    }

    /// "Ready to submit" after the last answer, or "No test needed" when the plan asked nothing.
    public static func readyCopy(noTest: Bool) -> CheckpointScreenCopy {
        if noTest {
            return CheckpointScreenCopy(
                title: "No test needed",
                body: "You've already completed everything this checkpoint would have asked \u{2014} jumping you forward."
            )
        }
        return CheckpointScreenCopy(title: "Ready to submit", body: "You've answered every question. Submit when ready.")
    }

    public static func primaryLabel(noTest: Bool, submitting: Bool) -> String {
        if submitting { return submittingLabel }
        return noTest ? continueLabel : submitLabel
    }

    public static func secondaryLabel(noTest: Bool) -> String {
        return noTest ? cancelLabel : exitLabel
    }

    public static func percent(_ score: Double) -> Int {
        return Int((score * 100).rounded())
    }

    public static func resultCopy(_ outcome: CheckpointOutcome) -> CheckpointScreenCopy {
        var lines = ["Score: \(percent(outcome.score))%"]
        if !outcome.applied {
            lines.append("This didn't move your position \u{2014} you'd already gotten there another way.")
        }
        return CheckpointScreenCopy(title: outcome.passed ? "Checkpoint passed!" : "Not quite there yet", body: lines.joined(separator: "\n"))
    }

    private static func planKey(unitKey: String, skillKey: String) -> String {
        return unitKey + "/" + skillKey
    }
}
