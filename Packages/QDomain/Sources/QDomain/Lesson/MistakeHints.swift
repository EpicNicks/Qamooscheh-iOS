import Foundation

// Short grammar reminders for common mistakes, shown on the word the review
// screen marks. Each hint is keyed by the kind of mistake it explains.
// Port of web domain/mistakeHints.ts.

public enum MistakeKind: Equatable, Sendable {
    case missingRa

    public var hint: String {
        switch self {
        case .missingRa:
            return "را marks a specific (definite) direct object. It follows the object: کتاب را خواندم, I read the book. Leave it out for an indefinite object: کتابی خواندم."
        }
    }
}

/// The common mistake a marked word of a correction shows, if there's a hint for it. `isMissing` is the review's "left out" mark: a typed answer's `.missing` word or a word-bank tile the learner left out.
public func mistakeKind(courseCode: String?, text: String, isMissing: Bool) -> MistakeKind? {
    if !Languages.isPersian(courseCode) || !isMissing { return nil }
    return PersianNormalize.foldCodepoints(PersianNormalize.normalizeStrict(text)) == "را" ? .missingRa : nil
}

public func mistakeKind(courseCode: String?, word: MarkedWord) -> MistakeKind? {
    return mistakeKind(courseCode: courseCode, text: word.text, isMissing: word.mark == .missing)
}
