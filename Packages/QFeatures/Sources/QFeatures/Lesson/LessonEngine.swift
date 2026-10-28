import Foundation
import QModel
import QDomain

// The lesson state machine, minus the I/O (SwiftUI-free). Port of Android
// core/domain/lesson/LessonEngine.kt (which ports web useLessonEngine.ts): an
// immutable, Codable LessonState of queued exercise instances plus what has
// been answered. Answering returns the next state. Fetching the plan, the
// grader runtime and the submit are the caller's job; grading goes through the
// injected QDomain `Grader` (nil or erroring = the answer is "pending", checked
// when you sync).

/// A wrong answer comes back this many exercises later...
public let retryDepth = 3

/// ...at most this many attempts in all.
public let maxAttempts = 2

/// One showing of one exercise. `attempt` counts previous tries, so 0 the first time. `plays` counts the finished plays of a listening exercise's recording in this showing; it lives here so a saved draft keeps it across the app being killed.
public struct ExerciseInstance: Codable, Equatable, Sendable {
    public var key: String
    public var unitKey: String?
    public var skillKey: String
    public var ordinal: Int
    public var exercise: ExerciseArtifact
    public var renderType: ExerciseType
    public var attempt: Int
    public var plays: Int

    public init(key: String, unitKey: String?, skillKey: String, ordinal: Int, exercise: ExerciseArtifact, renderType: ExerciseType, attempt: Int = 0, plays: Int = 0) {
        self.key = key
        self.unitKey = unitKey
        self.skillKey = skillKey
        self.ordinal = ordinal
        self.exercise = exercise
        self.renderType = renderType
        self.attempt = attempt
        self.plays = plays
    }

    /// Drafts saved before listening exercises existed have no `plays`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.key = try c.decode(String.self, forKey: .key)
        self.unitKey = try c.decodeIfPresent(String.self, forKey: .unitKey)
        self.skillKey = try c.decode(String.self, forKey: .skillKey)
        self.ordinal = try c.decode(Int.self, forKey: .ordinal)
        self.exercise = try c.decode(ExerciseArtifact.self, forKey: .exercise)
        self.renderType = try c.decode(ExerciseType.self, forKey: .renderType)
        self.attempt = try c.decode(Int.self, forKey: .attempt)
        self.plays = try c.decodeIfPresent(Int.self, forKey: .plays) ?? 0
    }

    public var listening: Bool { return renderType == .listenType }
    public var playsLeft: Int { return Listening.playsLeft(plays) }
}

public struct RecordedItem: Codable, Equatable, Sendable {
    public var unitKey: String?
    public var skillKey: String
    public var item: SubmittedItem

    public init(unitKey: String?, skillKey: String, item: SubmittedItem) {
        self.unitKey = unitKey
        self.skillKey = skillKey
        self.item = item
    }
}

/// The result of answering the current exercise.
public struct AnswerOutcome: Equatable, Sendable {
    public var state: LessonState
    public var feedback: AnswerFeedback
    public var attempt: Int
    public var requeued: Bool
    public var xpGained: Int
    /// A listening answer that extra plays, not a retry, priced down: the line "You played it more than once" explains it.
    public var extraPlays: Bool = false
}

/// Cosmetic, client-only XP for the pop animation and the recap; never sent anywhere. `attempt` is 1-based. (Android xpForAnswer.)
public func xpForAnswer(_ verdict: AnswerVerdict, attempt: Int, usedHint: Bool) -> Int {
    if verdict == .incorrect || verdict == .pending { return 0 }
    let base: Int
    if verdict == .correct && attempt == 1 {
        base = 10
    } else if verdict == .correct {
        base = 5
    } else {
        base = 7
    }
    // Round half up, like Math.round(base / 2.0).
    return usedHint ? (base + 1) / 2 : base
}

public struct LessonState: Codable, Equatable, Sendable {
    public var queue: [ExerciseInstance]
    public var totalCount: Int
    public var items: [RecordedItem]
    public var firstTryCorrect: Int
    /// Correct = 1, accepted with correction = 0.5, per first attempt (the server's ExerciseScore).
    public var firstTryPoints: Double
    /// Credit earned on retries (Backend#86): a wrong first try that is later answered right is worth the verdict weight halved per attempt before it. A retry only follows a wrong answer, so each exercise adds at most once. nil in states saved before retry credit.
    public var retryPoints: Double?
    /// Every checked attempt, for the pure `lessonScore`. nil in states saved before this field existed (the totals above are used then).
    public var scoredAttempts: [LessonAttempt]?
    /// Answers (first tries or retries) the device couldn't check: only the server can say whether they passed.
    public var uncheckedFirstTries: Int
    public var xp: Int
    /// Local practice: nothing is submitted, so nothing counts toward progress.
    public var practice: Bool
    /// Submission ids minted for this lesson, by session group (see `sessionGroupKeys`). Stamped once by `LessonEngine.completion` so repeating it, or completing a restored finished state, yields the same ids and the queue dedupes.
    public var submissionIds: [String: String]?
    /// Practice as the session was opened (Android's planned-session flag), kept so an engine rebuilt after process death mid "practice again" doesn't mistake the round's practice for the session's. nil in states saved before this field existed.
    public var sessionPractice: Bool?

    public init(queue: [ExerciseInstance], totalCount: Int? = nil, items: [RecordedItem] = [], firstTryCorrect: Int = 0, firstTryPoints: Double = 0, uncheckedFirstTries: Int = 0, xp: Int = 0, practice: Bool = false) {
        self.queue = queue
        self.totalCount = totalCount ?? queue.count
        self.items = items
        self.firstTryCorrect = firstTryCorrect
        self.firstTryPoints = firstTryPoints
        self.uncheckedFirstTries = uncheckedFirstTries
        self.scoredAttempts = []
        self.xp = xp
        self.practice = practice
    }

    public var current: ExerciseInstance? { queue.first }
    public var finished: Bool { queue.isEmpty }
    public var completedCount: Int { totalCount - queue.count }
    /// The server's lesson score: first-try points plus retry credit, over the exercises in the lesson.
    public var score: Double {
        if let attempts = scoredAttempts { return lessonScore(attempts) }
        return totalCount == 0 ? 0 : (firstTryPoints + (retryPoints ?? 0)) / Double(totalCount)
    }

    /// One more finished play of the current listening exercise, if it is `key` and has plays left; otherwise the same state.
    public func withPlay(key: String) -> LessonState {
        guard let current = current, current.key == key, current.listening, current.playsLeft > 0 else { return self }
        var next = self
        next.queue[0].plays = current.plays + 1
        return next
    }

    /// Records an answer to the current exercise. A wrong answer is recorded too (the server's FSRS needs it) and, unless it was the last attempt, comes back `retryDepth` exercises later. An unchecked (pending) answer moves on without a retry: the server decides. Returns nil when the queue is empty.
    public func answer(_ feedback: AnswerFeedback, submittedText: String, usedHint: Bool = false, latencyMs: Int? = nil) -> AnswerOutcome? {
        guard let current = current else { return nil }
        let attempt = current.attempt + 1
        let firstTry = current.attempt == 0
        let pending = feedback.verdict == .pending
        let wrong = feedback.verdict == .incorrect

        // A listening answer is priced as if the plays used were the attempt; answering unheard counts as one play.
        let playsUsed: Int? = current.listening ? Listening.playsUsed(current.plays) : nil
        let recorded = current.exercise.tags.map { tag in
            RecordedItem(
                unitKey: current.unitKey,
                skillKey: current.skillKey,
                item: SubmittedItem(exerciseOrdinal: current.ordinal, lexemeTag: tag, exerciseType: current.renderType, scriptMode: current.exercise.scriptMode, submittedText: submittedText, usedHint: usedHint, latencyMs: latencyMs, attempt: attempt, playsUsed: playsUsed)
            )
        }
        var rest = Array(queue.dropFirst())
        let requeued = wrong && attempt < maxAttempts
        if requeued {
            var again = current
            again.attempt = attempt
            // A retry is a fresh listen: three plays again, priced from its own attempt.
            again.plays = 0
            rest.insert(again, at: min(retryDepth, rest.count))
        }
        let priced = current.listening ? Listening.pricedAttempt(attempt: attempt, plays: current.plays) : attempt
        let xpGained = pending ? 0 : xpForAnswer(feedback.verdict, attempt: priced, usedHint: usedHint)
        let extraPlays = current.listening && !pending && !wrong && Listening.playedMoreThanOnce(attempt: attempt, plays: current.plays)

        var next = self
        next.queue = rest
        next.items = items + recorded
        if firstTry && !pending && !wrong { next.firstTryCorrect += 1 }
        if firstTry && !pending { next.firstTryPoints += verdictWeight(feedback.verdict) }
        if pending { next.uncheckedFirstTries += 1 }
        if !pending, let attempts = scoredAttempts { next.scoredAttempts = attempts + [LessonAttempt(exerciseKey: current.key, attempt: attempt, verdict: feedback.verdict)] }
        if !firstTry && !pending && !wrong { next.retryPoints = (retryPoints ?? 0) + lessonAttemptCredit(feedback.verdict, attempt: attempt) }
        next.xp = xp + xpGained
        return AnswerOutcome(state: next, feedback: feedback, attempt: attempt, requeued: requeued, xpGained: xpGained, extraPlays: extraPlays)
    }

    /// The same lesson again from the top: a retake, or practice mode (no credit).
    public func restart(_ instances: [ExerciseInstance], practice: Bool) -> LessonState {
        LessonState(queue: instances, practice: practice)
    }

    private static func groupKey(_ recorded: RecordedItem) -> String {
        (recorded.unitKey ?? "<none>") + "|" + recorded.skillKey
    }

    /// The session groups (unit and skill) in the order first played; one session each.
    public func sessionGroupKeys() -> [String] {
        var order: [String] = []
        var seen = Set<String>()
        for recorded in items {
            let id = LessonState.groupKey(recorded)
            if seen.insert(id).inserted { order.append(id) }
        }
        return order
    }

    /// One session per skill played, in the order first played, all stamped with when the lesson finished (web finishLesson). Each carries its own submissionId, so the result goes straight to `OfflineQueue.enqueue`. Empty in practice mode.
    public func buildSessions(courseCode: String, courseVersion: Int, occurredAt: Date, newId: () -> String) -> [SubmittedSession] {
        if practice { return [] }
        let order = sessionGroupKeys()
        var groups: [String: [RecordedItem]] = [:]
        for recorded in items { groups[LessonState.groupKey(recorded), default: []].append(recorded) }
        var sessions: [SubmittedSession] = []
        for id in order {
            let recorded = groups[id] ?? []
            guard let first = recorded.first else { continue }
            sessions.append(SubmittedSession(
                submissionId: newId(),
                courseCode: courseCode,
                unitKey: first.unitKey,
                skillKey: first.skillKey,
                courseVersion: courseVersion,
                occurredAt: occurredAt,
                completed: true,
                items: recorded.map { $0.item }
            ))
        }
        return sessions
    }

    /// Whether this lesson completes its skill, by the server's rule: every exercise of the skill answered and a score (retries credited, halved per attempt) of at least 75%. nil when answers went unchecked (only the server can say) or in practice.
    public func localLessonCompleted(exerciseCountBySkill: [String: Int]) -> Bool? {
        if practice || uncheckedFirstTries > 0 { return nil }
        // Counts are keyed "unit/skill" when the loader knows the unit (saved practice spans units), else by skill key.
        var ordinals: [String: (skillKey: String, seen: Set<Int>)] = [:]
        for recorded in items {
            var id = recorded.skillKey
            if let unit = recorded.unitKey { id = unit + "/" + recorded.skillKey }
            var entry = ordinals[id] ?? (skillKey: recorded.skillKey, seen: [])
            entry.seen.insert(recorded.item.exerciseOrdinal)
            ordinals[id] = entry
        }
        var covered = false
        for (id, entry) in ordinals {
            let count = exerciseCountBySkill[id] ?? exerciseCountBySkill[entry.skillKey] ?? 0
            if count > 0 && entry.seen.count >= count { covered = true }
        }
        return covered && score >= lessonPassThreshold
    }
}

/// The exercise instances for a lesson, in authored order (web buildInstances): each composite exercise resolved to a word bank or typing from the learner's card state for its primary tag. `dueTags` keeps only exercises practising a due lexeme.
public func buildInstances(skills: [(ref: SkillRef, skill: SkillArtifact)], cards: [String: CardState], dueTags: Set<String>? = nil) -> [ExerciseInstance] {
    var result: [ExerciseInstance] = []
    for entry in skills {
        for (ordinal, exercise) in entry.skill.exercises.enumerated() {
            if let due = dueTags, !exercise.tags.contains(where: { due.contains($0) }) { continue }
            var card: CardState?
            if let tag = exercise.tags.first { card = cards[tag] }
            result.append(ExerciseInstance(
                key: "\(entry.ref.unitKey ?? "_")/\(entry.ref.skillKey)/\(ordinal)",
                unitKey: entry.ref.unitKey,
                skillKey: entry.ref.skillKey,
                ordinal: ordinal,
                exercise: exercise,
                renderType: resolveExerciseType(exercise, cardState: card)
            ))
        }
    }
    return result
}

public struct LessonCompletion: Equatable, Sendable {
    public var sessions: [SubmittedSession]
    public var locallyCompleted: Bool?
    public var xp: Int
    public var score: Double
}

/// Drives one lesson: holds the state and the injected grader. A nil grader makes every answer pending, "checked when you sync"; so does `gradingOnDevice == false` and a grader response with an `error`.
public struct LessonEngine {
    public private(set) var state: LessonState
    public let courseCode: String?
    private let grader: Grader?
    /// Practice as the session was opened (Android's ViewModel-level flag): a restart may turn practice on, but only this decides it stays on.
    private let sessionPractice: Bool
    /// False once the device can't grade: every answer is pending.
    public var gradingOnDevice: Bool

    /// `sessionPractice` is the flag of the planned session; when nil it comes from the saved state, else from `state.practice` (a fresh lesson).
    public init(state: LessonState, courseCode: String?, grader: Grader?, gradingOnDevice: Bool = true, sessionPractice: Bool? = nil) {
        let session = sessionPractice ?? state.sessionPractice ?? state.practice
        var state = state
        state.sessionPractice = session
        self.state = state
        self.sessionPractice = session
        self.courseCode = courseCode
        self.grader = grader
        self.gradingOnDevice = gradingOnDevice
    }

    /// Feedback for `text` against `instance`, without recording it.
    public func grade(_ instance: ExerciseInstance, text: String) -> AnswerFeedback {
        if !gradingOnDevice {
            return AnswerFeedback(verdict: .pending, note: nil, xp: 0, separators: nil)
        }
        return checkAnswer(grader, courseCode: courseCode, exercise: GradedExercise(instance.exercise), submittedText: text)
    }

    /// Grades and records an answer to the current exercise; nil when the lesson is finished.
    @discardableResult
    public mutating func submit(_ text: String, usedHint: Bool = false, latencyMs: Int? = nil) -> AnswerOutcome? {
        guard let instance = state.current else { return nil }
        let feedback = grade(instance, text: text)
        guard let outcome = state.answer(feedback, submittedText: text, usedHint: usedHint, latencyMs: latencyMs) else { return nil }
        state = outcome.state
        return outcome
    }

    /// One more finished play of the current listening exercise, if `key` is still the one on screen.
    public mutating func recordPlay(key: String) {
        state = state.withPlay(key: key)
    }

    /// A story or saved-words round is read once through: a missed exercise is not asked again.
    public mutating func dropFromQueue(key: String) {
        state.queue.removeAll { $0.key == key }
    }

    /// A checkpoint takes its answers without marking them: the current exercise leaves the queue, nothing is graded or recorded.
    public mutating func advancePastCurrent() {
        if !state.queue.isEmpty { state.queue.removeFirst() }
    }

    public mutating func restart(_ instances: [ExerciseInstance], practice: Bool) {
        var next = state.restart(instances, practice: practice || sessionPractice)
        next.sessionPractice = sessionPractice
        state = next
    }

    /// The lesson's end: sessions for `OfflineQueue.enqueue` (empty for practice) and the local completion guess. nil until the lesson is finished. Submission ids are minted once and kept in the state, so calling again returns the same ids.
    public mutating func completion(courseCode: String, courseVersion: Int, occurredAt: Date, exerciseCountBySkill: [String: Int], newId: () -> String = { UUID().uuidString }) -> LessonCompletion? {
        if !state.finished { return nil }
        var ids = state.submissionIds ?? [:]
        let keys = state.sessionGroupKeys()
        for key in keys where ids[key] == nil { ids[key] = newId() }
        state.submissionIds = ids
        var next = 0
        let sessions = state.buildSessions(courseCode: courseCode, courseVersion: courseVersion, occurredAt: occurredAt, newId: {
            defer { next += 1 }
            return ids[keys[next]] ?? ""
        })
        return LessonCompletion(
            sessions: sessions,
            locallyCompleted: state.localLessonCompleted(exerciseCountBySkill: exerciseCountBySkill),
            xp: state.xp,
            score: state.score
        )
    }
}
