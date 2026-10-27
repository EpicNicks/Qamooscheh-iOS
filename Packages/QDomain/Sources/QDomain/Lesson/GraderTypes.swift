import Foundation

// The published offline grader's wire contract (the backend's
// tools/Qamooscheh.<Language>.Grader.Core/GraderContracts.cs, API_SPEC.md §7).
// Defined here so QDomain does not depend on a grader package; a concrete
// Grader is injected by the app. Port of web grader/types.ts.

/// One grading call. exerciseType/scriptMode are the grader's own spelling ("TypeIn", "Native"), not the artifacts'.
public struct GraderRequest: Equatable, Sendable {
    public var exerciseType: String
    public var scriptMode: String
    public var submitted: String
    public var acceptedAnswers: [String]
    /// word_bank/match only: the artifact's other correct tile orders, passed through unchanged.
    public var alternativeAnswers: [[String]]?
    /// The next four only feed the response's `xp`; none changes the verdict. nil: a first attempt with no hint.
    public var attempt: Int?
    public var usedHint: Bool?
    public var retype: Bool?
    public var retypeNumber: Int?

    public init(exerciseType: String, scriptMode: String, submitted: String, acceptedAnswers: [String], alternativeAnswers: [[String]]? = nil, attempt: Int? = nil, usedHint: Bool? = nil, retype: Bool? = nil, retypeNumber: Int? = nil) {
        self.exerciseType = exerciseType
        self.scriptMode = scriptMode
        self.submitted = submitted
        self.acceptedAnswers = acceptedAnswers
        self.alternativeAnswers = alternativeAnswers
        self.attempt = attempt
        self.usedHint = usedHint
        self.retype = retype
        self.retypeNumber = retypeNumber
    }
}

/// The ways the grader says the learner's separators differ from `matchedAnswer`; "missing" and "extra" are from the learner's side.
public enum SeparatorEditKind: String, Codable, Equatable, Sendable {
    case missingZwnj
    case extraZwnj
    case spaceForZwnj
    case zwnjForSpace
    case missingSpace
    case extraSpace
}

/// One place the learner's separators differ. `index` and `length` are UTF-16 code units of `matchedAnswer` as published; an extra separator is a caret (`length` 0, `index` where it would sit).
public struct SeparatorEdit: Codable, Equatable, Sendable {
    public var kind: SeparatorEditKind
    public var index: Int
    public var length: Int

    public init(kind: SeparatorEditKind, index: Int, length: Int) {
        self.kind = kind
        self.index = index
        self.length = length
    }
}

/// A wrong answer is a successful call with verdict "Incorrect". `error` means the grader could not interpret the request at all.
public struct GraderResponse: Equatable, Sendable {
    public var verdict: String?
    public var matchedAnswer: String?
    public var correct: Bool
    public var acceptedWithCorrection: Bool
    /// The language's own correction taxonomy ("ZwnjOrSpacing", "CodepointSubstitution", ...): display detail, not a cross-language contract.
    public var reasons: [String]
    /// Persian only: where the separators differ from `matchedAnswer`, in index order.
    public var separatorEdits: [SeparatorEdit]?
    public var error: String?
    public var xp: Int?
    /// The award before hint halving. nil from a grader older than fa v107.
    public var xpBase: Int?
    /// Why the award is what it is: one base code plus hint_halved when a hint lowered it. nil from an older grader.
    public var xpReasons: [String]?
    /// The grader's English line for each xpReasons code, same order and length. nil from an older grader.
    public var xpLines: [String]?

    public init(verdict: String? = "Incorrect", matchedAnswer: String? = nil, correct: Bool = false, acceptedWithCorrection: Bool = false, reasons: [String] = [], separatorEdits: [SeparatorEdit]? = nil, error: String? = nil, xp: Int? = 0, xpBase: Int? = nil, xpReasons: [String]? = nil, xpLines: [String]? = nil) {
        self.verdict = verdict
        self.matchedAnswer = matchedAnswer
        self.correct = correct
        self.acceptedWithCorrection = acceptedWithCorrection
        self.reasons = reasons
        self.separatorEdits = separatorEdits
        self.error = error
        self.xp = xp
        self.xpBase = xpBase
        self.xpReasons = xpReasons
        self.xpLines = xpLines
    }
}

/// The loaded grader.
public protocol Grader {
    func gradeEnvelope(_ request: GraderRequest) -> GraderResponse
    func xp(verdict: String, attempt: Int, usedHint: Bool, retype: Bool, retypeNumber: Int?) -> Int
}
