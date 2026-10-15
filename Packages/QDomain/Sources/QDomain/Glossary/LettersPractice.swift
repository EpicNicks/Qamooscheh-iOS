// Letters practice (spec 9.8): a short multiple-choice quiz over the abjad
// glossary's letters. Native only. It is local: nothing is submitted and
// nothing earns FSRS credit. Port of Android LettersPractice.kt.
//
// Everything here is pure and takes its random generator, so a seeded
// generator gives the same session every time.

import Foundation

/// How many questions a practice session asks, before retries.
public let lettersSessionSize = 10

/// Options per question: the answer and three distractors.
public let letterOptionCount = 4

/// A miss comes back this many questions later (the lesson engine's retry depth).
public let lettersRetryDepth = 3

/// Tries per question, the first included (the lesson engine's attempt cap).
public let lettersMaxAttempts = 2

public enum LetterQuestionKind: CaseIterable, Equatable, Sendable {
    /// The letter is shown; pick the sound it makes.
    case letterToSound
    /// The letter's name and sound are shown; pick the letter.
    case soundToLetter
    /// A contextual form is shown; pick which letter it is.
    case formToLetter
    /// The letter is shown with a position; pick how it is written there.
    case letterToForm
}

/// One question. `options` are what the buttons show: sound labels for letterToSound,
/// Persian text for the rest. `attempt` counts earlier tries, so 0 the first time.
public struct LetterQuestion: Equatable, Sendable {
    public var kind: LetterQuestionKind
    public var letter: AbjadLetter
    public var form: LetterForm
    public var options: [String]
    public var answerIndex: Int
    public var attempt: Int

    public init(kind: LetterQuestionKind, letter: AbjadLetter, form: LetterForm, options: [String], answerIndex: Int, attempt: Int = 0) {
        self.kind = kind
        self.letter = letter
        self.form = form
        self.options = options
        self.answerIndex = answerIndex
        self.attempt = attempt
    }

    /// Stable across retries; unique within a session, which never asks about a letter twice.
    public var key: String { "\(kind)-\(letter.letter)" }

    public var answer: String { options[answerIndex] }

    public var optionsArePersian: Bool { kind != .letterToSound }

    /// The Persian shown big in the prompt, or nil when the prompt is the letter's name (sound to letter).
    public var promptGlyph: String? {
        switch kind {
        case .letterToSound, .letterToForm: return letter.letter
        case .formToLetter: return letterInForm(letter, form)
        case .soundToLetter: return nil
        }
    }
}

/// Letters whose skeletons look alike, told apart by dots or a stroke; the most plausible wrong answers.
private let shapeFamilies: [[String]] = [
    ["ب", "پ", "ت", "ث", "ن", "ی"], ["ج", "چ", "ح", "خ"], ["د", "ذ"], ["ر", "ز", "ژ"],
    ["س", "ش"], ["ص", "ض"], ["ط", "ظ"], ["ع", "غ"], ["ف", "ق"], ["ک", "گ"],
    ["ا"], ["ل"], ["م"], ["و"], ["ه"],
]

/// The other letters that look like `letter`.
public func lookalikes(_ letter: AbjadLetter, letters: [AbjadLetter] = abjadLetters) -> [AbjadLetter] {
    guard let family = shapeFamilies.first(where: { $0.contains(letter.letter) }) else { return [] }
    return letters.filter { $0.letter != letter.letter && family.contains($0.letter) }
}

/// At most this many of the three distractors come from the plausible pool.
private let maxPlausible = 2

private func distinct<T: Equatable>(_ items: [T]) -> [T] {
    var seen: [T] = []
    for item in items where !seen.contains(item) { seen.append(item) }
    return seen
}

/// Picks `count` distinct distractors: up to maxPlausible from `plausible`, the rest from `others`.
private func distractors<T: Equatable, G: RandomNumberGenerator>(plausible: [T], others: [T], count: Int, using random: inout G) -> [T] {
    var picked = Array(distinct(plausible).shuffled(using: &random).prefix(min(maxPlausible, count)))
    let rest = distinct(others).filter { !picked.contains($0) }.shuffled(using: &random)
    picked += rest.prefix(max(0, count - picked.count))
    return picked
}

/// The answer among its distractors, shuffled, and where the answer landed.
private func withAnswer<G: RandomNumberGenerator>(_ answer: String, wrong: [String], using random: inout G) -> (options: [String], index: Int) {
    let options = (wrong + [answer]).shuffled(using: &random)
    return (options, options.firstIndex(of: answer) ?? 0)
}

/// Positions where the letter looks different from its isolated self.
private func contextualForms(_ letter: AbjadLetter) -> [LetterForm] {
    letter.joinsNext ? [.initial, .medial, .final] : [.medial, .final]
}

/// A question of `kind` about `letter`; distractors come from `letters`.
public func letterQuestion<G: RandomNumberGenerator>(_ kind: LetterQuestionKind, _ letter: AbjadLetter, using random: inout G, letters: [AbjadLetter] = abjadLetters) -> LetterQuestion {
    let count = letterOptionCount - 1
    let others = letters.filter { $0.letter != letter.letter }
    let alike = lookalikes(letter, letters: letters)
    switch kind {
    case .letterToSound:
        // A lookalike that says the same thing (ث looks like ت but sounds like س) is no distractor.
        let plausible = alike.map { $0.sound }.filter { $0 != letter.sound }
        let rest = letters.map { $0.sound }.filter { $0 != letter.sound }
        let wrong = distractors(plausible: plausible, others: rest, count: count, using: &random).map { soundOf($0).label }
        let built = withAnswer(soundOf(letter.sound).label, wrong: wrong, using: &random)
        return LetterQuestion(kind: kind, letter: letter, form: .isolated, options: built.options, answerIndex: built.index)
    case .soundToLetter:
        // The prompt names the letter, so other spellings of its sound are fair distractors.
        let plausible = others.filter { $0.sound == letter.sound } + alike
        let wrong = distractors(plausible: plausible, others: others, count: count, using: &random).map { $0.letter }
        let built = withAnswer(letter.letter, wrong: wrong, using: &random)
        return LetterQuestion(kind: kind, letter: letter, form: .isolated, options: built.options, answerIndex: built.index)
    case .formToLetter:
        let form = contextualForms(letter).randomElement(using: &random) ?? .final
        let wrong = distractors(plausible: alike, others: others, count: count, using: &random).map { $0.letter }
        let built = withAnswer(letter.letter, wrong: wrong, using: &random)
        return LetterQuestion(kind: kind, letter: letter, form: form, options: built.options, answerIndex: built.index)
    case .letterToForm:
        let form = contextualForms(letter).randomElement(using: &random) ?? .final
        let wrong = distractors(plausible: alike, others: others, count: count, using: &random).map { letterInForm($0, form) }
        let built = withAnswer(letterInForm(letter, form), wrong: wrong, using: &random)
        return LetterQuestion(kind: kind, letter: letter, form: form, options: built.options, answerIndex: built.index)
    }
}

/// A fresh session: `size` questions, each about a different letter, the kinds spread as evenly as `size` allows.
public func lettersSession<G: RandomNumberGenerator>(using random: inout G, size: Int = lettersSessionSize, letters: [AbjadLetter] = abjadLetters) -> LettersSession {
    let targets = Array(letters.shuffled(using: &random).prefix(size))
    let all = LetterQuestionKind.allCases
    let kinds = (0..<targets.count).map { all[$0 % all.count] }.shuffled(using: &random)
    var queue: [LetterQuestion] = []
    for (letter, kind) in zip(targets, kinds) {
        queue.append(letterQuestion(kind, letter, using: &random, letters: letters))
    }
    return LettersSession(queue: queue)
}

public struct LetterAnswer: Equatable, Sendable {
    public var session: LettersSession
    public var question: LetterQuestion
    public var choice: Int
    public var correct: Bool
    public var requeued: Bool
}

/// A practice session in progress: a miss comes back lettersRetryDepth questions later, up to
/// lettersMaxAttempts tries in all. The score counts first tries only.
public struct LettersSession: Equatable, Sendable {
    public var queue: [LetterQuestion]
    public var totalCount: Int
    public var firstTryCorrect: Int

    public init(queue: [LetterQuestion], totalCount: Int? = nil, firstTryCorrect: Int = 0) {
        self.queue = queue
        self.totalCount = totalCount ?? queue.count
        self.firstTryCorrect = firstTryCorrect
    }

    public var current: LetterQuestion? { queue.first }
    public var finished: Bool { queue.isEmpty }
    public var completedCount: Int { totalCount - queue.count }
    public var score: Double { totalCount == 0 ? 0 : Double(firstTryCorrect) / Double(totalCount) }

    /// Answers the current question with option `choice`; nil when there is no question left.
    public func answer(_ choice: Int) -> LetterAnswer? {
        guard let question = current else { return nil }
        let correct = choice == question.answerIndex
        let attempt = question.attempt + 1
        var rest = Array(queue.dropFirst())
        let requeued = !correct && attempt < lettersMaxAttempts
        if requeued {
            var again = question
            again.attempt = attempt
            rest.insert(again, at: min(lettersRetryDepth, rest.count))
        }
        let gained = correct && question.attempt == 0 ? 1 : 0
        let next = LettersSession(queue: rest, totalCount: totalCount, firstTryCorrect: firstTryCorrect + gained)
        return LetterAnswer(session: next, question: question, choice: choice, correct: correct, requeued: requeued)
    }
}
