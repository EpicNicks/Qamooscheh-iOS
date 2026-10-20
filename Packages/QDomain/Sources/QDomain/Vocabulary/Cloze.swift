import Foundation
import QModel

// Fill-in-the-blank flashcards. A cloze card is a sentence from a Parsle the
// learner has met, with one saved word taken out: the English meaning stands in
// the gap and the learner types the word. The sentence comes from an existing
// exercise (no new content), the blank is found with the same segmentation that
// powers the tap-a-word hints, and the answer is graded on the device. XP and
// review scheduling are the server's (API_SPEC 2.8a, kind "cloze").
// Port of web cloze.ts (Android Cloze.kt).

/// The most attempts the server takes for one card.
public let maxClozeAttempts = 50

/// A typo is only forgiven in a word this long: in a shorter one a single letter is a different word.
private let typoMinLength = 4

/// XP a card pays by the attempt it was answered on, mirroring the server's ClozeRules.Xp (first try 5, then 3, then 1,
/// nothing later or for a give-up). A display estimate: the server's award, its per-word daily cooldown included, is what counts.
public func clozeXp(attempt: Int, correct: Bool) -> Int {
    if !correct { return 0 }
    switch attempt {
    case ...1: return 5
    case 2: return 3
    case 3: return 1
    default: return 0
    }
}

/// How the server rates the learner's FSRS card for an answer (API_SPEC 2.8a). The server does the rating; this mirrors it for the conformance table.
public enum ClozeRating: String, Equatable, Sendable {
    case good = "Good"
    case hard = "Hard"
    case again = "Again"
}

public func clozeRating(attempt: Int, correct: Bool) -> ClozeRating {
    if !correct { return .again }
    switch attempt {
    case ...1: return .good
    case 2: return .hard
    default: return .again
    }
}

public enum ClozeGrade: Equatable, Sendable {
    case exact
    case typo
    case wrong
}

private func comparable(_ text: String) -> String {
    return PersianNormalize.foldCodepoints(PersianNormalize.normalizeStrict(text)).lowercased()
}

/// Grades a typed word against the blank's accepted spellings. Reading aids (vowel marks, ezafe) and Arabic-vs-Persian
/// letter variants don't count as differences. Regular mode forgives one wrong, missing, extra or swapped letter in a
/// word of four letters or more (`.typo`); hardcore mode forgives nothing.
public func gradeCloze(_ typed: String, accepted: [String], hardcore: Bool) -> ClozeGrade {
    let answer = comparable(typed)
    if answer.isEmpty { return .wrong }
    let keys = accepted.map(comparable).filter { !$0.isEmpty }
    if keys.contains(answer) { return .exact }
    if hardcore { return .wrong }
    let forgiven = keys.contains { $0.utf16.count >= typoMinLength && withinOneEdit($0, answer) }
    return forgiven ? .typo : .wrong
}

public struct ClozeCard: Equatable, Sendable {
    /// The saved word the card drills: what the round is submitted under.
    public var tag: String
    /// The sentence before the blank, as written.
    public var before: String
    /// The sentence after the blank, as written.
    public var after: String
    /// The word as written in the sentence (with its reading aids): shown in the gap once answered.
    public var blankText: String
    /// The spellings accepted for the blank.
    public var accepted: [String]
    /// What stands in the gap: the English for the word.
    public var gapLabel: String
    /// The English side of the sentence pair.
    public var english: String
    /// The exercise's tags other than the blank's, which say how the words around the gap split.
    public var contextTags: [String]

    public init(tag: String, before: String, after: String, blankText: String, accepted: [String], gapLabel: String, english: String, contextTags: [String]) {
        self.tag = tag
        self.before = before
        self.after = after
        self.blankText = blankText
        self.accepted = accepted
        self.gapLabel = gapLabel
        self.english = english
        self.contextTags = contextTags
    }

    /// What the card plays through the typed-answer field: the accepted spellings stand as its answer.
    public var asTypeIn: ExerciseArtifact {
        return ExerciseArtifact(type: .typeIn, scriptMode: .native, prompt: "", answer: accepted, tags: contextTags)
    }
}

private struct SentenceSides {
    var sentence: String
    var english: String
}

/// The target-language and English sides of an exercise, or nil for a kind a blank can't be cut from.
private func sentenceSides(_ exercise: ExerciseArtifact) -> SentenceSides? {
    if exercise.type != .typeIn && exercise.type != .wordBank { return nil }
    guard let first = exercise.answer.first else { return nil }
    let answerText = exercise.type == .wordBank ? exercise.answer.joined(separator: " ") : first
    return isLatinText(exercise.prompt)
        ? SentenceSides(sentence: answerText, english: exercise.prompt)
        : SentenceSides(sentence: exercise.prompt, english: answerText)
}

private let clozeAside = try! NSRegularExpression(pattern: "\\([^)]*\\)")
private let clozeSpaces = try! NSRegularExpression(pattern: "\\s+")

private func clozeReplacing(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
    let range = NSRange(location: 0, length: (text as NSString).length)
    return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
}

/// The English that stands in the gap: a meaning of the word that appears in the English sentence when one does, else
/// the gloss without its asides, plus its register when the word is informal.
public func clozeGapLabel(_ entry: LexemeIndexEntry, english: String) -> String {
    let padded = " " + normalizeMeaning(english) + " "
    var label = glossAnswers(entry.gloss).first { padded.contains(" " + $0 + " ") }
    if label == nil {
        let stripped = clozeReplacing(clozeSpaces, in: clozeReplacing(clozeAside, in: entry.gloss, with: " "), with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        label = stripped.isEmpty ? entry.gloss : stripped
    }
    let shown = label ?? entry.gloss
    if let register = registerLabel(entry.register) { return "\(shown) [\(register)]" }
    return shown
}

/// The cloze card an exercise gives for `tag`, or nil when it can't give an unambiguous one: the word must be written
/// exactly once in the sentence, and not run together with another of the exercise's words under one hint.
/// `hintMap` is the course-wide (ungated) map.
public func buildClozeCard(
    exercise: ExerciseArtifact, tag: String, hintMap: [String: WordHint], lexemeIndex: [String: LexemeIndexEntry]
) -> ClozeCard? {
    guard let entry = lexemeIndex[tag], let sides = sentenceSides(exercise) else { return nil }

    let segments = segmentAnnotatedText(sides.sentence, hintMap, tags: exercise.tags)
    let hits = segments.indices.filter { index in
        segments[index].isWord && (segments[index].hint?.senses ?? []).contains { $0.tag == tag }
    }
    if hits.count != 1 { return nil }
    let at = hits[0]
    let own = Set(exercise.tags)
    if (segments[at].hint?.senses ?? []).filter({ own.contains($0.tag) }).count > 1 { return nil }

    let blankText = segments[at].text
    var accepted: [String] = []
    for spelling in [PersianNormalize.stripReadingAids(blankText)] + (entry.forms ?? []) where !accepted.contains(spelling) {
        accepted.append(spelling)
    }
    return ClozeCard(
        tag: tag,
        before: segments[..<at].map { $0.text }.joined(),
        after: segments[(at + 1)...].map { $0.text }.joined(),
        blankText: blankText,
        accepted: accepted,
        gapLabel: clozeGapLabel(entry, english: sides.english),
        english: sides.english,
        contextTags: exercise.tags.filter { $0 != tag }
    )
}

/// One saved word and the exercises (already loaded) that use it.
public struct ClozeSource: Equatable, Sendable {
    public var tag: String
    public var exercises: [ExerciseArtifact]

    public init(tag: String, exercises: [ExerciseArtifact]) {
        self.tag = tag
        self.exercises = exercises
    }
}

/// One card per source word, from the first of its exercises that gives a blank, or, with `pick`, one of those that do
/// (given how many there are). A word with no usable sentence is left out: a cloze round is all cloze cards.
public func buildClozeDeck(
    sources: [ClozeSource], hintMap: [String: WordHint], lexemeIndex: [String: LexemeIndexEntry],
    pick: (_ count: Int) -> Int = { _ in 0 }
) -> [ClozeCard] {
    return sources.compactMap { source in
        let cards = source.exercises.compactMap {
            buildClozeCard(exercise: $0, tag: source.tag, hintMap: hintMap, lexemeIndex: lexemeIndex)
        }
        return cards.isEmpty ? nil : cards[min(max(pick(cards.count), 0), cards.count - 1)]
    }
}

/// The sources for a Repack's cloze round: one per word, in the order `tags` give, each with the `exercises` that use
/// it. A word no exercise uses is left out here; a word with exercises but no usable blank is left out by `buildClozeDeck`.
public func clozeSourcesForTags(_ tags: [String], exercises: [ExerciseArtifact]) -> [ClozeSource] {
    var seen = Set<String>()
    var sources: [ClozeSource] = []
    for tag in tags where seen.insert(tag).inserted {
        let using = exercises.filter { $0.tags.contains(tag) }
        if !using.isEmpty { sources.append(ClozeSource(tag: tag, exercises: using)) }
    }
    return sources
}

/// How `GET /v1/vocab/starred/practice` names an exercise: the key `clozeSourcesFromPractice` looks it up by.
public func practiceExerciseKey(_ ref: StarredPracticeExercise) -> String {
    return "\(ref.unitKey)/\(ref.skillKey)/\(ref.ordinal)"
}

/// The sources for the saved-words round: one per practice word, with the exercises the server named that were found on disk.
public func clozeSourcesFromPractice(_ words: [StarredPracticeWord], exercises: [String: ExerciseArtifact]) -> [ClozeSource] {
    return words.map { word in
        ClozeSource(tag: word.tag, exercises: word.exercises.compactMap { exercises[practiceExerciseKey($0)] })
    }
}

public struct ClozeResult: Equatable, Sendable {
    public var tag: String
    /// False when the learner gave up on the card.
    public var correct: Bool
    /// The attempt the card ended on.
    public var attempt: Int
    public var elapsedMs: Int

    public init(tag: String, correct: Bool, attempt: Int, elapsedMs: Int) {
        self.tag = tag
        self.correct = correct
        self.attempt = attempt
        self.elapsedMs = elapsedMs
    }

    /// The card as `POST /v1/flashcards/submit` takes it.
    public var submitted: SubmittedFlashcard {
        return SubmittedFlashcard(tag: tag, kind: .cloze, correct: correct, attempt: attempt, elapsedMs: elapsedMs)
    }
}

public struct ClozeSummary: Equatable, Sendable {
    public var firstTry = 0
    public var secondTry = 0
    public var thirdTry = 0
    /// Right on a fourth attempt or later, which pays nothing.
    public var later = 0
    public var gaveUp = 0
    /// The most the round could pay: what the table says, before the server's per-word daily cooldown.
    public var maxXp = 0

    public init() {}

    /// Every card right on the first try.
    public var flawless: Bool { return firstTry > 0 && secondTry + thirdTry + later + gaveUp == 0 }
}

public func summarizeCloze(_ results: [ClozeResult]) -> ClozeSummary {
    var summary = ClozeSummary()
    for result in results {
        summary.maxXp += clozeXp(attempt: result.attempt, correct: result.correct)
        if !result.correct {
            summary.gaveUp += 1
        } else if result.attempt <= 1 {
            summary.firstTry += 1
        } else if result.attempt == 2 {
            summary.secondTry += 1
        } else if result.attempt == 3 {
            summary.thirdTry += 1
        } else {
            summary.later += 1
        }
    }
    return summary
}

/// What the card says an attempt is worth, before it is answered.
public func clozeAttemptWorth(_ attempt: Int) -> String {
    let xp = clozeXp(attempt: attempt, correct: true)
    if attempt <= 1 { return "Worth up to \(xp) XP." }
    return xp > 0 ? "Not quite. Now worth up to \(xp) XP." : "Not quite. This one no longer pays XP."
}

/// What the result screen shows of a round's XP while and after it is sent.
public enum ClozeXp: Equatable, Sendable {
    case saving
    case failed
    case saved(Int)
}

public struct ClozeResultLines: Equatable, Sendable {
    public var breakdown: String
    public var xp: String
}

/// The result screen's lines: how the cards went by attempt, and the XP the server returned.
public func clozeResultLines(_ summary: ClozeSummary, correct: Int, xp: ClozeXp) -> ClozeResultLines {
    var parts = [
        "\(summary.firstTry) on the first try (5 XP each)",
        "\(summary.secondTry) on the second (3 XP)",
        "\(summary.thirdTry) on the third (1 XP)",
    ]
    if summary.later > 0 { parts.append("\(summary.later) later (no XP)") }
    if summary.gaveUp > 0 { parts.append("\(summary.gaveUp) skipped") }
    let line: String
    switch xp {
    case .saving:
        line = "Saving your XP\u{2026}"
    case .failed:
        line = "Couldn't save this round's XP."
    case .saved(let earned):
        if earned > 0 {
            line = "+\(earned) XP" + (earned < summary.maxXp ? ". Words you've practised a lot today pay less." : "")
        } else if correct > 0 {
            line = "No XP this round: those words have paid out for today already, or aren't learned words yet."
        } else {
            line = "No XP this round."
        }
    }
    return ClozeResultLines(breakdown: parts.joined(separator: ", ") + ".", xp: line)
}

/// Cards in a lesson or theme Repack's cloze round, at most; a hand-picked Repack has no limit.
public let remixClozeMaxCards = 20

/// The words a lesson or theme Repack's cloze round is cut from: those due for review first (the learner has a card for
/// them and it is due), then new ones (no card yet), each in the order `tags` give. A word whose card isn't due yet is left out.
public func remixClozeTags(_ tags: [String], cards: [String: CardState], now: Date) -> [String] {
    var due: [String] = []
    var new: [String] = []
    var seen = Set<String>()
    for tag in tags where seen.insert(tag).inserted {
        if let card = cards[tag] {
            if card.dueAt.map({ $0 <= now }) ?? true { due.append(tag) }
        } else {
            new.append(tag)
        }
    }
    return due + new
}

/// Cards in one cloze submission, at most (the server takes 1...200).
public let maxClozeSubmitCards = 200
