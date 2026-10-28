import Foundation


/// Qamooscheh.Domain.ScriptMode (user_prefs.script_mode).
public enum ScriptMode: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case native = "native"
    case romanized = "romanized"
    case both = "both"
}

/// Qamooscheh.Domain.Register (user_prefs.register and lexeme index entries).
public enum Register: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case spoken = "spoken"
    case written = "written"
    case both = "both"
    case standard = "standard"
}

/// Qamooscheh.Domain.KeyboardMode.
public enum KeyboardMode: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case contextual = "contextual"
    case isolated = "isolated"
}

/// Qamooscheh.Domain.ExerciseType.
public enum ExerciseType: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case wordBank = "word_bank"
    case typeIn = "type_in"
    case match = "match"
    case speak = "speak"
    /// Type what you hear (Backend#44): the prompt's recording with its text hidden, up to three plays, graded as type_in.
    case listenType = "listen_type"
    /// A type this build doesn't know (one added after the release). Any unrecognised name decodes to it, so a newer skill
    /// still loads; it is never shown or submitted, and a lesson holding one is declined (see `isPlayable` in QDomain).
    case unknown = "unknown"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ExerciseType(rawValue: raw) ?? .unknown
    }
}

/// Qamooscheh.Domain.ExerciseScriptMode.
public enum ExerciseScriptMode: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case native = "native"
    case romanized = "romanized"
}

/// Qamooscheh.Domain.FriendshipStatus.
public enum FriendshipStatus: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case pending = "pending"
    case accepted = "accepted"
    case blocked = "blocked"
}

/// Qamooscheh.Domain.ExerciseReportReason.
public enum ExerciseReportReason: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case audioWrong = "audio_wrong"
    case answerShouldBeAccepted = "answer_should_be_accepted"
    case other = "other"
}

/// Qamooscheh.Api.Flashcards.FlashcardKind.
public enum FlashcardKind: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case selfRated = "self_rated"
    case translation = "translation"
    case cloze = "cloze"
}

/// Qamooscheh.Api.SessionSubmit.SessionOutcome (PascalCase on the wire).
public enum SessionOutcome: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case processed = "Processed"
    case alreadyProcessed = "AlreadyProcessed"
    case rejected = "Rejected"
}

/// Qamooscheh.Domain.SkillCategory. Only standard advances the progress cursor.
public enum SkillCategory: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case standard = "standard"
    case story = "story"
    case conversation = "conversation"
    case song = "song"
}
