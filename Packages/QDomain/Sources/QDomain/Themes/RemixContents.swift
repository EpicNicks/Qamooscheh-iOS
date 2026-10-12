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

    public var label: String {
        switch self {
        case .all: return "All exercises"
        case .typeIn: return "Typing only"
        case .wordBank: return "Word bank only"
        case .flashcards: return "Flashcards only"
        case .flashcardsAndAll: return "Flashcards + all exercises"
        }
    }
}

/// The choices a remix can offer: the flashcard ones only where it has flashcards at all.
public func remixContentsOptions(hasFlashcards: Bool) -> [RemixContents] {
    return hasFlashcards ? [.all, .typeIn, .wordBank, .flashcards, .flashcardsAndAll] : [.all, .typeIn, .wordBank]
}

/// remembered when this remix offers it, else fallback.
public func initialRemixContents(remembered: RemixContents, options: [RemixContents], fallback: RemixContents) -> RemixContents {
    return options.contains(remembered) ? remembered : fallback
}

public func includesFlashcards(_ contents: RemixContents) -> Bool {
    return contents == .flashcards || contents == .flashcardsAndAll
}

public func includesExercise(_ contents: RemixContents, renderType: ExerciseType) -> Bool {
    switch contents {
    case .all, .flashcardsAndAll: return true
    case .flashcards: return false
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
