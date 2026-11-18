import Foundation
import QModel
import QDomain

/// What the verb forms view shows for one verbs.json entry, decided without any UI so swift test proves it
/// (vocab-search-verbs; web VerbFormsTable). Persian strings follow the learner's vowel-marks setting, as lessons do.
public struct VerbFormsTable: Equatable, Sendable {
    public var infinitive: String
    public var gloss: String?
    public var principalParts: [String]
    /// The tenses the entry has a table for, in teaching order; the picker's options.
    public var tenses: [VerbTenseLabel]
    /// The tense shown: the requested one when the entry has it, else the first available; nil when it has none.
    public var tense: String?
    public var negative: Bool
    public var rows: [VerbRow]
    /// Whether any row has a spoken form, so the table shows a Spoken column.
    public var showsSpoken: Bool

    public init(entry: VerbIndexEntry, requestedTense: String?, negative: Bool, vowelMarks: Bool) {
        func shown(_ s: String) -> String {
            return vowelMarks ? s : PersianNormalize.stripReadingAids(s)
        }
        let tenses = availableTenses(entry)
        let tense: String?
        if let requested = requestedTense, tenses.contains(where: { $0.tense == requested }) {
            tense = requested
        } else {
            tense = tenses.first?.tense
        }
        var rows: [VerbRow] = []
        if let tense = tense {
            for row in verbRows(entry, tense: tense, negative: negative) {
                var next = row
                next.written = shown(row.written)
                next.spoken = row.spoken.map(shown)
                rows.append(next)
            }
        }
        let gloss = entry.gloss?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.infinitive = shown(entry.infinitive)
        self.gloss = (gloss?.isEmpty ?? true) ? nil : gloss
        self.principalParts = entry.principalParts.map(shown)
        self.tenses = tenses
        self.tense = tense
        self.negative = negative
        self.rows = rows
        self.showsSpoken = hasSpokenColumn(rows)
    }
}

/// The verb whose forms sheet is open, by its verbs.json key.
struct VerbFormsTarget: Identifiable, Equatable {
    let id: String
}
