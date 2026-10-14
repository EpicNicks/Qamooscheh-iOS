import XCTest
import QModel
import QNetwork
@testable import QFeatures

private func ref(_ id: String, _ name: String?) -> FriendRefResponse {
    FriendRefResponse(userId: id, displayName: name, since: Date(timeIntervalSince1970: 0))
}

private final class FakeFriends: FriendsService, @unchecked Sendable {
    var friendsList = [ref("f1", "Dariush")]
    var requestList = [ref("r1", "Maryam")]
    var hits = [UserSearchResultResponse(userId: "u1", displayName: "Ali")]
    var requestStatus = FriendshipStatus.pending
    var friendsError: Error?
    var requestsError: Error?
    var searchError: Error?
    var requestError: Error?
    var acceptError: Error?
    var declineError: Error?
    var searched: [String] = []
    var requested: [String] = []
    var accepted: [String] = []
    var declined: [String] = []
    var friendsCalls = 0
    /// Runs inside the request call (to start a second action or edit while in flight).
    var duringRequest: (@MainActor () async -> Void)?

    func friends() async throws -> [FriendRefResponse] {
        friendsCalls += 1
        if let e = friendsError { throw e }
        return friendsList
    }

    func incomingRequests() async throws -> [FriendRefResponse] {
        if let e = requestsError { throw e }
        return requestList
    }

    func search(_ query: String) async throws -> [UserSearchResultResponse] {
        searched.append(query)
        if let e = searchError { throw e }
        return hits
    }

    func request(_ userId: String) async throws -> FriendshipStatus {
        requested.append(userId)
        if let hook = duringRequest { await hook() }
        if let e = requestError { throw e }
        return requestStatus
    }

    func accept(_ userId: String) async throws {
        accepted.append(userId)
        if let e = acceptError { throw e }
        requestList.removeAll { $0.userId == userId }
        friendsList.append(ref(userId, "New"))
    }

    func decline(_ userId: String) async throws {
        declined.append(userId)
        if let e = declineError { throw e }
        requestList.removeAll { $0.userId == userId }
    }
}

private func apiError(_ status: Int, _ message: String? = nil) -> ApiError {
    ApiError(status: status, body: message.map { ApiErrorBody(error: $0) })
}

@MainActor
final class FriendsModelTests: XCTestCase {
    private func makeModel(_ fake: FakeFriends, onUnauthorized: (@Sendable () -> Void)? = nil) -> FriendsModel {
        FriendsModel(service: fake, debounceNanos: 1_000_000, onUnauthorized: onUnauthorized)
    }

    func testLoadFillsBothListsAndIsLoadingBefore() async {
        let model = makeModel(FakeFriends())
        XCTAssertTrue(model.requests.loading)
        XCTAssertTrue(model.friends.loading)
        await model.load()
        XCTAssertEqual(model.requests.items?.map { $0.userId }, ["r1"])
        XCTAssertEqual(model.friends.items?.map { $0.userId }, ["f1"])
        XCTAssertFalse(model.friends.loading)
    }

    func testFailedReloadKeepsListUnderServerMessage() async {
        let fake = FakeFriends()
        let model = makeModel(fake)
        await model.load()
        fake.friendsError = apiError(500, "Friends are down.")
        await model.load()
        XCTAssertEqual(model.friends.items?.map { $0.userId }, ["f1"])
        XCTAssertEqual(model.friends.error, "Friends are down.")
        fake.friendsError = nil
        await model.load()
        XCTAssertNil(model.friends.error)
    }

    func testFirstLoadFailureShowsFallbackNotLoading() async {
        let fake = FakeFriends()
        fake.requestsError = apiError(500)
        let model = makeModel(fake)
        await model.load()
        XCTAssertEqual(model.requests.error, "Couldn't load requests.")
        XCTAssertFalse(model.requests.loading)
        XCTAssertNil(model.requests.items)
    }

    func testReappearingKeepsQueryResultsAndSent() async {
        let fake = FakeFriends()
        let model = makeModel(fake)
        model.onQueryChange("ali")
        await model.settleSearch()
        await model.add("u1")
        await model.load()
        XCTAssertEqual(model.query, "ali")
        XCTAssertEqual(model.results.count, 1)
        XCTAssertEqual(model.sent["u1"], .pending)
    }

    func testBurstOfTypingSearchesOnceWithTrimmedFinalText() async {
        let fake = FakeFriends()
        let model = makeModel(fake)
        model.onQueryChange("a")
        model.onQueryChange("al")
        model.onQueryChange(" ali ")
        await model.settleSearch()
        XCTAssertEqual(fake.searched, ["ali"])
        XCTAssertEqual(model.results.map { $0.userId }, ["u1"])
    }

    func testSameTrimmedQueryIsNotSearchedAgain() async {
        let fake = FakeFriends()
        let model = makeModel(fake)
        model.onQueryChange("ali")
        await model.settleSearch()
        model.onQueryChange("ali ")
        await model.settleSearch()
        XCTAssertEqual(fake.searched, ["ali"])
    }

    func testSearchFailureClearsResultsShowsMessageAndRetries() async {
        let fake = FakeFriends()
        let model = makeModel(fake)
        model.onQueryChange("ali")
        await model.settleSearch()
        fake.searchError = apiError(429)
        model.onQueryChange("alic")
        await model.settleSearch()
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertEqual(model.searchError, AuthRules.tooManyRequests)
        fake.searchError = nil
        model.onQueryChange("alic")
        await model.settleSearch()
        XCTAssertNil(model.searchError)
        XCTAssertEqual(model.results.count, 1)
    }

    func testAddRecordsPendingAndShowsRequestSent() async {
        let fake = FakeFriends()
        let model = makeModel(fake)
        await model.load()
        await model.add("u1")
        XCTAssertEqual(fake.requested, ["u1"])
        XCTAssertEqual(model.sent["u1"], .pending)
        XCTAssertEqual(hitAction(userId: "u1", sent: model.sent, friendIds: model.friendIds), .requestSent)
        XCTAssertFalse(model.busy.contains("u1"))
    }

    func testAddThatCompletesTheirRequestMakesFriendsAndReloads() async {
        let fake = FakeFriends()
        fake.requestStatus = .accepted
        let model = makeModel(fake)
        await model.load()
        let before = fake.friendsCalls
        await model.add("u1")
        XCTAssertEqual(hitAction(userId: "u1", sent: model.sent, friendIds: model.friendIds), .friends)
        XCTAssertGreaterThan(fake.friendsCalls, before)
    }

    func testAddFailureShowsServerMessageAndLeavesRowAddable() async {
        let fake = FakeFriends()
        fake.requestError = apiError(400, "You can't add yourself.")
        let model = makeModel(fake)
        await model.add("u1")
        XCTAssertEqual(model.actionError, "You can't add yourself.")
        XCTAssertNil(model.sent["u1"])
        XCTAssertEqual(hitAction(userId: "u1", sent: model.sent, friendIds: []), .add)
        XCTAssertTrue(model.busy.isEmpty)
    }

    func testAddFailureWithoutMessageUsesFallback() async {
        let fake = FakeFriends()
        fake.requestError = apiError(500)
        let model = makeModel(fake)
        await model.add("u1")
        XCTAssertEqual(model.actionError, "Couldn't send that request.")
    }

    func testAcceptMovesRequestToFriends() async {
        let model = makeModel(FakeFriends())
        await model.load()
        await model.accept("r1")
        XCTAssertEqual(model.requests.items?.count, 0)
        XCTAssertEqual(model.friends.items?.map { $0.userId }, ["f1", "r1"])
        XCTAssertNil(model.actionError)
    }

    func testAcceptFailureKeepsRequestAndReportsError() async {
        let fake = FakeFriends()
        fake.acceptError = apiError(404, "That request is gone.")
        let model = makeModel(fake)
        await model.load()
        await model.accept("r1")
        XCTAssertEqual(model.actionError, "That request is gone.")
        XCTAssertEqual(model.requests.items?.map { $0.userId }, ["r1"])
        XCTAssertTrue(model.busy.isEmpty)
    }

    func testDeclineRemovesRequestWithoutReloadingFriends() async {
        let fake = FakeFriends()
        let model = makeModel(fake)
        await model.load()
        let before = fake.friendsCalls
        await model.decline("r1")
        XCTAssertEqual(fake.declined, ["r1"])
        XCTAssertEqual(model.requests.items?.count, 0)
        XCTAssertEqual(fake.friendsCalls, before)
    }

    func testDeclineFailureFallback() async {
        let fake = FakeFriends()
        fake.declineError = URLError(.timedOut)
        let model = makeModel(fake)
        await model.load()
        await model.decline("r1")
        XCTAssertEqual(model.actionError, AuthRules.offline)
        XCTAssertEqual(model.requests.items?.count, 1)
    }

    func testSecondTapWhileBusyIsIgnoredAndOtherUsersStillWork() async {
        let fake = FakeFriends()
        let model = makeModel(fake)
        fake.duringRequest = { [weak model] in
            guard let model = model else { return }
            XCTAssertTrue(model.busy.contains("u1"))
            await model.add("u1")
            await model.add("u2")
        }
        await model.add("u1")
        XCTAssertEqual(fake.requested, ["u1", "u2"])
        XCTAssertTrue(model.busy.isEmpty)
    }

    func testQueryTypedDuringAddIsKept() async {
        let fake = FakeFriends()
        let model = makeModel(fake)
        fake.duringRequest = { [weak model] in model?.onQueryChange("mar") }
        await model.add("u1")
        XCTAssertEqual(model.query, "mar")
        await model.settleSearch()
        XCTAssertEqual(fake.searched, ["mar"])
    }

    func testUnauthorizedIsObservable() async {
        let fake = FakeFriends()
        fake.requestError = apiError(401)
        let counter = Counter()
        let model = makeModel(fake, onUnauthorized: { counter.bump() })
        await model.add("u1")
        XCTAssertEqual(counter.value, 1)
        fake.friendsError = apiError(401)
        await model.load()
        XCTAssertEqual(counter.value, 2)
    }

    func testHitActionStates() {
        XCTAssertEqual(hitAction(userId: "a", sent: [:], friendIds: []), .add)
        XCTAssertEqual(hitAction(userId: "a", sent: [:], friendIds: ["a"]), .friends)
        XCTAssertEqual(hitAction(userId: "a", sent: ["a": .pending], friendIds: []), .requestSent)
        XCTAssertEqual(hitAction(userId: "a", sent: ["a": .accepted], friendIds: []), .friends)
        XCTAssertEqual(hitAction(userId: "a", sent: ["a": .blocked], friendIds: []), .nothing)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func bump() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
