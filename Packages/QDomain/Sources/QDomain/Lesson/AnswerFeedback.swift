import Foundation
import QModel

// Top-level "was this answer right" dispatcher for instant in-lesson feedback
// (never authoritative: the server re-grades every submission). The verdict
// and XP come from the published offline grader; this builds the request, maps
// the response, and words the note saying where an accepted-but-imperfect
// answer went wrong. Without a grader, a plain exact match stands in.
// Port of web domain/answerFeedback.ts.

public enum AnswerVerdict: String, Equatable, Sendable {
    case correct
    case acceptedWithCorrection = "accepted_with_correction"
    case incorrect
}

/// Where an accepted answer's separators differ from `matchedAnswer`, the accepted answer the grader matched.
public struct SeparatorMarks: Equatable, Sendable {
    public var matchedAnswer: String
    public var edits: [SeparatorEdit]

    public init(matchedAnswer: String, edits: [SeparatorEdit]) {
        self.matchedAnswer = matchedAnswer
        self.edits = edits
    }
}

public struct AnswerFeedback: Equatable, Sendable {
    public var verdict: AnswerVerdict
    /// A short explanation when the answer was accepted but imperfect; nil otherwise.
    public var note: String?
    /// The XP this answer earns, as the grader prices it. 0 without a grader.
    public var xp: Int
    /// The grader's separator edits for an accepted answer whose half-spaces or spaces were off.
    public var separators: SeparatorMarks?

    public init(verdict: AnswerVerdict, note: String?, xp: Int, separators: SeparatorMarks?) {
        self.verdict = verdict
        self.note = note
        self.xp = xp
        self.separators = separators
    }
}

/// What the answer's XP depends on besides its verdict. nil fields: a first attempt without a hint.
public struct AnswerContext: Equatable, Sendable {
    /// 1-indexed.
    public var attempt: Int?
    public var usedHint: Bool?
    public var retype: Bool?
    public var retypeNumber: Int?

    public init(attempt: Int? = nil, usedHint: Bool? = nil, retype: Bool? = nil, retypeNumber: Int? = nil) {
        self.attempt = attempt
        self.usedHint = usedHint
        self.retype = retype
        self.retypeNumber = retypeNumber
    }
}

/// The parts of an exercise the check reads.
public struct GradedExercise: Equatable, Sendable {
    public var type: ExerciseType
    public var scriptMode: ExerciseScriptMode
    public var answer: [String]
    public var alternativeAnswers: [[String]]?

    public init(type: ExerciseType, scriptMode: ExerciseScriptMode, answer: [String], alternativeAnswers: [[String]]? = nil) {
        self.type = type
        self.scriptMode = scriptMode
        self.answer = answer
        self.alternativeAnswers = alternativeAnswers
    }

    public init(_ exercise: ExerciseArtifact) {
        self.init(type: exercise.type, scriptMode: exercise.scriptMode, answer: exercise.answer, alternativeAnswers: exercise.alternativeAnswers)
    }
}

/// UTF-16 code unit slice [from, to), clamped like JS String.prototype.slice for non-negative offsets.
func utf16Slice(_ s: String, _ from: Int, _ to: Int) -> String {
    let units = Array(s.utf16)
    let lo = max(0, min(from, units.count))
    let hi = max(lo, min(to, units.count))
    return String(decoding: units[lo..<hi], as: UTF16.self)
}

/// The grader's names for the reasons it forgave an answer, in the order notes list them. The Japanese grader's own reasons have no wording here and add no note.
private let reasonLabels: [(reason: String, label: String)] = [
    ("CodepointSubstitution", "used the Arabic form of a letter instead of the Persian one"),
    ("ZwnjOrSpacing", "the half-space (ZWNJ) was off"),
    ("LatinizationVariance", "romanization spelling"),
    ("EditDistanceTypo", "a small typo"),
]

/// A word in an English sentence, isolated so a Persian one keeps its place in the line.
private func isolate(_ word: String) -> String {
    return "\u{2068}\(word)\u{2069}"
}

/// Which words a forgiven typo was in, by lining `submitted` up word for word with the answer it was matched to. When the words don't line up, the whole answer stands in.
private func describeTypo(_ submitted: String, _ matchedAnswer: String, romanized: Bool) -> String {
    func words(_ text: String) -> [String] {
        let base = romanized ? AnswerDiff.normalizeCase(text) : PersianNormalize.normalizeStrict(text)
        return base.components(separatedBy: " ")
    }
    func fold(_ text: String) -> String {
        return romanized ? AnswerDiff.foldLatinVariance(text) : PersianNormalize.foldCodepoints(text)
    }
    let typedWords = words(submitted)
    let acceptedWords = words(matchedAnswer)
    if typedWords.count != acceptedWords.count { return "it's \(isolate(acceptedWords.joined(separator: " ")))" }
    var parts: [String] = []
    for i in 0..<acceptedWords.count where Array(fold(acceptedWords[i]).utf8) != Array(fold(typedWords[i]).utf8) {
        parts.append("\(isolate(acceptedWords[i])), not \(isolate(typedWords[i]))")
    }
    return parts.joined(separator: "; ")
}

private func describeReasons(_ response: GraderResponse, submitted: String, romanized: Bool, spacingMatters: Bool) -> String? {
    var labels: [String] = []
    for entry in reasonLabels where response.reasons.contains(entry.reason) {
        var detail = ""
        if entry.reason == "EditDistanceTypo", let matched = response.matchedAnswer, !matched.isEmpty {
            detail = describeTypo(submitted, matched, romanized: romanized)
        } else if entry.reason == "ZwnjOrSpacing", spacingMatters, let matched = response.matchedAnswer, !matched.isEmpty,
                  let edits = response.separatorEdits, !edits.isEmpty {
            detail = "needs " + edits.map { describeSeparatorEdit(matched, $0) }.joined(separator: "; ")
        }
        labels.append(detail.isEmpty ? entry.label : "\(entry.label): \(detail)")
    }
    return labels.isEmpty ? nil : "Close \u{2014} \(labels.joined(separator: ", "))."
}

private func separatorPhrase(_ kind: SeparatorEditKind) -> String {
    switch kind {
    case .missingZwnj: return "a half-space"
    case .missingSpace: return "a space"
    case .extraZwnj: return "no half-space"
    case .extraSpace: return "no space"
    case .spaceForZwnj: return "a half-space, not a space,"
    case .zwnjForSpace: return "a space, not a half-space,"
    }
}

private func isWordScalar(_ s: Unicode.Scalar) -> Bool {
    return !isJSWhitespace(s) && s != "\u{200C}"
}

/// One separator edit in words, naming the letters before it in `matchedAnswer`, or the ones after when it sits at the start of a word.
private func describeSeparatorEdit(_ matchedAnswer: String, _ edit: SeparatorEdit) -> String {
    let phrase = separatorPhrase(edit.kind)
    let beforeScalars = Array(PersianNormalize.stripReadingAids(utf16Slice(matchedAnswer, 0, edit.index)).unicodeScalars)
    var start = beforeScalars.count
    while start > 0 && isWordScalar(beforeScalars[start - 1]) { start -= 1 }
    if start < beforeScalars.count {
        return "\(phrase) after \(isolate(scalarString(Array(beforeScalars[start...]))))"
    }
    let afterScalars = Array(PersianNormalize.stripReadingAids(utf16Slice(matchedAnswer, edit.index + edit.length, Int.max)).unicodeScalars)
    var end = 0
    while end < afterScalars.count && isWordScalar(afterScalars[end]) { end += 1 }
    if end > 0 {
        return "\(phrase) before \(isolate(scalarString(Array(afterScalars[0..<end]))))"
    }
    return phrase
}

private func verdictOf(_ response: GraderResponse) -> AnswerVerdict {
    if response.verdict == "Correct" { return .correct }
    if response.verdict == "AcceptedWithCorrection" { return .acceptedWithCorrection }
    return .incorrect
}

private func graderRequest(_ exercise: GradedExercise, _ submittedText: String, _ context: AnswerContext) -> GraderRequest {
    let selection = exercise.type == .wordBank || exercise.type == .match
    let typeName: String
    switch exercise.type {
    case .wordBank: typeName = "WordBank"
    case .typeIn: typeName = "TypeIn"
    case .match: typeName = "Match"
    case .speak: typeName = "Speak"
    }
    return GraderRequest(
        exerciseType: typeName,
        scriptMode: exercise.scriptMode == .romanized ? "Romanized" : "Native",
        submitted: submittedText,
        // A selection's `answer` is the ordered tiles of ONE correct selection, which the grader joins itself.
        acceptedAnswers: exercise.answer,
        alternativeAnswers: selection ? exercise.alternativeAnswers : nil,
        attempt: context.attempt,
        usedHint: context.usedHint,
        retype: context.retype,
        retypeNumber: context.retypeNumber
    )
}

/// The feedback for `submittedText` against `exercise`: the verdict and XP from `grader`, plus the note. Without a grader, or when it can't interpret the request, a plain exact-match check stands in and earns no XP.
public func checkAnswer(
    _ grader: Grader?,
    courseCode: String?,
    exercise: GradedExercise,
    submittedText: String,
    context: AnswerContext = AnswerContext()
) -> AnswerFeedback {
    let selection = exercise.type == .wordBank || exercise.type == .match
    let response = grader?.gradeEnvelope(graderRequest(exercise, submittedText, context))

    guard let response = response, response.error == nil else {
        // Selection-based `answer`s are tiles, so the plain check needs them joined.
        let accepted: [String] = selection
            ? ([exercise.answer] + (exercise.alternativeAnswers ?? [])).map { $0.joined(separator: " ") }
            : exercise.answer
        let verdict: AnswerVerdict = TextMatch.looksCorrect(submittedText, accepted) ? .correct : .incorrect
        return AnswerFeedback(verdict: verdict, note: nil, xp: 0, separators: nil)
    }

    let verdict = verdictOf(response)
    let xp = response.xp ?? 0
    // Selection-based: a typo is structurally impossible either way, and there is nothing typed to describe.
    if selection { return AnswerFeedback(verdict: verdict, note: nil, xp: xp, separators: nil) }
    // A separator difference alone is accepted with correction, so a wrong answer is wrong for more than its spacing.
    if verdict == .incorrect { return AnswerFeedback(verdict: verdict, note: nil, xp: xp, separators: nil) }
    let romanized = exercise.scriptMode == .romanized
    let spacingMatters = Languages.isPersian(courseCode) && !romanized
    let edits = response.separatorEdits ?? []
    var separators: SeparatorMarks?
    if spacingMatters, let matched = response.matchedAnswer, !matched.isEmpty, !edits.isEmpty {
        separators = SeparatorMarks(matchedAnswer: matched, edits: edits)
    }
    return AnswerFeedback(
        verdict: verdict,
        note: describeReasons(response, submitted: submittedText, romanized: romanized, spacingMatters: spacingMatters),
        xp: xp,
        separators: separators
    )
}

/// `answers` with whichever is closest to what the learner submitted first, so a revealed answer is the one they were nearest to. Ties, and an empty submission, keep the authored order.
public func closestAnswerFirst(_ submitted: String, _ answers: [String]) -> [String] {
    func fold(_ text: String) -> String {
        return PersianNormalize.foldCodepoints(PersianNormalize.normalizeStrict(text)).lowercased()
    }
    let typed = fold(submitted)
    if typed.isEmpty || answers.count < 2 { return answers }
    let ranked = answers.enumerated().map { (i, answer) in (answer: answer, i: i, distance: AnswerDiff.levenshteinDistance(typed, fold(answer))) }
    return ranked
        .sorted { $0.distance != $1.distance ? $0.distance < $1.distance : $0.i < $1.i }
        .map { $0.answer }
}
