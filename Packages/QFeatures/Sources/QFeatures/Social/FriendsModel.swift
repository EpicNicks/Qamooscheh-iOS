import Foundation
import Combine
import QModel
import QNetwork
import QData

/// The friends calls the screen needs. `FriendsRepository` conforms; tests use a fake.
public protocol FriendsService: Sendable {
    func friends() async throws -> [FriendRefResponse]
    func incomingRequests() async throws -> [FriendRefResponse]
    func search(_ query: String) async throws -> [UserSearchResultResponse]
    func request(_ userId: String) async throws -> FriendshipStatus
    func accept(_ userId: String) async throws
    func decline(_ userId: String) async throws
}

extension FriendsRepository: FriendsService {}

/// One list on the page: loading while there are neither items nor an error (Android ListState).
public struct FriendsList: Equatable, Sendable {
    public var items: [FriendRefResponse]?
    public var error: String?

    public init(items: [FriendRefResponse]? = nil, error: String? = nil) {
        self.items = items
        self.error = error
    }

    public var loading: Bool { items == nil && error == nil }
}

/// What the web shows for a user who never set a display name.
public let friendsUnnamed = "Unnamed learner"

/// What a search hit's row offers (Android FriendsScreen).
public enum HitAction: Equatable, Sendable {
    case add
    case friends
    case requestSent
    case nothing
}

/// The status the add came back as, else Friends if already friends, else an Add button.
public func hitAction(userId: String, sent: [String: FriendshipStatus], friendIds: Set<String>) -> HitAction {
    let status: FriendshipStatus? = sent[userId] ?? (friendIds.contains(userId) ? FriendshipStatus.accepted : nil)
    guard let known = status else { return .add }
    switch known {
    case .accepted: return .friends
    case .pending: return .requestSent
    // Blocked is never a request's outcome; offer nothing rather than a button that fails.
    case .blocked: return .nothing
    }
}

/// State for the Friends screen (web FriendsPage + useFriends, Android FriendsViewModel).
@MainActor
public final class FriendsModel: ObservableObject {
    @Published public private(set) var query = ""
    @Published public private(set) var results: [UserSearchResultResponse] = []
    @Published public private(set) var searchError: String?
    @Published public private(set) var requests = FriendsList()
    @Published public private(set) var friends = FriendsList()
    /// Users with an add, accept or decline in flight; only their own buttons grey out.
    @Published public private(set) var busy: Set<String> = []
    /// What adding each search hit came back as.
    @Published public private(set) var sent: [String: FriendshipStatus] = [:]
    @Published public private(set) var actionError: String?

    private let service: FriendsService?
    private let debounceNanos: UInt64
    private let onUnauthorized: (@Sendable () -> Void)?
    private var searchTask: Task<Void, Never>?
    private var lastSearched: String?

    public init(service: FriendsService?, debounceNanos: UInt64 = 250_000_000, onUnauthorized: (@Sendable () -> Void)? = nil) {
        self.service = service
        self.debounceNanos = debounceNanos
        self.onUnauthorized = onUnauthorized
    }

    public var friendIds: Set<String> { Set((friends.items ?? []).map { $0.userId }) }

    /// Safe on every appearance: reloads the two lists but keeps the typed query, its results and what was sent.
    public func load() async {
        await loadRequests()
        await loadFriends()
    }

    /// Debounced (web SEARCH_DEBOUNCE_MS): a burst of typing makes one request; a superseded search never posts.
    public func onQueryChange(_ value: String) {
        query = value
        searchTask?.cancel()
        let nanos = debounceNanos
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            if Task.isCancelled { return }
            await self?.runSearch(value)
        }
    }

    /// Waits for the pending debounced search (tests).
    public func settleSearch() async {
        await searchTask?.value
    }

    private func runSearch(_ raw: String) async {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if q == lastSearched { return }
        guard let service = service else { return }
        do {
            let hits = try await service.search(q)
            if Task.isCancelled { return }
            results = hits
            searchError = nil
            lastSearched = q
        } catch {
            if Task.isCancelled { return }
            results = []
            searchError = failureMessage(error, fallback: "Couldn't search right now.")
            lastSearched = nil
        }
    }

    public func add(_ userId: String) async {
        await act(userId, fallback: "Couldn't send that request.") { service in
            let status = try await service.request(userId)
            self.sent[userId] = status
            // Adding someone who had already asked us makes us friends at once.
            await self.load()
        }
    }

    public func accept(_ userId: String) async {
        await act(userId, fallback: "Couldn't accept that request.") { service in
            try await service.accept(userId)
            await self.load()
        }
    }

    public func decline(_ userId: String) async {
        await act(userId, fallback: "Couldn't decline that request.") { service in
            try await service.decline(userId)
            await self.loadRequests()
        }
    }

    private func act(_ userId: String, fallback: String, _ block: (FriendsService) async throws -> Void) async {
        guard let service = service, !busy.contains(userId) else { return }
        busy.insert(userId)
        actionError = nil
        do {
            try await block(service)
        } catch {
            actionError = failureMessage(error, fallback: fallback)
        }
        busy.remove(userId)
    }

    func loadRequests() async {
        guard let service = service else { return }
        do {
            requests = FriendsList(items: try await service.incomingRequests())
        } catch {
            // A failed reload keeps the list it already had, under the error.
            requests.error = failureMessage(error, fallback: "Couldn't load requests.")
        }
    }

    func loadFriends() async {
        guard let service = service else { return }
        do {
            friends = FriendsList(items: try await service.friends())
        } catch {
            friends.error = failureMessage(error, fallback: "Couldn't load friends.")
        }
    }

    /// The server's message when there is one (Android userMessage); a 401 also reaches `onUnauthorized`.
    private func failureMessage(_ error: Error, fallback: String) -> String {
        if (error as? ApiError)?.status == 401 || error is SessionExpiredError { onUnauthorized?() }
        return AuthRules.message(for: error, fallback: fallback)
    }

    /// Seeds a loaded screen without any network (snapshot showcases).
    public static func preview(
        query: String, results: [UserSearchResultResponse], requests: FriendsList, friends: FriendsList,
        sent: [String: FriendshipStatus] = [:], busy: Set<String> = [], actionError: String? = nil
    ) -> FriendsModel {
        let model = FriendsModel(service: nil)
        model.query = query
        model.results = results
        model.requests = requests
        model.friends = friends
        model.sent = sent
        model.busy = busy
        model.actionError = actionError
        return model
    }
}
