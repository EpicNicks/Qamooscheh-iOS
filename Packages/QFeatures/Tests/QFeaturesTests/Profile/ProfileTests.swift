import XCTest
import QModel
import QNetwork
import QDomain
@testable import QFeatures

private final class FakeProfileService: ProfileService, @unchecked Sendable {
    var stored = ProfileResponse(displayName: "Nick", fullName: nil, country: "CA")
    var fetchFails = false
    var saveFails = false
    var saveError: Error?
    var fetchError: Error?
    var fetchCount = 0
    var onSave: (() -> Void)?
    var saved: [UpdateProfileRequest] = []

    func fetch() async throws -> ProfileResponse {
        fetchCount += 1
        if let e = fetchError { throw e }
        if fetchFails { throw URLError(.notConnectedToInternet) }
        return stored
    }

    func save(_ request: UpdateProfileRequest) async throws -> ProfileResponse {
        onSave?()
        if let e = saveError { throw e }
        if saveFails { throw URLError(.notConnectedToInternet) }
        saved.append(request)
        stored = ProfileResponse(displayName: request.displayName, fullName: request.fullName, country: request.country)
        return stored
    }
}

final class ProfileLogicTests: XCTestCase {
    func testClampUppercasesAndCaps() {
        let form = ProfileForm(displayName: String(repeating: "a", count: 60), fullName: String(repeating: "b", count: 130), country: "usa").clamped()
        XCTAssertEqual(form.displayName.count, 40)
        XCTAssertEqual(form.fullName.count, 100)
        XCTAssertEqual(form.country, "US")
    }

    func testFormErrors() {
        XCTAssertEqual(profileFormError(ProfileForm(displayName: "  ")), "A display name is required.")
        XCTAssertEqual(profileFormError(ProfileForm(displayName: "N", country: "U")), "Country must be a 2-letter code, e.g. US.")
        XCTAssertEqual(profileFormError(ProfileForm(displayName: "N", country: "u1")), "Country must be a 2-letter code, e.g. US.")
        XCTAssertNil(profileFormError(ProfileForm(displayName: "N", country: "US")))
        XCTAssertNil(profileFormError(ProfileForm(displayName: "N")))
    }

    func testRequestBlanksBecomeNil() {
        let r = profileRequest(ProfileForm(displayName: " Nick ", fullName: "  ", country: ""))
        XCTAssertEqual(r, UpdateProfileRequest(displayName: "Nick", fullName: nil, country: nil))
    }

    func testRecentActivityFillsGaps() {
        let days = [ActivityDay(localDay: "2026-10-12", reviews: 1, xp: 50), ActivityDay(localDay: "2026-10-08", reviews: 1, xp: 20)]
        let week = recentActivity(days, today: "2026-10-12")
        XCTAssertEqual(week.map { $0.day }, ["2026-10-06", "2026-10-07", "2026-10-08", "2026-10-09", "2026-10-10", "2026-10-11", "2026-10-12"])
        XCTAssertEqual(week.map { $0.xp }, [0, 0, 20, 0, 0, 0, 50])
    }

    func testRecentActivityAcrossMonthBoundary() {
        let week = recentActivity([], today: "2026-03-02", count: 3)
        XCTAssertEqual(week.map { $0.day }, ["2026-02-28", "2026-03-01", "2026-03-02"])
    }

    func testBarFraction() {
        XCTAssertEqual(barFraction(xp: 0, peak: 100), 0.02, accuracy: 0.0001)
        XCTAssertEqual(barFraction(xp: 1, peak: 1000), 0.04, accuracy: 0.0001)
        XCTAssertEqual(barFraction(xp: 50, peak: 100), 0.5, accuracy: 0.0001)
        XCTAssertEqual(barFraction(xp: 500, peak: 100), 1.0, accuracy: 0.0001)
        XCTAssertEqual(barFraction(xp: 0, peak: 0), 0.02, accuracy: 0.0001)
    }

    func testStudyingLine() {
        XCTAssertNil(studyingLine(courseCode: nil, enrolledCount: 2))
        XCTAssertEqual(studyingLine(courseCode: "fa", enrolledCount: 1), "Studying Persian")
        XCTAssertEqual(studyingLine(courseCode: "fa", enrolledCount: 3), "Studying Persian and 2 more")
        XCTAssertEqual(studyingLine(courseCode: "xx", enrolledCount: 1), "Studying XX")
    }

    func testWeekdayShort() {
        XCTAssertEqual(weekdayShort("2026-10-12", locale: Locale(identifier: "en_US_POSIX")), "Mon")
        XCTAssertEqual(weekdayShort("garbage", locale: Locale(identifier: "en_US_POSIX")), "garbage")
    }
}

@MainActor
final class ProfileModelTests: XCTestCase {
    func testLoadFillsForm() async {
        let model = ProfileModel(service: FakeProfileService())
        await model.load()
        XCTAssertEqual(model.form, ProfileForm(displayName: "Nick", fullName: "", country: "CA"))
        XCTAssertNil(model.loadError)
    }

    func testLoadFailureThenRetry() async {
        let service = FakeProfileService()
        service.fetchFails = true
        let model = ProfileModel(service: service)
        await model.load()
        XCTAssertNil(model.form)
        XCTAssertNotNil(model.loadError)
        service.fetchFails = false
        await model.loadProfile()
        XCTAssertNil(model.loadError)
        XCTAssertNotNil(model.form)
    }

    func testSaveSendsAndMarksSaved() async {
        let service = FakeProfileService()
        let model = ProfileModel(service: service)
        await model.load()
        model.edit { $0.country = "us"; $0.fullName = "Nicholas" }
        await model.save()
        XCTAssertEqual(service.saved.last, UpdateProfileRequest(displayName: "Nick", fullName: "Nicholas", country: "US"))
        XCTAssertTrue(model.saved)
        model.edit { $0.displayName = "Nicky" }
        XCTAssertFalse(model.saved)
    }

    func testInvalidFormIsNotSent() async {
        let service = FakeProfileService()
        let model = ProfileModel(service: service)
        await model.load()
        model.edit { $0.displayName = "" }
        await model.save()
        XCTAssertEqual(model.saveError, "A display name is required.")
        XCTAssertTrue(service.saved.isEmpty)
        model.edit { $0.displayName = "N" }
        XCTAssertNil(model.saveError)
    }

    func testSaveFailureKeepsDraft() async {
        let service = FakeProfileService()
        service.saveFails = true
        let model = ProfileModel(service: service)
        await model.load()
        model.edit { $0.displayName = "Changed" }
        await model.save()
        XCTAssertEqual(model.saveError, AuthRules.offline)
        XCTAssertEqual(model.form?.displayName, "Changed")
        XCTAssertFalse(model.saved)
        XCTAssertFalse(model.saving)
    }

    func testSignOutErrorAndSuccess() async {
        struct Boom: Error {}
        let failing = ProfileModel(service: nil, signOut: { throw Boom() })
        await failing.signOut()
        XCTAssertEqual(failing.signOutError, "Couldn't sign out.")
        XCTAssertFalse(failing.signingOut)
        let ok = ProfileModel(service: nil, signOut: {})
        await ok.signOut()
        XCTAssertNil(ok.signOutError)
    }

    func testTotalXp() {
        let context = ProfileContext(courseCode: "fa", enrolledCount: 1, activity: [ActivityDay(localDay: "2026-10-12", reviews: 1, xp: 30), ActivityDay(localDay: "2026-10-11", reviews: 1, xp: 20)])
        XCTAssertEqual(ProfileModel(service: nil, context: context).totalXpValue, 50)
    }

    func testReloadKeepsDraft() async {
        let service = FakeProfileService()
        let model = ProfileModel(service: service)
        await model.load()
        model.edit { $0.displayName = "Typed" }
        await model.load()
        await model.loadProfile()
        XCTAssertEqual(model.form?.displayName, "Typed")
        XCTAssertEqual(service.fetchCount, 1)
    }

    func testFailedStreakRefreshKeepsLastGood() async {
        let service = FakeStreakService(streak: sampleStreak())
        let model = ProfileModel(service: FakeProfileService(), streakService: service)
        await model.load()
        XCTAssertEqual(model.streak?.currentStreakDays, 4)
        service.streak = nil
        await model.load()
        XCTAssertEqual(model.streak?.currentStreakDays, 4)
    }

    func testTodayFallbackRespectsLastDayStart() async {
        let now = Date(timeIntervalSince1970: 1_791_856_800)
        let none = ProfileModel(service: nil)
        XCTAssertEqual(none.today(now: now), todayLocalDay(now: now, calendar: .current))
        let model = ProfileModel(service: nil, streakService: FakeStreakService(streak: sampleStreak(dayStartHour: 3)))
        await model.load()
        XCTAssertEqual(model.today(now: Date(timeIntervalSince1970: 1_791_774_000 + 86_400 + 60)), "2026-10-13")
    }

    func testEditDuringSaveKeepsNewerEditsAndSaysSaved() async {
        let service = FakeProfileService()
        let model = ProfileModel(service: service)
        await model.load()
        model.edit { $0.fullName = "Full" }
        service.onSave = { [unowned model] in
            MainActor.assumeIsolated { model.edit { $0.displayName = "Newer" } }
        }
        await model.save()
        XCTAssertEqual(model.form, ProfileForm(displayName: "Newer", fullName: "Full", country: "CA"))
        XCTAssertTrue(model.savedWithNewerEdits)
        XCTAssertFalse(model.saved)
        model.edit { $0.country = "US" }
        XCTAssertFalse(model.savedWithNewerEdits)
    }

    func testServerMessageShownAndUnauthorizedReported() async {
        let service = FakeProfileService()
        service.saveError = ApiError(status: 400, body: ApiErrorBody(error: "Display name is taken."))
        let model = ProfileModel(service: service)
        await model.load()
        await model.save()
        XCTAssertEqual(model.saveError, "Display name is taken.")

        let box = CallBox()
        let unauthorized = FakeProfileService()
        unauthorized.saveError = ApiError(status: 401, body: nil)
        let m2 = ProfileModel(service: unauthorized, onUnauthorized: { box.hit() })
        await m2.load()
        await m2.save()
        XCTAssertEqual(box.count, 1)
        unauthorized.fetchError = ApiError(status: 401, body: nil)
        let m3 = ProfileModel(service: unauthorized, onUnauthorized: { box.hit() })
        await m3.load()
        XCTAssertEqual(box.count, 2)
        XCTAssertNotNil(m3.loadError)
    }

    func testSignOutStaysBusyAfterSuccess() async {
        let box = CallBox()
        let model = ProfileModel(service: nil, signOut: { box.hit() })
        await model.signOut()
        await model.signOut()
        XCTAssertEqual(box.count, 1)
        XCTAssertTrue(model.signingOut)
    }
}

private final class CallBox: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func hit() { lock.lock(); n += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return n }
}

private final class FakeStreakService: StreakService, @unchecked Sendable {
    var streak: StreakResponse?
    init(streak: StreakResponse?) { self.streak = streak }
    func fetch() async throws -> StreakResponse {
        guard let streak = streak else { throw URLError(.notConnectedToInternet) }
        return streak
    }
    func pause(_ request: StreakPauseRequest) async throws {}
    func cancelPause() async throws {}
}

private func sampleStreak(dayStartHour: Int = 3) -> StreakResponse {
    StreakResponse(
        currentStreakDays: 4, longestStreakDays: 9, practicedToday: false, pausedToday: false,
        pauseDaysAvailable: 10, timeZone: "UTC", dayStartHour: dayStartHour,
        today: "2026-10-12", nextDayStartsAt: Date(timeIntervalSince1970: 1_791_774_000))  // 2026-10-12T03:00:00Z

}

final class CurrentStreakDayTests: XCTestCase {
    func testAdvancesPastNextDayStart() {
        let streak = sampleStreak()
        let next = streak.nextDayStartsAt
        XCTAssertEqual(currentStreakDay(streak, now: next.addingTimeInterval(-60)), "2026-10-12")
        XCTAssertEqual(currentStreakDay(streak, now: next), "2026-10-13")
        XCTAssertEqual(currentStreakDay(streak, now: next.addingTimeInterval(86_400 + 5)), "2026-10-14")
    }

    func testUnparseableTodayUsesDayStartShift() {
        var streak = sampleStreak()
        streak.today = "garbled"
        // 01:00 UTC on 2026-10-13, 3am day start: still the 12th.
        let now = Date(timeIntervalSince1970: 1_791_853_200)
        XCTAssertEqual(currentStreakDay(streak, now: now), "2026-10-12")
    }
}
