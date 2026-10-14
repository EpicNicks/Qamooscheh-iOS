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

    /// Every card held for this user, by lexeme tag. A missing or unreadable file reads as empty.
    public func all(userId: String) -> [String: CardState] {
        guard let data = try? store.read(CardStateStore.key(userId: userId)),
              let cards = try? QJSON.makeDecoder().decode([CardState].self, from: data) else { return [:] }
        var byTag: [String: CardState] = [:]
        for card in cards { byTag[card.lexemeTag] = card }
        return byTag
    }

    /// Folds server card states into this user's file. A card is replaced unless the held one was
    /// reviewed later (a late response from an earlier lesson must not roll a card back).
    public func merge(userId: String, cards: [CardState]) throws {
        if cards.isEmpty { return }
        var held = all(userId: userId)
        for card in cards {
            if let existing = held[card.lexemeTag],
               let old = existing.lastReviewedAt, let new = card.lastReviewedAt, old > new {
                continue
            }
            held[card.lexemeTag] = card
        }
        let sorted = held.values.sorted { $0.lexemeTag < $1.lexemeTag }
        try store.write(try QJSON.makeEncoder().encode(sorted), to: CardStateStore.key(userId: userId))
    }

    /// Forgets this user's cards (sign-out of that account).
    public func clear(userId: String) throws {
        try store.remove(CardStateStore.key(userId: userId))
    }
}
