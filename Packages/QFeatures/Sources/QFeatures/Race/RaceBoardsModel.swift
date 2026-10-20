import Foundation
import Combine
import QModel
import QNetwork

/// Perfect Delivery's boards (API_SPEC 2.8b): global, country, this week and friends, split by hardcore, and by device
/// class, of which this app only ever shows `touch`.
@MainActor
public final class RaceBoardsModel: ObservableObject {
    @Published public private(set) var scope: RaceScope = .global
    @Published public private(set) var hardcore = false
    @Published public private(set) var loading = true
    @Published public private(set) var entries: [RaceBoardEntry] = []
    @Published public private(set) var error: String?

    private let store: VocabularyStore
    private let race: RaceService?
    private let onUnauthorized: (@Sendable () -> Void)?
    private var generation = 0

    public init(store: VocabularyStore, race: RaceService?, onUnauthorized: (@Sendable () -> Void)? = nil) {
        self.store = store
        self.race = race
        self.onUnauthorized = onUnauthorized
    }

    public func selectScope(_ next: RaceScope) async {
        scope = next
        await load()
    }

    public func setHardcore(_ next: Bool) async {
        hardcore = next
        await load()
    }

    /// (Re)loads the board for the scope and switch as they are now. The newest call wins.
    public func load() async {
        generation += 1
        let mine = generation
        loading = true
        error = nil
        let shown = (scope: scope, hardcore: hardcore)
        await store.refresh()
        if mine != generation { return }
        guard let course = store.content?.courseCode, let race = race else {
            loading = false
            entries = []
            error = "Couldn't load the board."
            return
        }
        do {
            let board = try await race.board(courseCode: course, scope: shown.scope, hardcore: shown.hardcore)
            if mine != generation { return }
            entries = board.entries
            loading = false
        } catch {
            if isCancellation(error) { return }
            if isUnauthorizedError(error) { onUnauthorized?() }
            if mine != generation { return }
            entries = []
            loading = false
            self.error = AuthRules.message(for: error, fallback: "Couldn't load the board.")
        }
    }
}
