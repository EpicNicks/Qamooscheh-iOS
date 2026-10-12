import Foundation
import QModel

// Presentation of a verb index entry (QModel's VerbIndexEntry, verbs.json). The
// publisher generates every table, so nothing here conjugates: it only orders
// and labels what the entry already holds. Port of web verbForms.ts.

/// A tense key of `VerbIndexEntry.table` and its label.
public struct VerbTenseLabel: Equatable, Sendable {
    public var tense: String
    public var label: String

    public init(tense: String, label: String) {
        self.tense = tense
        self.label = label
    }
}

/// A person key of a tense's cells and its label.
public struct VerbPersonLabel: Equatable, Sendable {
    public var person: String
    public var label: String

    public init(person: String, label: String) {
        self.person = person
        self.label = label
    }
}

public let verbTenses: [VerbTenseLabel] = [
    VerbTenseLabel(tense: "present", label: "Present"),
    VerbTenseLabel(tense: "simplePast", label: "Simple past"),
    VerbTenseLabel(tense: "pastContinuous", label: "Past continuous"),
    VerbTenseLabel(tense: "presentPerfect", label: "Present perfect"),
    VerbTenseLabel(tense: "subjunctive", label: "Subjunctive"),
    VerbTenseLabel(tense: "imperative", label: "Imperative"),
    VerbTenseLabel(tense: "future", label: "Future"),
]

public let verbPersons: [VerbPersonLabel] = [
    VerbPersonLabel(person: "1s", label: "I"),
    VerbPersonLabel(person: "2s", label: "you"),
    VerbPersonLabel(person: "3s", label: "he / she"),
    VerbPersonLabel(person: "1p", label: "we"),
    VerbPersonLabel(person: "2p", label: "you (pl.)"),
    VerbPersonLabel(person: "3p", label: "they"),
]

/// The tenses an entry actually has a table for, in teaching order.
public func availableTenses(_ entry: VerbIndexEntry) -> [VerbTenseLabel] {
    return verbTenses.filter { !(entry.table[$0.tense] ?? [:]).isEmpty }
}

public struct VerbRow: Equatable, Sendable {
    public var person: String
    public var label: String
    public var written: String
    /// Nil where the course authors no spoken stems for this verb (and always, for the future).
    public var spoken: String?

    public init(person: String, label: String, written: String, spoken: String?) {
        self.person = person
        self.label = label
        self.written = written
        self.spoken = spoken
    }
}

/// One tense as table rows, in person order, for the affirmative or the negative. Persons the tense lacks (the imperative has two) are left out.
public func verbRows(_ entry: VerbIndexEntry, tense: String, negative: Bool) -> [VerbRow] {
    let cells = entry.table[tense] ?? [:]
    var rows: [VerbRow] = []
    for p in verbPersons {
        guard let cell = cells[p.person] else { continue }
        rows.append(VerbRow(
            person: p.person,
            label: p.label,
            written: negative ? cell.negative : cell.written,
            spoken: negative ? cell.negativeSpoken : cell.spoken
        ))
    }
    return rows
}

/// Whether to show a spoken column: any row in the tense has one.
public func hasSpokenColumn(_ rows: [VerbRow]) -> Bool {
    return rows.contains { $0.spoken != nil }
}
