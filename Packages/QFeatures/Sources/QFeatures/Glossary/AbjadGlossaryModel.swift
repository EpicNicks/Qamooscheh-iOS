import Foundation
import Combine
import QDomain

/// A sound group as the page draws it: `letters` is the whole group, `shown` the ones the search left visible.
public struct ShownSoundGroup: Equatable {
    public let sound: SoundId
    public let letters: [AbjadLetter]
    public let shown: [AbjadLetter]
}

/// A search narrows each sound group to its matching letters and hides the groups left empty, but a
/// partly-matched group keeps its enclosure. `matching` nil (no search) shows everything.
public func shownSoundGroups(_ matching: [String]?, groups: [AbjadSoundGroup] = abjadSoundGroups()) -> [ShownSoundGroup] {
    guard let matching = matching else {
        return groups.map { ShownSoundGroup(sound: $0.sound, letters: $0.letters, shown: $0.letters) }
    }
    let set = Set(matching)
    return groups
        .map { ShownSoundGroup(sound: $0.sound, letters: $0.letters, shown: $0.letters.filter { set.contains($0.letter) }) }
        .filter { !$0.shown.isEmpty }
}

/// The flashcard deck's letters: the whole alphabet, or whatever the search narrowed it to, in alphabet order.
public func deckLetters(_ matching: [String]?, letters: [AbjadLetter] = abjadLetters) -> [AbjadLetter] {
    guard let matching = matching else { return letters }
    let set = Set(matching)
    return letters.filter { set.contains($0.letter) }
}

/// A Fisher-Yates shuffle of the deck positions 0..<length.
public func shuffledOrder<G: RandomNumberGenerator>(length: Int, using generator: inout G) -> [Int] {
    var order = Array(0..<max(length, 0))
    var i = order.count - 1
    while i >= 1 {
        let j = Int.random(in: 0...i, using: &generator)
        order.swapAt(i, j)
        i -= 1
    }
    return order
}

/// One piece of a letter's note: English prose, or a quoted Persian run.
public struct NoteSegment: Equatable {
    public let text: String
    public let isPersian: Bool
}

private func isPersianScalar(_ v: UInt32) -> Bool {
    (v >= 0x0600 && v <= 0x06FF) || v == 0x200C
}

/// JavaScript's `\s` (as the web splits notes).
private func isJSSpace(_ v: UInt32) -> Bool {
    switch v {
    case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: return true
    default: return false
    }
}

/// Notes are English prose quoting Persian. Each quoted run (spaces allowed between Persian words) is
/// split out so the UI can give it the Persian font and a bidi isolate. Empty pieces are dropped.
public func splitPersianRuns(_ text: String) -> [NoteSegment] {
    let scalars = Array(text.unicodeScalars)
    var segments: [NoteSegment] = []
    var plain = String.UnicodeScalarView()
    var i = 0
    while i < scalars.count {
        guard isPersianScalar(scalars[i].value) else {
            plain.append(scalars[i])
            i += 1
            continue
        }
        var end = i + 1
        var k = end
        while k < scalars.count {
            if isPersianScalar(scalars[k].value) {
                k += 1
                end = k
            } else if isJSSpace(scalars[k].value) {
                k += 1
            } else {
                break
            }
        }
        if !plain.isEmpty {
            segments.append(NoteSegment(text: String(plain), isPersian: false))
            plain = String.UnicodeScalarView()
        }
        var run = String.UnicodeScalarView()
        run.append(contentsOf: scalars[i..<end])
        segments.append(NoteSegment(text: String(run), isPersian: true))
        i = end
    }
    if !plain.isEmpty { segments.append(NoteSegment(text: String(plain), isPersian: false)) }
    return segments
}

public enum AbjadView: Equatable {
    case letters, flashcards
}

/// The flashcard deck's place: `order` is a shuffle of deck positions, or nil for alphabet order.
public struct DeckState: Equatable {
    public var order: [Int]?
    public var position: Int
    public var flipped: Bool

    public init(order: [Int]? = nil, position: Int = 0, flipped: Bool = false) {
        self.order = order
        self.position = position
        self.flipped = flipped
    }
}

/// The abjad page (web AbjadGlossary, Android AbjadGlossaryScreen/GlossaryViewModel): one form and
/// one letter search drive both the letter tiles and the flashcard deck.
@MainActor
public final class AbjadGlossaryModel: ObservableObject {
    @Published public private(set) var view: AbjadView = .letters
    @Published public private(set) var form: LetterForm = .isolated
    @Published public private(set) var tokens: [LetterSearchToken] = []
    /// What the search input still shows: only an unfinished "c", waiting for its "h".
    @Published public private(set) var pending: String = ""
    @Published public private(set) var groups: [ShownSoundGroup] = shownSoundGroups(nil)
    @Published public private(set) var deck: [AbjadLetter] = abjadLetters
    @Published public private(set) var deckState = DeckState()

    private let shuffle: (Int) -> [Int]

    public init(shuffle: ((Int) -> [Int])? = nil) {
        self.shuffle = shuffle ?? { n in
            var g = SystemRandomNumberGenerator()
            return shuffledOrder(length: n, using: &g)
        }
    }

    /// nil when there is no search; "Showing N of 32 letters" otherwise.
    public var status: String? {
        tokens.isEmpty ? nil : "Showing \(deck.count) of \(abjadLetters.count) letters"
    }

    /// The card on show: its letter, through the shuffle if there is one.
    public var card: AbjadLetter? {
        var index = deckState.position
        if let order = deckState.order, deckState.position >= 0, deckState.position < order.count {
            index = order[deckState.position]
        }
        return index >= 0 && index < deck.count ? deck[index] : nil
    }

    public func setView(_ newView: AbjadView) { view = newView }

    public func setForm(_ newForm: LetterForm) { form = newForm }

    /// The search input's new text: every valid character becomes a chip, the rest is dropped.
    public func onSearchInput(_ text: String) {
        let parsed = parseLetterSearch(text, tokens)
        setTokens(parsed.tokens, pending: parsed.pending)
    }

    public func removeToken(_ key: String) { setTokens(tokens.filter { $0.key != key }, pending: pending) }

    /// Backspace in an empty input takes the last chip.
    public func removeLastToken() { setTokens(Array(tokens.dropLast()), pending: pending) }

    public func clearSearch() { setTokens([], pending: "") }

    public func flipCard() { deckState.flipped.toggle() }

    /// Steps `delta` cards, wrapping at either end; the new card starts face up.
    public func moveCard(_ delta: Int) {
        let size = deck.count
        if size == 0 { return }
        let next = (((deckState.position + delta) % size) + size) % size
        deckState = DeckState(order: deckState.order, position: next, flipped: false)
    }

    public func toggleShuffle() {
        deckState = DeckState(order: deckState.order == nil ? shuffle(deck.count) : nil)
    }

    private func setTokens(_ newTokens: [LetterSearchToken], pending newPending: String) {
        let matching = lettersMatching(newTokens)
        let newDeck = deckLetters(matching)
        tokens = newTokens
        pending = newPending
        groups = shownSoundGroups(matching)
        // A different deck starts fresh at card 1, rather than carrying a place or shuffle over.
        if newDeck != deck { deckState = DeckState() }
        deck = newDeck
    }
}
