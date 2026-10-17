import XCTest
import QModel
import QNetwork
import QData
@testable import QFeatures

private final class FakeContacts: ContactsService, @unchecked Sendable {
    var state = ContactsFindableResponse(findable: false, canBeFound: true)
    var matchesByCall: [[ContactMatchResponse]] = []
    var matchError: Error?
    var failFromCall: Int?
    var setError: Error?
    var sentBatches: [[String]] = []
    var setCalls: [Bool] = []

    func findable() async throws -> ContactsFindableResponse { state }

    func setFindable(_ value: Bool) async throws -> ContactsFindableResponse {
        setCalls.append(value)
        if let e = setError { throw e }
        state.findable = value
        return state
    }

    func match(_ hashes: [String]) async throws -> [ContactMatchResponse] {
        sentBatches.append(hashes)
        if let from = failFromCall, sentBatches.count >= from { throw ApiError(status: 429, body: nil) }
        if let e = matchError { throw e }
        return matchesByCall.isEmpty ? [] : matchesByCall.removeFirst()
    }
}

private final class FakeReader: ContactEmailReading, @unchecked Sendable {
    var allowed = true
    var addresses: [String] = []
    var accessAsked = 0
    var emailsRead = 0

    func requestAccess() async throws -> Bool {
        accessAsked += 1
        return allowed
    }

    func emails() async throws -> [String] {
        emailsRead += 1
        return addresses
    }
}

@MainActor
final class ContactsMatchingModelTests: XCTestCase {
    private func make(_ service: FakeContacts, _ reader: FakeReader) -> ContactsMatchingModel {
        ContactsMatchingModel(service: service, reader: reader)
    }

    func testDefaultsOffAndNeverReadsContactsUntilOptedIn() async {
        let service = FakeContacts()
        let reader = FakeReader()
        reader.addresses = ["a@x.com"]
        let model = make(service, reader)
        await model.load()
        XCTAssertFalse(model.findable)
        await model.findFriends()
        XCTAssertEqual(reader.accessAsked, 0)
        XCTAssertEqual(reader.emailsRead, 0)
        XCTAssertTrue(service.sentBatches.isEmpty)
        XCTAssertNil(model.matches)
    }

    func testOptInThenSendsOnlyHashes() async {
        let service = FakeContacts()
        let reader = FakeReader()
        reader.addresses = ["Ann@X.com ", "ann@x.com", "bob@x.com"]
        service.matchesByCall = [[ContactMatchResponse(userId: "u1", displayName: "Ann", relationship: .none)]]
        let model = make(service, reader)
        await model.load()
        await model.setFindable(true)
        XCTAssertTrue(model.findable)
        await model.findFriends()
        XCTAssertEqual(service.sentBatches.count, 1)
        XCTAssertEqual(service.sentBatches[0], [ContactHashing.sha256Hex("ann@x.com"), ContactHashing.sha256Hex("bob@x.com")])
        XCTAssertFalse(service.sentBatches.flatMap { $0 }.contains { $0.contains("@") })
        XCTAssertEqual(model.matches?.map { $0.userId }, ["u1"])
    }

    func testDeniedPermissionStopsBeforeReadingAnyContact() async {
        let service = FakeContacts()
        service.state.findable = true
        let reader = FakeReader()
        reader.allowed = false
        let model = make(service, reader)
        await model.load()
        await model.findFriends()
        XCTAssertEqual(reader.emailsRead, 0)
        XCTAssertTrue(service.sentBatches.isEmpty)
        XCTAssertNotNil(model.message)
    }

    func testCapsAtDailyAllowanceAndSplitsIntoCallsOf500() async {
        let service = FakeContacts()
        service.state.findable = true
        let reader = FakeReader()
        reader.addresses = (0 ..< 1200).map { "c\($0)@x.com" }
        let model = make(service, reader)
        await model.load()
        await model.findFriends()
        XCTAssertEqual(service.sentBatches.map { $0.count }, [500, 500])
        XCTAssertTrue(model.truncated)
    }

    func testTurningOffClearsResultsAndFailedToggleKeepsState() async {
        let service = FakeContacts()
        service.state.findable = true
        let reader = FakeReader()
        reader.addresses = ["a@x.com"]
        service.matchesByCall = [[ContactMatchResponse(userId: "u1", displayName: "Ann", relationship: .friends)]]
        let model = make(service, reader)
        await model.load()
        await model.findFriends()
        XCTAssertNotNil(model.matches)
        service.setError = ApiError(status: 500, body: nil)
        await model.setFindable(false)
        XCTAssertTrue(model.findable)
        XCTAssertNotNil(model.message)
        service.setError = nil
        await model.setFindable(false)
        XCTAssertFalse(model.findable)
        XCTAssertNil(model.matches)
    }

    func testRateLimitShowsServerMessage() async {
        let service = FakeContacts()
        service.state.findable = true
        service.matchError = ApiError(status: 429, body: nil)
        let reader = FakeReader()
        reader.addresses = ["a@x.com"]
        let model = make(service, reader)
        await model.load()
        await model.findFriends()
        XCTAssertNotNil(model.message)
        XCTAssertNil(model.matches)
    }

    func testGoogleOnlyAccountIsFlagged() async {
        let service = FakeContacts()
        service.state = ContactsFindableResponse(findable: false, canBeFound: false)
        let model = make(service, FakeReader())
        await model.load()
        XCTAssertFalse(model.canBeFound)
    }

    func testContactActionPrefersLocalAdd() {
        let match = ContactMatchResponse(userId: "u1", displayName: "A", relationship: .none)
        XCTAssertEqual(contactAction(match, sent: [:]), .add)
        XCTAssertEqual(contactAction(match, sent: ["u1": .pending]), .requestSent)
        XCTAssertEqual(contactAction(ContactMatchResponse(userId: "u2", relationship: .friends), sent: [:]), .friends)
        XCTAssertEqual(contactAction(ContactMatchResponse(userId: "u3", relationship: .requestReceived), sent: [:]), .nothing)
    }

    func testContactActionUsesFriendsListAfterAccepting() {
        let match = ContactMatchResponse(userId: "u3", relationship: .requestReceived)
        XCTAssertEqual(contactAction(match, sent: [:], friendIds: ["u3"]), .friends)
        XCTAssertEqual(contactAction(match, sent: [:], friendIds: []), .nothing)
    }

    func testLaterCallFailureKeepsEarlierMatchesAndShowsError() async {
        let service = FakeContacts()
        service.state.findable = true
        service.failFromCall = 2
        service.matchesByCall = [[ContactMatchResponse(userId: "u1", displayName: "Ann", relationship: .none)]]
        let reader = FakeReader()
        reader.addresses = (0 ..< 700).map { "c\($0)@x.com" }
        let model = make(service, reader)
        await model.load()
        await model.findFriends()
        XCTAssertEqual(service.sentBatches.count, 2)
        XCTAssertEqual(model.matches?.map { $0.userId }, ["u1"])
        XCTAssertNotNil(model.message)
    }

    func testMatchesSortIgnoringCase() async {
        let service = FakeContacts()
        service.state.findable = true
        service.matchesByCall = [[
            ContactMatchResponse(userId: "u1", displayName: "Carl", relationship: .none),
            ContactMatchResponse(userId: "u2", displayName: "bob", relationship: .none),
        ]]
        let reader = FakeReader()
        reader.addresses = ["a@x.com"]
        let model = make(service, reader)
        await model.load()
        await model.findFriends()
        XCTAssertEqual(model.matches?.map { $0.displayName }, ["bob", "Carl"])
    }
}
