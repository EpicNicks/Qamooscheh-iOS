import XCTest
import QModel
import QNetwork
@testable import QFeatures

private actor FakeOnboardingService: OnboardingService {
    var names: [String] = []
    var enrollCalls: [([String], String)] = []
    var completeCalls = 0
    var catalogCalls = 0
    var catalogResult: Result<[CourseCatalogEntry], Error> = .success([])
    var nameResult: Result<Void, Error> = .success(())
    var enrollResult: Result<Void, Error> = .success(())
    var completeResult: Result<Bool, Error> = .success(true)
    var delayNanos: UInt64 = 0

    func setCatalog(_ r: Result<[CourseCatalogEntry], Error>) { catalogResult = r }
    func setName(_ r: Result<Void, Error>) { nameResult = r }
    func setEnroll(_ r: Result<Void, Error>) { enrollResult = r }
    func setComplete(_ r: Result<Bool, Error>) { completeResult = r }
    func setDelay(_ nanos: UInt64) { delayNanos = nanos }

    private func pause() async throws {
        if delayNanos > 0 { try await Task.sleep(nanoseconds: delayNanos) }
    }

    func catalog() async throws -> [CourseCatalogEntry] {
        catalogCalls += 1
        return try catalogResult.get()
    }

    func setDisplayName(_ displayName: String) async throws -> ProfileResponse {
        names.append(displayName)
        try await pause()
        try nameResult.get()
        return ProfileResponse(displayName: displayName)
    }

    func enrollAll(courseCodes: [String], active: String) async throws -> BootstrapResponse {
        enrollCalls.append((courseCodes, active))
        try await pause()
        try enrollResult.get()
        return BootstrapResponse(
            course: CourseRef(code: active, version: 1, manifestSha256: "h"),
            graders: [], enrolledCourseCodes: courseCodes, onboardingComplete: false)
    }

    func completeOnboarding() async throws -> Bool {
        completeCalls += 1
        try await pause()
        return try completeResult.get()
    }
}

@MainActor
private final class Recorder {
    var bootstraps: [BootstrapResponse] = []
    var completions: [Bool] = []
}

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    private func make(
        _ fake: FakeOnboardingService,
        store: OnboardingStepStore = InMemoryOnboardingStepStore(),
        recorder: Recorder? = nil
    ) -> OnboardingViewModel {
        let recorder = recorder ?? Recorder()
        return OnboardingViewModel(
            service: fake, stepStore: store,
            onBootstrap: { recorder.bootstraps.append($0) },
            onComplete: { recorder.completions.append($0) })
    }

    private func entry(_ code: String) -> CourseCatalogEntry {
        CourseCatalogEntry(code: code, nativeName: code, latinName: code, cultureFacts: [])
    }

    private func toLanguages(_ vm: OnboardingViewModel) async {
        vm.displayName = "Sara"
        await vm.submitName()
    }

    private func toTutorial(_ vm: OnboardingViewModel) async {
        await toLanguages(vm)
        await vm.startLearning(courseCodes: ["fa"])
    }

    // MARK: order and name step

    func testStepOrderIsNameLanguagesTutorial() {
        XCTAssertEqual(OnboardingStep.allCases, [.name, .languages, .tutorial])
        XCTAssertEqual(make(FakeOnboardingService()).step, .name)
    }

    func testBlankNameIsSilentNoOp() async {
        let fake = FakeOnboardingService()
        let vm = make(fake)
        vm.displayName = "   "
        XCTAssertFalse(vm.canSubmitName)
        await vm.submitName()
        XCTAssertEqual(vm.step, .name)
        XCTAssertNil(vm.error)
        let names = await fake.names
        XCTAssertEqual(names, [])
    }

    func testNameIsTrimmedSavedAndAdvances() async {
        let fake = FakeOnboardingService()
        let store = InMemoryOnboardingStepStore()
        let vm = make(fake, store: store)
        vm.displayName = "  Sara "
        await vm.submitName()
        let names = await fake.names
        XCTAssertEqual(names, ["Sara"])
        XCTAssertEqual(vm.step, .languages)
        XCTAssertEqual(store.step, .languages)
        XCTAssertNil(vm.error)
        XCTAssertFalse(vm.isSubmitting)
    }

    func testNameIsCappedAtForty() {
        let vm = make(FakeOnboardingService())
        vm.displayName = String(repeating: "x", count: 60)
        XCTAssertEqual(vm.displayName.count, 40)
    }

    func testNameFailureShowsFallbackStaysAndEditingClearsIt() async {
        let fake = FakeOnboardingService()
        await fake.setName(.failure(ApiError(status: 400, body: nil)))
        let vm = make(fake)
        vm.displayName = "Sara"
        await vm.submitName()
        XCTAssertEqual(vm.error, OnboardingRules.nameFallback)
        XCTAssertEqual(vm.step, .name)
        vm.displayName = "Sarah"
        XCTAssertNil(vm.error)
        await fake.setName(.success(()))
        await vm.submitName()
        XCTAssertEqual(vm.step, .languages)
    }

    func testServerMessageAndOfflineAreShown() async {
        let fake = FakeOnboardingService()
        await fake.setName(.failure(ApiError(status: 400, body: ApiErrorBody(error: "Name taken."))))
        let vm = make(fake)
        vm.displayName = "Sara"
        await vm.submitName()
        XCTAssertEqual(vm.error, "Name taken.")
        await fake.setName(.failure(URLError(.notConnectedToInternet)))
        await vm.submitName()
        XCTAssertEqual(vm.error, AuthRules.offline)
    }

    func testDoubleNameSubmitIsGuarded() async {
        let fake = FakeOnboardingService()
        await fake.setDelay(50_000_000)
        let vm = make(fake)
        vm.displayName = "Sara"
        async let first: Void = vm.submitName()
        async let second: Void = vm.submitName()
        _ = await (first, second)
        let names = await fake.names
        XCTAssertEqual(names.count, 1)
        XCTAssertEqual(vm.step, .languages)
    }

    func testSubmittingIsObservableAndBlocksSubmit() async {
        let fake = FakeOnboardingService()
        await fake.setDelay(100_000_000)
        let vm = make(fake)
        vm.displayName = "Sara"
        let task = Task { await vm.submitName() }
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(vm.isSubmitting)
        XCTAssertFalse(vm.canSubmitName)
        await task.value
        XCTAssertFalse(vm.isSubmitting)
    }

    func testNameCannotBeSubmittedFromOtherSteps() async {
        let fake = FakeOnboardingService()
        let vm = make(fake)
        await toLanguages(vm)
        await vm.submitName()
        let names = await fake.names
        XCTAssertEqual(names.count, 1)
        XCTAssertEqual(vm.step, .languages)
    }

    // MARK: languages step

    func testLanguagesBeforeNameStepIsNoOp() async {
        let fake = FakeOnboardingService()
        let vm = make(fake)
        await vm.startLearning(courseCodes: ["fa"])
        let calls = await fake.enrollCalls.count
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(vm.step, .name)
    }

    func testEmptyPickIsNoOp() async {
        let fake = FakeOnboardingService()
        let vm = make(fake)
        await toLanguages(vm)
        await vm.startLearning(courseCodes: [])
        let calls = await fake.enrollCalls.count
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(vm.step, .languages)
    }

    func testEnrollsInPickOrderStartsOnFirstAndAppliesOnlyFinalBootstrap() async {
        let fake = FakeOnboardingService()
        let recorder = Recorder()
        let store = InMemoryOnboardingStepStore()
        let vm = make(fake, store: store, recorder: recorder)
        await toLanguages(vm)
        await vm.startLearning(courseCodes: ["ja", "fa"])
        let calls = await fake.enrollCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].0, ["ja", "fa"])
        XCTAssertEqual(calls[0].1, "ja")
        XCTAssertEqual(recorder.bootstraps.count, 1)
        XCTAssertEqual(recorder.bootstraps[0].course?.code, "ja")
        XCTAssertEqual(vm.step, .tutorial)
        XCTAssertEqual(store.step, .tutorial)
    }

    func testRepeatedCodesAreEnrolledOnce() async {
        let fake = FakeOnboardingService()
        let vm = make(fake)
        await toLanguages(vm)
        await vm.startLearning(courseCodes: ["ja", "fa", "ja"])
        let calls = await fake.enrollCalls
        XCTAssertEqual(calls[0].0, ["ja", "fa"])
    }

    func testEnrollFailureStaysAppliesNothingAndRetrySucceeds() async {
        let fake = FakeOnboardingService()
        let recorder = Recorder()
        let vm = make(fake, recorder: recorder)
        await toLanguages(vm)
        await fake.setEnroll(.failure(ApiError(status: 500, body: nil)))
        await vm.startLearning(courseCodes: ["fa"])
        XCTAssertEqual(vm.error, OnboardingRules.enrollFallback)
        XCTAssertEqual(vm.step, .languages)
        XCTAssertEqual(recorder.bootstraps.count, 0)
        XCTAssertFalse(vm.isSubmitting)
        await fake.setEnroll(.success(()))
        await vm.startLearning(courseCodes: ["fa"])
        XCTAssertNil(vm.error)
        XCTAssertEqual(vm.step, .tutorial)
        XCTAssertEqual(recorder.bootstraps.count, 1)
    }

    func testDoubleStartLearningEnrollsOnce() async {
        let fake = FakeOnboardingService()
        let recorder = Recorder()
        let vm = make(fake, recorder: recorder)
        await toLanguages(vm)
        await fake.setDelay(50_000_000)
        async let first: Void = vm.startLearning(courseCodes: ["fa"])
        async let second: Void = vm.startLearning(courseCodes: ["fa"])
        _ = await (first, second)
        let calls = await fake.enrollCalls.count
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(recorder.bootstraps.count, 1)
    }

    // MARK: tutorial step

    func testFinishBeforeTutorialIsNoOp() async {
        let fake = FakeOnboardingService()
        let vm = make(fake)
        await toLanguages(vm)
        await vm.finishTutorial()
        let calls = await fake.completeCalls
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(vm.isFinished)
    }

    func testFinishingTutorialCompletesOnceAndClearsStoredStep() async {
        let fake = FakeOnboardingService()
        let recorder = Recorder()
        let store = InMemoryOnboardingStepStore()
        let vm = make(fake, store: store, recorder: recorder)
        await toTutorial(vm)
        await vm.finishTutorial()
        XCTAssertTrue(vm.isFinished)
        XCTAssertNil(store.step)
        XCTAssertEqual(recorder.completions, [true])
        await vm.finishTutorial()
        let calls = await fake.completeCalls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(recorder.completions, [true])
    }

    func testFailedCompleteCallStillFinishes() async {
        let fake = FakeOnboardingService()
        await fake.setComplete(.failure(URLError(.notConnectedToInternet)))
        let recorder = Recorder()
        let vm = make(fake, recorder: recorder)
        await toTutorial(vm)
        await vm.finishTutorial()
        XCTAssertTrue(vm.isFinished)
        XCTAssertNil(vm.error)
        XCTAssertEqual(recorder.completions, [true])
    }

    func testDoubleFinishCompletesOnce() async {
        let fake = FakeOnboardingService()
        let recorder = Recorder()
        let vm = make(fake, recorder: recorder)
        await toTutorial(vm)
        await fake.setDelay(50_000_000)
        async let first: Void = vm.finishTutorial()
        async let second: Void = vm.finishTutorial()
        _ = await (first, second)
        let calls = await fake.completeCalls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(recorder.completions.count, 1)
    }

    func testFinishedFlowIgnoresFurtherActions() async {
        let fake = FakeOnboardingService()
        let vm = make(fake)
        await toTutorial(vm)
        await vm.finishTutorial()
        await vm.submitName()
        await vm.startLearning(courseCodes: ["ja"])
        let names = await fake.names.count
        let enrolls = await fake.enrollCalls.count
        XCTAssertEqual(names, 1)
        XCTAssertEqual(enrolls, 1)
        XCTAssertEqual(vm.step, .tutorial)
    }

    // MARK: catalog

    func testCatalogLoads() async {
        let fake = FakeOnboardingService()
        await fake.setCatalog(.success([entry("fa"), entry("ja")]))
        let vm = make(fake)
        XCTAssertNil(vm.catalog)
        await vm.loadCatalog()
        XCTAssertEqual(vm.catalog?.map { $0.code }, ["fa", "ja"])
        XCTAssertNil(vm.catalogError)
    }

    func testCatalogFailureUsesOwnErrorAndRetryRecovers() async {
        let fake = FakeOnboardingService()
        await fake.setCatalog(.failure(ApiError(status: 500, body: nil)))
        let vm = make(fake)
        await vm.loadCatalog()
        XCTAssertEqual(vm.catalogError, OnboardingRules.catalogFallback)
        XCTAssertNil(vm.error)
        XCTAssertNil(vm.catalog)
        await fake.setCatalog(.success([entry("fa")]))
        await vm.loadCatalog()
        XCTAssertNil(vm.catalogError)
        XCTAssertEqual(vm.catalog?.count, 1)
    }

    func testCatalogFailureNeverOverridesInFlightSubmitOrItsError() async {
        let fake = FakeOnboardingService()
        let vm = make(fake)
        await toLanguages(vm)
        await fake.setDelay(600_000_000)
        await fake.setEnroll(.failure(ApiError(status: 400, body: ApiErrorBody(error: "Bad course."))))
        await fake.setCatalog(.failure(ApiError(status: 500, body: nil)))
        let task = Task { await vm.startLearning(courseCodes: ["fa"]) }
        try? await Task.sleep(nanoseconds: 30_000_000)
        await vm.loadCatalog()
        XCTAssertTrue(vm.isSubmitting)
        XCTAssertNil(vm.error)
        await task.value
        XCTAssertEqual(vm.error, "Bad course.")
        XCTAssertEqual(vm.catalogError, OnboardingRules.catalogFallback)
        XCTAssertEqual(vm.step, .languages)
    }

    // MARK: persistence

    func testStepIsRestoredFromStore() {
        let store = InMemoryOnboardingStepStore(step: .tutorial)
        XCTAssertEqual(make(FakeOnboardingService(), store: store).step, .tutorial)
    }

    func testUserDefaultsStoreRoundTrips() {
        let suite = "onboarding-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return XCTFail("no defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsOnboardingStepStore(defaults: defaults, key: "step")
        XCTAssertNil(store.step)
        store.step = .languages
        XCTAssertEqual(store.step, .languages)
        store.step = nil
        XCTAssertNil(store.step)
    }
}
