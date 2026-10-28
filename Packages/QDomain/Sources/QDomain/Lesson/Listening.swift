import Foundation
import QModel

// The listening exercise (listen_type, Backend#44) and the exercise types this build can't show. Port of Android
// Answers.kt isPlayable and the plays rules in LessonEngine.kt. No grader code: extra plays are the client's own line.

public enum Listening {
    /// A recording can be played this many times in one showing.
    public static let maxPlays = 3

    /// The line shown when extra plays, not a retry, priced the answer down.
    public static let extraPlaysNote = "You played it more than once"

    /// Whether `audio` holds at least one usable take (a voice with a non-empty first take).
    public static func hasRecording(_ audio: AudioMap?) -> Bool {
        guard let audio = audio else { return false }
        return audio.values.contains { takes in
            if let first = takes.first { return !first.isEmpty }
            return false
        }
    }

    /// Plays left of the three after `plays` finished ones.
    public static func playsLeft(_ plays: Int) -> Int { return max(0, maxPlays - plays) }

    /// The playsUsed to send: 1 to 3, and 1 for an answer given unheard.
    public static func playsUsed(_ plays: Int) -> Int { return min(max(plays, 1), maxPlays) }

    /// The attempt the server prices the answer as: max(attempt, playsUsed). `attempt` is 1-based.
    public static func pricedAttempt(attempt: Int, plays: Int) -> Int { return max(attempt, playsUsed(plays)) }

    /// Whether extra plays, not the attempt, priced the answer.
    public static func playedMoreThanOnce(attempt: Int, plays: Int) -> Bool { return pricedAttempt(attempt: attempt, plays: plays) > attempt }
}

extension Listening {
    /// The takes of `audio` to try, best first: the usual pick, then every voice's first take in voice order. A listening
    /// exercise plays its recording only (never speech), and offline only the course's default voice is on the device,
    /// so the player takes the first of these that it holds.
    public static func candidates(_ audio: AudioMap?) -> [String] {
        guard let audio = audio else { return [] }
        var result: [String] = []
        if let picked = Recordings.pickRecording(audio, choice: VoiceChoice(preferredVoice: nil, defaultVoice: nil)), !picked.isEmpty {
            result.append(picked)
        }
        for voice in audio.keys.sorted(by: { $0.utf16.lexicographicallyPrecedes($1.utf16) }) {
            if let take = audio[voice]?.first, !take.isEmpty, !result.contains(take) { result.append(take) }
        }
        return result
    }
}

/// How one take of a recording ended.
public enum PlayEnd: Equatable, Sendable {
    /// It ran to its end: the only way a play is charged.
    case completed
    /// Stopped by another voice, leaving the screen or the system. Free.
    case cutOff
    /// It could not be loaded or broke off. Free.
    case failed
}

/// Where a listening exercise's plays stand: finished plays, and whether a take is running right now. Both play buttons
/// (normal and slow) are locked while a take runs, so stopping each play early cannot give free plays.
public struct ListeningPlays: Equatable, Sendable {
    public private(set) var finished: Int
    public private(set) var playing: Bool

    public init(finished: Int = 0, playing: Bool = false) {
        self.finished = finished
        self.playing = playing
    }

    public var left: Int { return Listening.playsLeft(finished) }

    /// Whether a play can start now.
    public var canStart: Bool { return !playing && left > 0 }

    /// The buttons are locked while a take runs.
    public var buttonsLocked: Bool { return playing }

    /// Marks a take as started; false (and no change) when one is running or none are left.
    public mutating func begin() -> Bool {
        if !canStart { return false }
        playing = true
        return true
    }

    /// Ends the running take; a play is charged only if it completed (a slow replay counts like any other).
    public mutating func end(_ how: PlayEnd) {
        if !playing { return }
        playing = false
        if how == .completed && left > 0 { finished += 1 }
    }
}

/// Whether this build can put `exercise` in front of a learner. A type it doesn't know can't be; neither can a listening
/// exercise with no recording of its prompt, since the text is never shown in place of the audio.
public func isPlayable(_ exercise: ExerciseArtifact) -> Bool {
    switch exercise.type {
    case .unknown: return false
    case .listenType: return Listening.hasRecording(exercise.promptAudio)
    case .wordBank, .typeIn, .match, .speak: return true
    }
}

/// What to do with the exercises of a session that holds some this build can't play.
public enum PlayableScreen<T>: Equatable where T: Equatable {
    /// All playable, or the unplayable ones were left out.
    case play([T])
    /// A submitted session needs every ordinal answered, so one that can't be played is declined, not skipped.
    case decline
}

/// A lesson or checkpoint (`submitted`) holding an unplayable exercise is declined; a repack or practice round leaves it out.
public func screenUnplayable<T: Equatable>(_ items: [T], submitted: Bool, exercise: (T) -> ExerciseArtifact) -> PlayableScreen<T> {
    let playable = items.filter { isPlayable(exercise($0)) }
    if submitted && playable.count != items.count { return .decline }
    return .play(playable)
}

/// Shown when a lesson is declined for an exercise this build can't play.
public let unplayableLessonMessage = "Some exercises in this Parsle can't be played on this version of Qamooscheh. Try updating the app."
