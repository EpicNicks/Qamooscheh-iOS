import XCTest
import QModel
@testable import QFeatures

private final class FakeProfileService: ProfileService, @unchecked Sendable {
    var stored = ProfileResponse(displayName: "Nick", fullName: nil, country: "CA")
    var fetchFails = false
    var saveFails = false
    var saved: [UpdateProfileRequest] = []

    func fetch() async throws -> ProfileResponse {
        if fetchFails { throw URLError(.notConnectedToInternet) }
        return stored
    }

    func save(_ request: UpdateProfileRequest) async throws -> ProfileResponse {
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
        XCTAssertEqual(model.saveError, "Couldn't save your profile.")
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
}
