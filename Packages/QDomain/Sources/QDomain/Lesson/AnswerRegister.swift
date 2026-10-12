import Foundation
import QModel

// The register an accepted answer is in, read off the lexemes its words are.
// The published data has no per-answer register marking, so an answer is only
// as informal or formal as the words in it. Words are looked up by surface in
// the course's hint map. Port of web domain/answerRegister.ts.

/// Alternatives listed beside the answer given.
private let maxAlternatives = 2

public struct AnswerRegisterAlternative: Equatable, Sendable {
    public var answer: String
    public var label: String

    public init(answer: String, label: String) {
        self.answer = answer
        self.label = label
    }
}

public struct AnswerRegisterNote: Equatable, Sendable {
    /// The given answer's register label ("informal"/"formal"); nil when its words aren't specific to one.
    public var label: String?
    /// Other accepted answers in a different, labelled register, closest to the given one first.
    public var alternatives: [AnswerRegisterAlternative]

    public init(label: String?, alternatives: [AnswerRegisterAlternative]) {
        self.label = label
        self.alternatives = alternatives
    }
}

private func isPunctOrSymbol(_ s: Unicode.Scalar) -> Bool {
    switch s.properties.generalCategory {
    case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
         .initialPunctuation, .finalPunctuation, .otherPunctuation,
         .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
        return true
    default:
        return false
    }
}

private func trimPunctuation(_ word: String) -> String {
    let scalars = Array(word.unicodeScalars)
    var start = 0
    var end = scalars.count
    while end > start, isPunctOrSymbol(scalars[end - 1]) { end -= 1 }
    while start < end, isPunctOrSymbol(scalars[start]) { start += 1 }
    var out = String.UnicodeScalarView()
    out.append(contentsOf: scalars[start..<end])
    return String(out)
}

/// Spoken if any word is spoken, otherwise the most marked register present (written); nil when no word is specific to one. A "both" word is neutral.
public func answerRegister(_ answer: String, hintMap: [String: WordHint]) -> Register? {
    var register: Register?
    for word in answer.components(separatedBy: .whitespacesAndNewlines) {
        let hint = hintMap[trimPunctuation(word)]
        if hint?.register == .spoken { return .spoken }
        if hint?.register == .written { register = .written }
    }
    return register
}

/// The register of the answer the learner gave (the accepted answer nearest their submission) and of the other accepted answers in another one. nil when there's nothing to say.
public func describeAnswerRegister(_ exercise: GradedExercise, submittedText: String, hintMap: [String: WordHint]) -> AnswerRegisterNote? {
    let tokenized = exercise.type == .wordBank || exercise.type == .match
    let answers: [String] = tokenized
        ? ([exercise.answer] + (exercise.alternativeAnswers ?? [])).map { $0.joined(separator: " ") }
        : exercise.answer
    let ranked = closestAnswerFirst(submittedText, answers)
    guard let given = ranked.first else { return nil }

    let label = registerLabel(answerRegister(given, hintMap: hintMap))
    var alternatives: [AnswerRegisterAlternative] = []
    for answer in ranked.dropFirst() {
        if let other = registerLabel(answerRegister(answer, hintMap: hintMap)), other != label, alternatives.count < maxAlternatives {
            alternatives.append(AnswerRegisterAlternative(answer: answer, label: other))
        }
    }
    if label != nil || !alternatives.isEmpty { return AnswerRegisterNote(label: label, alternatives: alternatives) }
    return nil
}
