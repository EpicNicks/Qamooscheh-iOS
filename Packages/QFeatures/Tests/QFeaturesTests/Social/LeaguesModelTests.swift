import XCTest
import QModel
import QNetwork
@testable import QFeatures

private func league(_ tier: Int, _ n: Int) -> CurrentLeagueResponse {
    var rows: [LeagueStandingResponse] = []
    for i in 0..<n {
        rows.append(LeagueStandingResponse(userId: "U\(i)", displayName: i == 2 ? nil : "n\(i)", points: 100 - i))
    }
    return CurrentLeagueResponse(tier: tier, periodEndsAt: Date(timeIntervalSince1970: 1_000), standings: rows)
}

private final class FakeLeague: LeagueService, @unchecked Sendable {
    var result: CurrentLeagueResponse?
    var error: Error?
    var calls = 0
    /// Runs inside the call, before it returns (to start a second refresh).
    var during: (@MainActor (Int) async -> Void)?

    func current() async throws -> CurrentLeagueResponse? {
        calls += 1
        let n = calls
        let snapshot = result
        if let hook = during { await hook(n) }
        if let e = error { throw e }
        return snapshot
    }
}

@MainActor
final class LeaguesModelTests: XCTestCase {
    func testSplitCounts() {
        XCTAssertEqual(LeagueSplit.counts(cohortSize: 13).promote, 7)
        XCTAssertEqual(LeagueSplit.counts(cohortSize: 13).demote, 3)
        XCTAssertEqual(LeagueSplit.counts(cohortSize: 0).promote, 0)
        // A cohort of one: promote 1, demotions shrink to 0.
        XCTAssertEqual(LeagueSplit.counts(cohortSize: 1).promote, 1)
        XCTAssertEqual(LeagueSplit.counts(cohortSize: 1).demote, 0)
        XCTAssertEqual(LeagueSplit.counts(cohortSize: 2).promote, 1)
        XCTAssertEqual(LeagueSplit.counts(cohortSize: 2).demote, 1)
        // 6 * 7 / 13 = 3.23 -> 3; 6 * 3 / 13 = 1.38 -> 1.
        XCTAssertEqual(LeagueSplit.counts(cohortSize: 6).promote, 3)
        XCTAssertEqual(LeagueSplit.counts(cohortSize: 6).demote, 1)
        XCTAssertEqual(LeagueSplit.outcome(rank: 7, cohortSize: 13), .promoted)
        XCTAssertEqual(LeagueSplit.outcome(rank: 8, cohortSize: 13), .held)
        XCTAssertEqual(LeagueSplit.outcome(rank: 10, cohortSize: 13), .held)
        XCTAssertEqual(LeagueSplit.outcome(rank: 11, cohortSize: 13), .demoted)
    }

    func testRowsMarkViewerCaseInsensitivelyAndFloorHoldsDemotion() {
        let ui = makeLeagueUi(league(0, 13), viewerId: "u12")
        XCTAssertEqual(ui.rows.filter { $0.isMe }.map { $0.rank }, [13])
        XCTAssertFalse(ui.rows.contains { $0.outcome == .demoted })
        XCTAssertEqual(ui.rows[12].outcome, .held)
        let upper = makeLeagueUi(league(1, 13), viewerId: nil)
        XCTAssertEqual(upper.rows[12].outcome, .demoted)
        XCTAssertTrue(upper.rows.allSatisfy { !$0.isMe })
        XCTAssertNil(upper.rows[2].displayName)
    }

    func testFormatRemaining() {
        XCTAssertEqual(formatRemaining(seconds: 0), "This period has ended. Results are on the way.")
        XCTAssertEqual(formatRemaining(seconds: -5), "This period has ended. Results are on the way.")
        XCTAssertEqual(formatRemaining(seconds: 59), "0m 59s left")
        XCTAssertEqual(formatRemaining(seconds: 3_725), "1h 2m left")
        XCTAssertEqual(formatRemaining(seconds: 2 * 86_400 + 5 * 3_600 + 99), "2d 5h left")
    }

    func testReadyAndNoLeague() async {
        let fake = FakeLeague()
        fake.result = league(1, 3)
        let model = LeaguesModel(service: fake, viewerId: "u0")
        await model.refresh()
        guard case .ready(let ui) = model.state else { return XCTFail("expected ready") }
        XCTAssertEqual(ui.tier, 1)
        XCTAssertTrue(ui.rows[0].isMe)
        fake.result = nil
        await model.refresh()
        XCTAssertEqual(model.state, .noLeague)
    }

    func testFailureSurfacesServerMessageAndReload() async {
        let fake = FakeLeague()
        fake.error = ApiError(status: 500, body: ApiErrorBody(error: "Leagues are down"))
        let model = LeaguesModel(service: fake, viewerId: nil)
        await model.refresh()
        XCTAssertEqual(model.state, .failed("Leagues are down"))
        fake.error = nil
        fake.result = league(1, 2)
        await model.refresh()
        if case .ready = model.state {} else { XCTFail("expected ready after retry") }
    }

    func testUnauthorizedIsObservable() async {
        let fake = FakeLeague()
        fake.error = ApiError(status: 401, body: nil)
        let box = Counter()
        let model = LeaguesModel(service: fake, viewerId: nil, onUnauthorized: { box.bump() })
        await model.refresh()
        XCTAssertEqual(box.count, 1)
    }

    func testReloadKeepsStandingsAndStaleResultNeverOverwritesNewer() async {
        let fake = FakeLeague()
        fake.result = league(1, 3)
        let model = LeaguesModel(service: fake, viewerId: nil)
        await model.refresh()
        // The first (slow) call starts a second refresh that finishes first with newer data.
        fake.result = league(1, 3)
        fake.during = { n in
            if n == 2 {
                fake.during = nil
                fake.result = league(5, 3)
                await model.refresh()
                fake.result = league(1, 3)
            }
        }
        await model.refresh()
        guard case .ready(let ui) = model.state else { return XCTFail("expected ready") }
        XCTAssertEqual(ui.tier, 5)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func bump() { lock.lock(); value += 1; lock.unlock() }
}
