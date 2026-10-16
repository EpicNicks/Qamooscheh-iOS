import Foundation

// Field-for-field copy of the backend's GraderContracts.cs (camelCase wire names).
// Nullable fields are omitted from the JSON when nil, as the C# serializer does.

/// One grading call. Optional fields feed only the response's xp, never the verdict.
public struct GraderRequest: Codable, Equatable, Sendable {
    public var exerciseType: String
    public var scriptMode: String
    public var submitted: String
    public var acceptedAnswers: [String]
    public var alternativeAnswers: [[String]]?
    public var attempt: Int?
    public var usedHint: Bool?
    public var retype: Bool?
    public var retypeNumber: Int?

    public init(
        exerciseType: String,
        scriptMode: String,
        submitted: String,
        acceptedAnswers: [String],
        alternativeAnswers: [[String]]? = nil,
        attempt: Int? = nil,
        usedHint: Bool? = nil,
        retype: Bool? = nil,
        retypeNumber: Int? = nil
    ) {
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

/// One separator difference. Index/length are UTF-16 code units of matchedAnswer.
public struct SeparatorEditResponse: Codable, Equatable, Sendable {
    public var kind: String
    public var index: Int
    public var length: Int

    public init(kind: String, index: Int, length: Int) {
        self.kind = kind
        self.index = index
        self.length = length
    }
}

/// The grader's answer. `error` is set only for an uninterpretable request; a wrong
/// answer is a successful call with verdict "Incorrect".
public struct GraderResponse: Codable, Equatable, Sendable {
    public var verdict: String?
    public var matchedAnswer: String?
    public var correct: Bool
    public var acceptedWithCorrection: Bool
    public var reasons: [String]
    public var error: String?
    public var xp: Int?
    public var separatorEdits: [SeparatorEditResponse]?

    public init(
        verdict: String?,
        matchedAnswer: String? = nil,
        correct: Bool = false,
        acceptedWithCorrection: Bool = false,
        reasons: [String] = [],
        error: String? = nil,
        xp: Int? = nil,
        separatorEdits: [SeparatorEditResponse]? = nil
    ) {
        self.verdict = verdict
        self.matchedAnswer = matchedAnswer
        self.correct = correct
        self.acceptedWithCorrection = acceptedWithCorrection
        self.reasons = reasons
        self.error = error
        self.xp = xp
        self.separatorEdits = separatorEdits
    }

    private enum CodingKeys: String, CodingKey {
        case verdict, matchedAnswer, correct, acceptedWithCorrection, reasons, error, xp, separatorEdits
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        verdict = try c.decodeIfPresent(String.self, forKey: .verdict)
        matchedAnswer = try c.decodeIfPresent(String.self, forKey: .matchedAnswer)
        correct = try c.decodeIfPresent(Bool.self, forKey: .correct) ?? false
        acceptedWithCorrection = try c.decodeIfPresent(Bool.self, forKey: .acceptedWithCorrection) ?? false
        reasons = try c.decodeIfPresent([String].self, forKey: .reasons) ?? []
        error = try c.decodeIfPresent(String.self, forKey: .error)
        xp = try c.decodeIfPresent(Int.self, forKey: .xp)
        separatorEdits = try c.decodeIfPresent([SeparatorEditResponse].self, forKey: .separatorEdits)
    }
}
