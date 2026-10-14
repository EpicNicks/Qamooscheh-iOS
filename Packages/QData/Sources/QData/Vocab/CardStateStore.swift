import Foundation
import QModel

/// The device's mirror of the server's FSRS card state, one file per user, so it survives a
/// relaunch and one account never sees another's cards. Writes go through one actor, so two
/// merges can't read the same file and lose each other's cards; files are replaced atomically.
public actor CardStateStore {
    private let store: ContentFileStore

    public init(store: ContentFileStore) {
        self.store = store
    }

    /// Hex keeps any user id a valid store key.
    static func key(userId: String) -> String {
        "cardstate/" + userId.utf8.map { String(format: "%02x", $0) }.joined() + ".json"
    }

    /// Every card held for this user, by lexeme tag. A missing file, or one that can't be read right
    /// now, reads as empty; nothing here writes, so a failed read never costs the user their cards.
    public func all(userId: String) -> [String: CardState] {
        guard let loaded = try? load(userId: userId) else { return [:] }
        return loaded.cards
    }

    /// Folds server card states into this user's file. A card is replaced unless the held one was
    /// reviewed later (a late response from an earlier lesson must not roll a card back). A card that
    /// was never reviewed counts as older than any reviewed one. If the file can't be read, nothing
    /// is written and the error is thrown.
    public func merge(userId: String, cards: [CardState]) throws {
        if cards.isEmpty { return }
        let key = CardStateStore.key(userId: userId)
        let loaded = try load(userId: userId)
        if let raw = loaded.unreadableRaw { try quarantine(raw, key: key) }
        var held = loaded.cards
        for card in cards {
            if let existing = held[card.lexemeTag], CardStateStore.isLater(existing, than: card) { continue }
            held[card.lexemeTag] = card
        }
        let sorted = held.values.sorted { $0.lexemeTag < $1.lexemeTag }
        try store.write(try QJSON.makeEncoder().encode(sorted), to: key)
    }

    /// True when `held` was reviewed strictly after `incoming`; nil counts as oldest.
    private static func isLater(_ held: CardState, than incoming: CardState) -> Bool {
        guard let old = held.lastReviewedAt else { return false }
        guard let new = incoming.lastReviewedAt else { return true }
        return old > new
    }

    private struct Lossy: Decodable {
        let card: CardState?
        init(from decoder: Decoder) throws { card = try? CardState(from: decoder) }
    }

    private struct Loaded {
        var cards: [String: CardState] = [:]
        /// The raw bytes when the file wasn't a clean list of cards (not an array, or some elements bad).
        var unreadableRaw: Data?
    }

    /// Throws only when the read itself fails (transient I/O); no file is an empty result.
    private func load(userId: String) throws -> Loaded {
        guard let data = try store.read(CardStateStore.key(userId: userId)) else { return Loaded() }
        guard let items = try? QJSON.makeDecoder().decode([Lossy].self, from: data) else {
            return Loaded(cards: [:], unreadableRaw: data)
        }
        var loaded = Loaded()
        for item in items {
            if let card = item.card { loaded.cards[card.lexemeTag] = card } else { loaded.unreadableRaw = data }
        }
        return loaded
    }

    /// Keeps a copy of a file we couldn't fully read, under a name that never overwrites an earlier one.
    private func quarantine(_ raw: Data, key: String) throws {
        var name = key + ".corrupt"
        var n = 1
        while try store.read(name) != nil {
            n += 1
            name = key + ".corrupt." + String(n)
        }
        try store.write(raw, to: name)
    }

    /// Forgets this user's cards (sign-out of that account).
    public func clear(userId: String) throws {
        let key = CardStateStore.key(userId: userId)
        try store.remove(key)
        // Quarantined copies hold this user's cards too.
        try store.remove(key + ".corrupt")
        var n = 2
        while try store.read(key + ".corrupt." + String(n)) != nil {
            try store.remove(key + ".corrupt." + String(n))
            n += 1
        }
    }
}
