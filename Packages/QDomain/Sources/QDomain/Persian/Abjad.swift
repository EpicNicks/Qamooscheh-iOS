// Port of web:src/domain/persian/abjad.ts (Android: Abjad.kt).
//
// The Persian alphabet (abjad) as reference data for the glossary's
// "Persian Letters (Abjad)" page. `abjadLetters` (AbjadLetters.swift) is the
// single source: all 32 letters in alphabet order, each tagged with its sound.
// The same-sound groups, positional forms and flashcard deck are derived from it.

import Foundation

public enum LetterForm: String, CaseIterable, Sendable {
    case isolated, initial, medial, final
}

/// The sounds the letters make; the raw value is the web's SoundId string, which the letter search also uses as Latin input.
public enum SoundId: String, CaseIterable, Sendable {
    case a, b, p, t, s, j, ch, h, kh, d, z, r, zh, sh
    case glottal, gh, f, k, g, l, m, n, v, y
}

public struct AbjadSound: Equatable, Sendable {
    /// How the sound is romanized throughout the app.
    public let label: String
    /// A plain-English anchor for the sound ("as in sun").
    public let hint: String

    public init(label: String, hint: String) {
        self.label = label
        self.hint = hint
    }
}

public let abjadSounds: [SoundId: AbjadSound] = [
    .a: AbjadSound(label: "ā / a / e / o", hint: "vowel carrier"),
    .b: AbjadSound(label: "b", hint: "as in boy"),
    .p: AbjadSound(label: "p", hint: "as in pen"),
    .t: AbjadSound(label: "t", hint: "as in top"),
    .s: AbjadSound(label: "s", hint: "as in sun"),
    .j: AbjadSound(label: "j", hint: "as in jam"),
    .ch: AbjadSound(label: "ch", hint: "as in chair"),
    .h: AbjadSound(label: "h", hint: "as in hat"),
    .kh: AbjadSound(label: "kh", hint: "ch in Scottish loch"),
    .d: AbjadSound(label: "d", hint: "as in dog"),
    .z: AbjadSound(label: "z", hint: "as in zoo"),
    .r: AbjadSound(label: "r", hint: "a light tap"),
    .zh: AbjadSound(label: "zh", hint: "s in measure"),
    .sh: AbjadSound(label: "sh", hint: "as in shoe"),
    .glottal: AbjadSound(label: "'", hint: "glottal stop, or silent"),
    .gh: AbjadSound(label: "gh", hint: "throaty, like French r"),
    .f: AbjadSound(label: "f", hint: "as in fun"),
    .k: AbjadSound(label: "k", hint: "as in kite"),
    .g: AbjadSound(label: "g", hint: "as in go"),
    .l: AbjadSound(label: "l", hint: "as in lamp"),
    .m: AbjadSound(label: "m", hint: "as in moon"),
    .n: AbjadSound(label: "n", hint: "as in net"),
    .v: AbjadSound(label: "v / u / o", hint: "consonant or vowel"),
    .y: AbjadSound(label: "y / i", hint: "consonant or vowel"),
]

/// The sound's entry; every SoundId has one.
public func soundOf(_ id: SoundId) -> AbjadSound {
    abjadSounds[id]!
}

public struct AbjadExample: Equatable, Sendable {
    public let word: String
    public let romanization: String
    public let meaning: String

    public init(word: String, romanization: String, meaning: String) {
        self.word = word
        self.romanization = romanization
        self.meaning = meaning
    }
}

public struct AbjadLetter: Equatable, Sendable {
    public let letter: String
    public let sound: SoundId
    public let nameNative: String
    public let nameRomanized: String
    /// False for the seven letters that never join the letter after them (ا د ذ ر ز ژ و).
    public let joinsNext: Bool
    public let example: AbjadExample
    /// The "Learn more" side's extra context, when the letter has a story beyond its sound.
    public let note: String?

    public init(letter: String, sound: SoundId, nameNative: String, nameRomanized: String, joinsNext: Bool, example: AbjadExample, note: String?) {
        self.letter = letter
        self.sound = sound
        self.nameNative = nameNative
        self.nameRomanized = nameRomanized
        self.joinsNext = joinsNext
        self.example = example
        self.note = note
    }
}

private let tatweel = "ـ"

/// The letter as it appears in `form`, drawn with a tatweel (ـ) on each side that joins a neighbor.
/// A non-joiner has nothing to extend on its left, so its initial/medial shapes collapse to isolated/final.
public func letterInForm(_ letter: String, joinsNext: Bool, _ form: LetterForm) -> String {
    let joinsPrev = form == .medial || form == .final
    let extendsNext = joinsNext && (form == .initial || form == .medial)
    return (joinsPrev ? tatweel : "") + letter + (extendsNext ? tatweel : "")
}

public func letterInForm(_ letter: AbjadLetter, _ form: LetterForm) -> String {
    letterInForm(letter.letter, joinsNext: letter.joinsNext, form)
}

public struct AbjadSoundGroup: Equatable, Sendable {
    public let sound: SoundId
    public let letters: [AbjadLetter]
}

/// Letters grouped by sound, groups in the order their first letter appears in the alphabet.
public func abjadSoundGroups(_ letters: [AbjadLetter] = abjadLetters) -> [AbjadSoundGroup] {
    var order: [SoundId] = []
    var grouped: [SoundId: [AbjadLetter]] = [:]
    for letter in letters {
        if grouped[letter.sound] == nil {
            order.append(letter.sound)
            grouped[letter.sound] = [letter]
        } else {
            grouped[letter.sound]!.append(letter)
        }
    }
    return order.map { AbjadSoundGroup(sound: $0, letters: grouped[$0]!) }
}

public struct AbjadFlashcard: Equatable, Sendable {
    public let id: String
    /// Front: the letter itself (the deck UI picks which positional form to draw).
    public let letter: AbjadLetter
    /// Back: what it sounds like and what it's called.
    public let sound: AbjadSound
    public let nameRomanized: String
    public let nameNative: String
}

/// One card per letter, in alphabet order.
public func abjadFlashcards(_ letters: [AbjadLetter] = abjadLetters) -> [AbjadFlashcard] {
    letters.map { letter in
        AbjadFlashcard(
            id: letter.letter,
            letter: letter,
            sound: soundOf(letter.sound),
            nameRomanized: letter.nameRomanized,
            nameNative: letter.nameNative
        )
    }
}
