import XCTest
import QModel
import QNetwork
@testable import QFeatures

private struct Boom: Error {}

private actor FakeCourseService: OnboardingService {
    var calls: [String] = []
    var catalogResult: Result<[CourseCatalogEntry], Error> = .success([])
    var failEnroll = false
    var failSwitch = false
    var delayNanos: UInt64 = 0

    func setCatalog(_ r: Result<[CourseCatalogEntry], Error>) { catalogResult = r }
    func setFailEnroll(_ v: Bool) { failEnroll = v }
    func setFailSwitch(_ v: Bool) { failSwitch = v }
    func setDelay(_ nanos: UInt64) { delayNanos = nanos }

    private var enrolledNow: [String] = []
    func seed(_ codes: [String]) { enrolledNow = codes }

    func catalog() async throws -> [CourseCatalogEntry] { try catalogResult.get() }

    func setDisplayName(_ displayName: String) async throws -> ProfileResponse {
        ProfileResponse(displayName: displayName)
    }

    func enrollAll(courseCodes: [String], active: String) async throws -> BootstrapResponse {
        BootstrapResponse(graders: [], enrolledCourseCodes: courseCodes, onboardingComplete: true)
    }

    func completeOnboarding() async throws -> Bool { true }

    func enroll(courseCode: String) async throws -> BootstrapResponse {
        calls.append("enroll:\(courseCode)")
        if delayNanos > 0 { try await Task.sleep(nanoseconds: delayNanos) }
        if failEnroll { throw Boom() }
        if !enrolledNow.contains(courseCode) { enrolledNow.append(courseCode) }
        return BootstrapResponse(graders: [], enrolledCourseCodes: enrolledNow, onboardingComplete: true)
    }

    func switchActive(courseCode: String) async throws -> BootstrapResponse {
        calls.append("switch:\(courseCode)")
        if delayNanos > 0 { try await Task.sleep(nanoseconds: delayNanos) }
        if failSwitch { throw Boom() }
        return BootstrapResponse(
            course: CourseRef(code: courseCode, version: 1, manifestSha256: "h"),
            graders: [], enrolledCourseCodes: enrolledNow, onboardingComplete: true)
    }
}

@MainActor
private final class Seen {
    var bootstraps: [BootstrapResponse] = []
}

@MainActor
final class CourseSwitcherModelTests: XCTestCase {
    private func entry(_ code: String, _ name: String) -> CourseCatalogEntry {
        CourseCatalogEntry(code: code, nativeName: name, latinName: name, cultureFacts: [])
    }

    private func start(
        _ fake: FakeCourseService, enrolled: [String] = ["fa", "ja"], active: String = "fa", seen: Seen? = nil
    ) async -> CourseSwitcherModel {
        await fake.seed(enrolled)
        await fake.setCatalog(.success([entry("fa", "Persian"), entry("ja", "Japanese"), entry("es", "Spanish")]))
        let boot = BootstrapResponse(
            course: CourseRef(code: active, version: 1, manifestSha256: "h"),
            graders: [], enrolledCourseCodes: enrolled, onboardingComplete: true)
        let model = CourseSwitcherModel(service: fake, bootstrap: boot, onBootstrap: { seen?.bootstraps.append($0) })
        await model.loadCatalog()
        return model
    }

    func testEnrolledUsesCatalogNamesAndMarksActive() async {
        let model = await start(FakeCourseService())
        XCTAssertEqual(model.enrolled.map(\.name), ["Persian", "Japanese"])
        XCTAssertEqual(model.enrolled.map(\.isActive), [true, false])
    }

    func testNameFallsBackToUppercasedCodeWhenCatalogFails() async {
        let fake = FakeCourseService()
        let model = await start(fake)
        let bare = CourseSwitcherModel(
            service: fake,
            bootstrap: BootstrapResponse(graders: [], enrolledCourseCodes: ["fa"], onboardingComplete: true))
        await fake.setCatalog(.failure(Boom()))
        await bare.loadCatalog()
        XCTAssertEqual(bare.enrolled.map(\.name), ["FA"])
        XCTAssertNil(bare.error)
        XCTAssertEqual(model.enrolled.count, 2)
    }

    func testAddableIsCatalogMinusEnrolled() async {
        let model = await start(FakeCourseService())
        XCTAssertEqual(model.addable.map(\.code), ["es"])
    }

    func testSwitchCallsServiceAndHandsBootstrapOn() async {
        let fake = FakeCourseService()
        let seen = Seen()
        let model = await start(fake, seen: seen)
        await model.switchTo("ja")
        let calls = await fake.calls
        XCTAssertEqual(calls, ["switch:ja"])
        XCTAssertEqual(model.activeCode, "ja")
        XCTAssertEqual(seen.bootstraps.count, 1)
        XCTAssertFalse(model.isBusy)
    }

    func testSwitchToActiveIsNoOp() async {
        let fake = FakeCourseService()
        let model = await start(fake)
        await model.switchTo("fa")
        let calls = await fake.calls
        XCTAssertEqual(calls, [])
    }

    func testSwitchFailureShowsFallbackAndKeepsCourse() async {
        let fake = FakeCourseService()
        let model = await start(fake)
        await fake.setFailSwitch(true)
        await model.switchTo("ja")
        XCTAssertEqual(model.error, CourseSwitcherRules.switchFallback)
        XCTAssertEqual(model.activeCode, "fa")
        XCTAssertFalse(model.isBusy)
    }

    func testAddEnrollsThenSwitches() async {
        let fake = FakeCourseService()
        let seen = Seen()
        let model = await start(fake, seen: seen)
        await model.addCourse("es")
        let calls = await fake.calls
        XCTAssertEqual(calls, ["enroll:es", "switch:es"])
        XCTAssertEqual(model.activeCode, "es")
        XCTAssertEqual(model.addable, [])
        XCTAssertEqual(seen.bootstraps.count, 2)
    }

    func testAddFailureShowsFallbackAndSkipsSwitch() async {
        let fake = FakeCourseService()
        let model = await start(fake)
        await fake.setFailEnroll(true)
        await model.addCourse("es")
        let calls = await fake.calls
        XCTAssertEqual(calls, ["enroll:es"])
        XCTAssertEqual(model.error, CourseSwitcherRules.addFallback)
    }

    func testAddAlreadyEnrolledIsNoOp() async {
        let fake = FakeCourseService()
        let model = await start(fake)
        await model.addCourse("ja")
        let calls = await fake.calls
        XCTAssertEqual(calls, [])
    }

    func testSecondCallWhileBusyIsIgnored() async {
        let fake = FakeCourseService()
        let model = await start(fake)
        await fake.setDelay(100_000_000)
        let first = Task { await model.switchTo("ja") }
        await Task.yield()
        XCTAssertTrue(model.isBusy)
        await model.addCourse("es")
        await first.value
        let calls = await fake.calls
        XCTAssertEqual(calls, ["switch:ja"])
    }
}
