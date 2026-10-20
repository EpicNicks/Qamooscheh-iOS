import Foundation
import QModel

// What a remix holds: before it starts the learner picks whether it keeps
// every exercise it would build or only one kind. The filter runs client-side
// over the exercises already built, by render type, so submission, XP and
// review credit match an unfiltered remix.

public enum RemixContents: String, Equatable, Hashable, Sendable, CaseIterable {
    case all = "all"
    case typeIn = "type_in"
    case wordBank = "word_bank"
    case flashcards = "flashcards"
    case flashcardsAndAll = "flashcards_and_all"
    /// Fill-in-the-blank cards: its whole round is cloze cards, never exercises or flashcards.
    case cloze = "cloze"

    public var label: String {
        switch self {
        case .all: return "All exercises"
        case .typeIn: return "Typing only"
        case .wordBank: return "Word bank only"
        case .flashcards: return "Flashcards only"
        case .flashcardsAndAll: return "Flashcards + all exercises"
        case .cloze: return "Fill in the blank"
        }
    }
}

/// The choices a remix can offer: the flashcard ones only where it has flashcards at all; Fill in the blank is always last.
public func remixContentsOptions(hasFlashcards: Bool) -> [RemixContents] {
    return hasFlashcards ? [.all, .typeIn, .wordBank, .flashcards, .flashcardsAndAll, .cloze] : [.all, .typeIn, .wordBank, .cloze]
}

/// remembered when this remix offers it, else fallback.
public func initialRemixContents(remembered: RemixContents, options: [RemixContents], fallback: RemixContents) -> RemixContents {
    return options.contains(remembered) ? remembered : fallback
}

public func includesFlashcards(_ contents: RemixContents) -> Bool {
    return contents == .flashcards || contents == .flashcardsAndAll
}

/// Fill in the blank swaps the whole remix for a round of cloze cards.
public func isClozeContents(_ contents: RemixContents) -> Bool {
    return contents == .cloze
}

public func includesExercise(_ contents: RemixContents, renderType: ExerciseType) -> Bool {
    switch contents {
    case .all, .flashcardsAndAll: return true
    case .flashcards, .cloze: return false
    case .typeIn: return renderType == .typeIn
    case .wordBank: return renderType == .wordBank
    }
}

/// Keeps the exercises contents allows, THEN caps the result at max (nil = no cap),
/// so a filtered remix is still full whenever enough matching exercises exist.
public func filterRemixExercises<T>(_ exercises: [T], contents: RemixContents, max: Int? = nil, renderType: (T) -> ExerciseType) -> [T] {
    let kept = exercises.filter { includesExercise(contents, renderType: renderType($0)) }
    guard let limit = max else { return kept }
    return Array(kept.prefix(Swift.max(limit, 0)))
}

/// What a saved-words remix keeps of its flashcards and its exercises.
public struct SavedRemixSelection<C, E> {
    public var cards: [C]
    public var exercises: [E]

    public var isEmpty: Bool { return cards.isEmpty && exercises.isEmpty }
}

/// The saved-words remix under `contents` (web SavedPracticePage.filtered): the flashcards when the choice includes them,
/// and the exercises it allows by the type each will show as. An exercise whose type isn't known (`renderType` nil) stays
/// only in the choices that keep everything.
public func selectSavedRemix<C, E>(cards: [C], exercises: [E], contents: RemixContents, renderType: (E) -> ExerciseType?) -> SavedRemixSelection<C, E> {
    return SavedRemixSelection(
        cards: includesFlashcards(contents) ? cards : [],
        exercises: exercises.filter { exercise in
            if let type = renderType(exercise) { return includesExercise(contents, renderType: type) }
            return contents == .all || contents == .flashcardsAndAll
        })
}
