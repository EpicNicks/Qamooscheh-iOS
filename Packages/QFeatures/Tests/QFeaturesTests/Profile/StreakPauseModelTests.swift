import XCTest
import QModel
import QNetwork
@testable import QFeatures

private final class PauseFake: StreakService, @unchecked Sendable {
    private let lock = NSLock()
    var streak: StreakResponse
    var pauseFailure: Error?
    var cancelFailure: Error?
    var fetchFailure: Error?
    private(set) var pauses: [StreakPauseRequest] = []
    private(set) var cancels = 0
    private(set) var fetches = 0

    init(streak: StreakResponse) { self.streak = streak }

    func fetch() async throws -> StreakResponse {
        lock.lock(); fetches += 1; lock.unlock()
        if let failure = fetchFailure { throw failure }
        return streak
    }

    func pause(_ request: StreakPauseRequest) async throws {
        lock.lock(); pauses.append(request); lock.unlock()
        if let failure = pauseFailure { throw failure }
        streak.pause = StreakPauseResponse(startDay: request.startDay, endDay: request.endDay, started: false)
    }

    func cancelPause() async throws {
        lock.lock(); cancels += 1; lock.unlock()
        if let failure = cancelFailure { throw failure }
        streak.pause = nil
    }
}

private func pauseStreak(available: Int = 10, pause: StreakPauseResponse? = nil) -> StreakResponse {
    StreakResponse(
        currentStreakDays: 4, longestStreakDays: 9, practicedToday: false, pausedToday: false,
        pause: pause, pauseDaysAvailable: available, timeZone: "UTC", dayStartHour: 3,
        today: "2026-10-12", nextDayStartsAt: Date(timeIntervalSince1970: 1_791_774_000))
}

final class StreakPauseProblemTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_700_000)

    func testAcceptsAWindowInBounds() {
        XCTAssertNil(streakPauseProblem(streak: pauseStreak(), startDay: "2026-10-12", days: 3, now: now))
        XCTAssertNil(streakPauseProblem(streak: pauseStreak(), startDay: "2026-11-11", days: 10, now: now))
    }

    func testRejectsBadDaysAndStarts() {
        let s = pauseStreak(available: 5)
        XCTAssertNotNil(streakPauseProblem(streak: s, startDay: "2026-10-12", days: 0, now: now))
        XCTAssertNotNil(streakPauseProblem(streak: s, startDay: "2026-10-12", days: 6, now: now))
        XCTAssertNotNil(streakPauseProblem(streak: s, startDay: "2026-10-11", days: 2, now: now))
        XCTAssertNotNil(streakPauseProblem(streak: s, startDay: "2026-11-12", days: 2, now: now))
        XCTAssertNotNil(streakPauseProblem(streak: s, startDay: "2026-13-40", days: 2, now: now))
        XCTAssertNotNil(streakPauseProblem(streak: s, startDay: "tomorrow", days: 2, now: now))
        XCTAssertNotNil(streakPauseProblem(streak: pauseStreak(available: 0), startDay: "2026-10-12", days: 1, now: now))
    }
}

@MainActor
final class StreakPauseModelTests: XCTestCase {
    private func makeModel(_ fake: PauseFake) -> StreakPauseModel {
        StreakPauseModel(service: fake, now: { Date(timeIntervalSince1970: 1_791_700_000) })
    }

    func testBookSendsInclusiveWindowAndRefetches() async {
        let fake = PauseFake(streak: pauseStreak())
        let model = makeModel(fake)
        await model.load()
        await model.book(startDay: "2026-10-13", days: 3)
        XCTAssertEqual(fake.pauses, [StreakPauseRequest(startDay: "2026-10-13", endDay: "2026-10-15")])
        XCTAssertEqual(model.pause?.endDay, "2026-10-15")
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.error)
    }

    func testInvalidBookingNeverReachesTheService() async {
        let fake = PauseFake(streak: pauseStreak(available: 2))
        let model = makeModel(fake)
        await model.load()
        await model.book(startDay: "2026-10-13", days: 5)
        XCTAssertTrue(fake.pauses.isEmpty)
        XCTAssertNotNil(model.error)
        XCTAssertFalse(model.busy)
    }

    func testServerMessageSurfacesAndStreakRefetches() async {
        let fake = PauseFake(streak: pauseStreak())
        fake.pauseFailure = ApiError(status: 409, body: ApiErrorBody(error: "A pause is already booked."))
        let model = makeModel(fake)
        await model.load()
        let before = fake.fetches
        await model.book(startDay: "2026-10-13", days: 2)
        XCTAssertEqual(model.error, "A pause is already booked.")
        XCTAssertEqual(fake.fetches, before + 1)
        XCTAssertFalse(model.busy)
    }

    func testGenericFailureUsesFallback() async {
        let fake = PauseFake(streak: pauseStreak())
        fake.pauseFailure = ApiError(status: 500, body: nil)
        let model = makeModel(fake)
        await model.load()
        await model.book(startDay: "2026-10-13", days: 2)
        XCTAssertEqual(model.error, "Couldn't pause your streak.")
    }

    func testCancelClearsPauseAndAnErrorClearsOnNextAction() async {
        let fake = PauseFake(streak: pauseStreak(pause: StreakPauseResponse(startDay: "2026-10-13", endDay: "2026-10-15", started: false)))
        let model = makeModel(fake)
        await model.load()
        fake.cancelFailure = ApiError(status: 500, body: nil)
        await model.cancel()
        XCTAssertEqual(model.error, "Couldn't cancel the pause.")
        XCTAssertNotNil(model.pause)
        fake.cancelFailure = nil
        await model.cancel()
        XCTAssertNil(model.error)
        XCTAssertNil(model.pause)
        XCTAssertEqual(fake.cancels, 2)
    }

    func testWithoutServiceNothingHappens() async {
        let model = StreakPauseModel(service: nil)
        await model.book(startDay: "2026-10-13", days: 2)
        await model.cancel()
        XCTAssertNil(model.streak)
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.error)
    }
}
