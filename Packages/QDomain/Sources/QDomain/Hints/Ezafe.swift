import Foundation

// The ezafe: the unwritten "-e" that links a Persian noun to what describes
// or owns it (ketāb-e man, "my book"; havā-ye khub, "good weather"). Ordinary
// Persian never writes it, so content marks it where it's relevant, the way
// teaching texts do (the graders ignore both marks):
//
//   کتابِ من    a kasra on the word                        -> ketāb-e
//   هوایِ خوب   after a vowel, a kasra on the linking ی    -> havā-ye
//   خانهٔ من    after a silent heh, a hamza above it       -> khāne-ye
//
// A marked word is looked up WITHOUT its mark (and without the linking ی),
// and carries the ezafe beside its own hint, so the display can show it as
// its own highlighted piece. Port of web ezafe.ts.
//
// Works on Unicode scalars throughout: Swift's String suffix tests are
// grapheme- and canonical-equivalence-based, and a kasra or hamza combines
// with the letter before it.

public enum Ezafe: String, Equatable, Hashable, Sendable {
    case e = "-e"
    case ye = "-ye"

    public var text: String { return rawValue }
}

public struct EzafeReading: Equatable, Sendable {
    public var base: String
    public var ezafe: Ezafe

    public init(base: String, ezafe: Ezafe) {
        self.base = base
        self.ezafe = ezafe
    }
}

private let ezHeh: Unicode.Scalar = "\u{0647}"
private let ezYeh: Unicode.Scalar = "\u{06CC}"
private let ezAlef: Unicode.Scalar = "\u{0627}"
private let ezWaw: Unicode.Scalar = "\u{0648}"
private let ezZwnj: Unicode.Scalar = "\u{200C}"
private let ezKasra: Unicode.Scalar = "\u{0650}"
private let ezHamzaAbove: Unicode.Scalar = "\u{0654}"
/// Shadda (doubling). Unicode normalization orders it AFTER a kasra on the same letter, so it can hide a final ezafe mark.
private let ezShadda: Unicode.Scalar = "\u{0651}"

func scalarString(_ scalars: [Unicode.Scalar]) -> String {
    var view = String.UnicodeScalarView()
    view.append(contentsOf: scalars)
    return String(view)
}

/// The ways a marked `word` can read as a bare word plus its ezafe, most
/// likely first; empty when it carries no ezafe mark. A kasra on a final ی is
/// either the linking ی after a vowel (هوایِ = havā-ye) or a word that simply
/// ends in ی (چایِ = chāy-e); which one is decided by which bare word the
/// lexicon actually has.
public func ezafeReadings(_ marked: String) -> [EzafeReading] {
    var word = Array(marked.unicodeScalars)
    if word.last == ezShadda { word.removeLast() }
    if word.count >= 2, word[word.count - 2] == ezHeh, word[word.count - 1] == ezHamzaAbove {
        return [EzafeReading(base: scalarString(Array(word.dropLast())), ezafe: .ye)]
    }
    guard word.last == ezKasra else { return [] }
    let bare = Array(word.dropLast())
    guard bare.last == ezYeh else { return [EzafeReading(base: scalarString(bare), ezafe: .e)] }
    let beforeYeh = Array(bare.dropLast())
    // خانه‌یِ: a linking ی after a half-space always follows a vowel.
    if beforeYeh.last == ezZwnj {
        return [EzafeReading(base: scalarString(Array(beforeYeh.dropLast())), ezafe: .ye)]
    }
    let linking = EzafeReading(base: scalarString(beforeYeh), ezafe: .ye)
    let ownYeh = EzafeReading(base: scalarString(bare), ezafe: .e)
    let vowelFinal = beforeYeh.last == ezAlef || beforeYeh.last == ezWaw
    return vowelFinal ? [linking, ownYeh] : [ownYeh, linking]
}

/// The hint for an ezafe-marked `word`: its bare word's hint (from `lookup`,
/// which may itself split off attached endings, and is handed the word without
/// any of its vowel marks) plus the ezafe; nil when the word carries no mark
/// or no reading of it is a word `lookup` knows.
public func ezafeHint(_ word: String, lookup: (_ bare: String) -> WordHint?) -> WordHint? {
    for reading in ezafeReadings(word) {
        if var hint = lookup(PersianNormalize.stripReadingAids(reading.base)) {
            hint.ezafe = reading.ezafe
            return hint
        }
    }
    return nil
}
