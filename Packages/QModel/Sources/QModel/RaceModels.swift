import Foundation

// The Repack race (backend Race/RaceContracts.cs, API_SPEC 2.8b). The device builds and grades the cloze cards; the server
// starts and finishes the run, times it, issues the FSRS weights and holds implausible runs off the boards.

public enum RaceMode: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    /// Ranked; ends at the 3rd strike.
    case perfectDelivery = "perfect_delivery"
    /// Unranked; runs until the learner stops. Personal best only.
    case endlessPractice = "endless_practice"
}

public enum RaceDeviceClass: String, Codable, Equatable, Hashable, Sendable {
    case touch = "touch"
    case keyboard = "keyboard"
}

public enum RaceScope: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case global = "global"
    case country = "country"
    case weekly = "weekly"
    case friends = "friends"
}

/// POST /v1/race/runs. `tags` are the lexeme tags of the deck the device built.
public struct StartRaceRequest: Codable, Equatable, Sendable {
    public var courseCode: String
    public var mode: RaceMode
    public var hardcore: Bool
    public var deviceClass: RaceDeviceClass
    public var tags: [String]

    public init(courseCode: String, mode: RaceMode, hardcore: Bool, deviceClass: RaceDeviceClass, tags: [String]) {
        self.courseCode = courseCode
        self.mode = mode
        self.hardcore = hardcore
        self.deviceClass = deviceClass
        self.tags = tags
    }
}

/// `weights` maps each learned tag to 1 + min(1 - R, 0.9). A tag missing from it is not a learned word and must not be dealt.
public struct StartRaceResponse: Codable, Equatable, Sendable {
    public var runId: String
    public var serverStartedAt: String
    public var weights: [String: Double]

    public init(runId: String, serverStartedAt: String, weights: [String: Double]) {
        self.runId = runId
        self.serverStartedAt = serverStartedAt
        self.weights = weights
    }
}

/// One card's answer: the attempt it ended on, and whether it was right (false is a give-up).
public struct RaceAnswer: Codable, Equatable, Sendable {
    public var tag: String
    public var attempt: Int
    public var correct: Bool
    public var elapsedMs: Int?

    public init(tag: String, attempt: Int, correct: Bool, elapsedMs: Int? = nil) {
        self.tag = tag
        self.attempt = attempt
        self.correct = correct
        self.elapsedMs = elapsedMs
    }
}

/// POST /v1/race/runs/{id}/finish: every answer in order, one per card. `deckDone` says the deck ran out.
public struct FinishRaceRequest: Codable, Equatable, Sendable {
    public var answers: [RaceAnswer]
    public var deckDone: Bool

    public init(answers: [RaceAnswer], deckDone: Bool = false) {
        self.answers = answers
        self.deckDone = deckDone
    }
}

public struct RacePersonalBest: Codable, Equatable, Sendable {
    public var score: Double
    public var timeMs: Int

    public init(score: Double, timeMs: Int) {
        self.score = score
        self.timeMs = timeMs
    }
}

/// `rank` is the run's place on its global board, only for a ranked, unheld run. `held` means a speed check kept it off
/// the boards (`heldReason` names it). `alreadyFinished`: the figures are what the run banked the first time.
public struct FinishRaceResponse: Codable, Equatable, Sendable {
    public var score: Double
    public var timeMs: Int
    public var solved: Int
    public var strikes: Int
    public var endReason: String
    public var xp: Int
    public var held: Bool
    public var heldReason: String?
    public var rank: Int?
    public var personalBest: RacePersonalBest?
    public var alreadyFinished: Bool

    public init(
        score: Double, timeMs: Int, solved: Int, strikes: Int, endReason: String, xp: Int, held: Bool = false,
        heldReason: String? = nil, rank: Int? = nil, personalBest: RacePersonalBest? = nil, alreadyFinished: Bool = false
    ) {
        self.score = score
        self.timeMs = timeMs
        self.solved = solved
        self.strikes = strikes
        self.endReason = endReason
        self.xp = xp
        self.held = held
        self.heldReason = heldReason
        self.rank = rank
        self.personalBest = personalBest
        self.alreadyFinished = alreadyFinished
    }
}

/// GET /v1/race/boards: the top 50 plus the caller's own row if outside them.
public struct RaceBoardResponse: Codable, Equatable, Sendable {
    public var entries: [RaceBoardEntry]

    public init(entries: [RaceBoardEntry] = []) {
        self.entries = entries
    }
}

public struct RaceBoardEntry: Codable, Equatable, Sendable {
    public var rank: Int
    public var userId: String
    public var displayName: String?
    public var country: String?
    public var score: Double
    public var timeMs: Int
    public var isYou: Bool

    public init(rank: Int, userId: String, displayName: String? = nil, country: String? = nil, score: Double, timeMs: Int, isYou: Bool = false) {
        self.rank = rank
        self.userId = userId
        self.displayName = displayName
        self.country = country
        self.score = score
        self.timeMs = timeMs
        self.isYou = isYou
    }
}
