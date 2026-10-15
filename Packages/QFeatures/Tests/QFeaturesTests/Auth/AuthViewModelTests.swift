import XCTest
import QNetwork
@testable import QFeatures

private actor FakeAuthService: AuthService {
    var loginCalls: [(String, String)] = []
    var registerCalls: [(String, String, String)] = []
    var googleCalls: [String] = []
    var registrationResult: Result<Bool, Error> = .success(true)
    var signInResult: Result<Void, Error> = .success(())
    var delayNanos: UInt64 = 0
    var gate: SubmitGate?

    func setSignIn(_ result: Result<Void, Error>) { signInResult = result }
    func setRegistration(_ result: Result<Bool, Error>) { registrationResult = result }
    func setDelay(_ nanos: UInt64) { delayNanos = nanos }
    func setGate(_ g: SubmitGate) { gate = g }

    private static let session = StoredSession(
        userId: "u1", accessToken: "a", accessTokenExpiresAt: Date(timeIntervalSince1970: 0), refreshToken: "r")

    private func finish() async throws -> StoredSession {
        if let gate { await gate.pass() }
        if delayNanos > 0 { try await Task.sleep(nanoseconds: delayNanos) }
        try signInResult.get()
        return FakeAuthService.session
    }

    func registrationEnabled() async throws -> Bool { try registrationResult.get() }

    func login(email: String, password: String) async throws -> StoredSession {
        loginCalls.append((email, password))
        return try await finish()
    }

    func register(email: String, password: String, confirmPassword: String) async throws -> StoredSession {
        registerCalls.append((email, password, confirmPassword))
        return try await finish()
    }

    func signInWithGoogle(idToken: String) async throws -> StoredSession {
        googleCalls.append(idToken)
        return try await finish()
    }
}

@MainActor
final class LoginViewModelTests: XCTestCase {
    func testBlankFieldsAreSilentNoOp() async {
        let fake = FakeAuthService()
        let vm = LoginViewModel(service: fake)
        await vm.submit()
        vm.email = "a@b.co"
        await vm.submit()
        XCTAssertEqual(vm.state, .idle)
        let calls = await fake.loginCalls.count
        XCTAssertEqual(calls, 0)
    }

    func testSuccessSendsCredentialsAndEndsInSuccess() async {
        let fake = FakeAuthService()
        let vm = LoginViewModel(service: fake)
        vm.email = "a@b.co"
        vm.password = "x"
        await vm.submit()
        XCTAssertEqual(vm.state, .success)
        let calls = await fake.loginCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].0, "a@b.co")
        XCTAssertEqual(calls[0].1, "x")
    }

    func testServerMessageIsShown() async {
        let fake = FakeAuthService()
        await fake.setSignIn(.failure(AuthError.invalidCredentials(message: "Nope.")))
        let vm = LoginViewModel(service: fake)
        vm.email = "a@b.co"
        vm.password = "x"
        await vm.submit()
        XCTAssertEqual(vm.state, .error("Nope."))
    }

    func testMissingMessageUsesFallback() async {
        let fake = FakeAuthService()
        await fake.setSignIn(.failure(AuthError.invalidCredentials(message: nil)))
        let vm = LoginViewModel(service: fake)
        vm.email = "a@b.co"
        vm.password = "x"
        await vm.submit()
        XCTAssertEqual(vm.state, .error(AuthRules.loginFallback))
    }

    func testTooManyAttemptsAndOffline() async {
        let fake = FakeAuthService()
        let vm = LoginViewModel(service: fake)
        vm.email = "a@b.co"
        vm.password = "x"
        await fake.setSignIn(.failure(AuthError.tooManyAttempts(message: nil)))
        await vm.submit()
        XCTAssertEqual(vm.state, .error(AuthRules.tooManyRequests))
        await fake.setSignIn(.failure(URLError(.notConnectedToInternet)))
        await vm.submit()
        XCTAssertEqual(vm.state, .error(AuthRules.offline))
    }

    func testEditingClearsError() async {
        let fake = FakeAuthService()
        await fake.setSignIn(.failure(AuthError.validation(message: nil)))
        let vm = LoginViewModel(service: fake)
        vm.email = "a@b.co"
        vm.password = "x"
        await vm.submit()
        XCTAssertEqual(vm.state, .error(AuthRules.loginFallback))
        vm.password = "xy"
        XCTAssertEqual(vm.state, .idle)
    }

    func testRetryAfterErrorCanSucceed() async {
        let fake = FakeAuthService()
        await fake.setSignIn(.failure(AuthError.validation(message: nil)))
        let vm = LoginViewModel(service: fake)
        vm.email = "a@b.co"
        vm.password = "x"
        await vm.submit()
        await fake.setSignIn(.success(()))
        await vm.submit()
        XCTAssertEqual(vm.state, .success)
    }

    func testDoubleSubmitIsGuarded() async {
        let fake = FakeAuthService()
        await fake.setDelay(50_000_000)
        let vm = LoginViewModel(service: fake)
        vm.email = "a@b.co"
        vm.password = "x"
        async let first: Void = vm.submit()
        async let second: Void = vm.submit()
        _ = await (first, second)
        let calls = await fake.loginCalls.count
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(vm.state, .success)
    }

    func testSubmittingStateIsObservable() async {
        let fake = FakeAuthService()
        let gate = SubmitGate()
        await fake.setGate(gate)
        let vm = LoginViewModel(service: fake)
        vm.email = "a@b.co"
        vm.password = "x"
        let task = Task { await vm.submit() }
        await gate.waitUntilEntered()
        XCTAssertEqual(vm.state, .submitting)
        XCTAssertFalse(vm.canSubmit)
        await gate.release()
        await task.value
        XCTAssertEqual(vm.state, .success)
    }

    func testLoginDoesNotEnforceEmailFormatOrPasswordLength() async {
        let fake = FakeAuthService()
        let vm = LoginViewModel(service: fake)
        vm.email = "admin"
        vm.password = "x"
        await vm.submit()
        XCTAssertEqual(vm.state, .success)
    }

    func testOverlongFieldRejectedLocally() async {
        let fake = FakeAuthService()
        let vm = LoginViewModel(service: fake)
        vm.email = "a@b.co"
        vm.password = String(repeating: "p", count: 257)
        await vm.submit()
        XCTAssertEqual(vm.state, .error(AuthRules.fieldTooLong))
        let calls = await fake.loginCalls.count
        XCTAssertEqual(calls, 0)
    }

    func testGoogleSuccessAndError() async {
        let fake = FakeAuthService()
        let vm = LoginViewModel(service: fake)
        vm.reportGoogleError("Cancelled.")
        XCTAssertEqual(vm.state, .error("Cancelled."))
        await fake.setSignIn(.failure(AuthError.registrationClosed(message: nil)))
        await vm.signInWithGoogle(idToken: "tok")
        XCTAssertEqual(vm.state, .error(AuthRules.googleFallback))
        await fake.setSignIn(.success(()))
        await vm.signInWithGoogle(idToken: "tok")
        XCTAssertEqual(vm.state, .success)
        let calls = await fake.googleCalls
        XCTAssertEqual(calls, ["tok", "tok"])
    }

    func testRegistrationStatus() async {
        let fake = FakeAuthService()
        await fake.setRegistration(.success(false))
        let vm = LoginViewModel(service: fake)
        XCTAssertNil(vm.registrationEnabled)
        await vm.loadRegistrationStatus()
        XCTAssertEqual(vm.registrationEnabled, false)
    }

    func testRegistrationStatusFailureLeavesNil() async {
        let fake = FakeAuthService()
        await fake.setRegistration(.failure(URLError(.timedOut)))
        let vm = LoginViewModel(service: fake)
        await vm.loadRegistrationStatus()
        XCTAssertNil(vm.registrationEnabled)
    }

    func testGoogleErrorDuringSubmitStaysSubmitting() async {
        let fake = FakeAuthService()
        let gate = SubmitGate()
        await fake.setGate(gate)
        let vm = LoginViewModel(service: fake)
        vm.email = "a@b.co"
        vm.password = "x"
        let task = Task { await vm.submit() }
        await gate.waitUntilEntered()
        XCTAssertEqual(vm.state, .submitting)
        vm.reportGoogleError("Cancelled.")
        XCTAssertEqual(vm.state, .submitting)
        await gate.release()
        await task.value
        XCTAssertEqual(vm.state, .success)
    }

    func testGoogleErrorAfterSuccessStaysSuccess() async {
        let fake = FakeAuthService()
        let vm = LoginViewModel(service: fake)
        vm.email = "a@b.co"
        vm.password = "x"
        await vm.submit()
        XCTAssertEqual(vm.state, .success)
        vm.reportGoogleError("Cancelled.")
        XCTAssertEqual(vm.state, .success)
    }
}

@MainActor
final class RegisterViewModelTests: XCTestCase {
    private func filled(_ fake: FakeAuthService, password: String = "password1", confirm: String = "password1") -> RegisterViewModel {
        let vm = RegisterViewModel(service: fake)
        vm.email = "a@b.co"
        vm.password = password
        vm.confirmPassword = confirm
        return vm
    }

    func testSuccess() async {
        let fake = FakeAuthService()
        let vm = filled(fake)
        await vm.submit()
        XCTAssertEqual(vm.state, .success)
        let calls = await fake.registerCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].2, "password1")
    }

    func testMismatchBlocksBeforeNetwork() async {
        let fake = FakeAuthService()
        let vm = filled(fake, confirm: "password2")
        await vm.submit()
        XCTAssertEqual(vm.state, .error(AuthRules.passwordMismatch))
        let calls = await fake.registerCalls.count
        XCTAssertEqual(calls, 0)
    }

    func testShortPasswordBlocksBeforeNetwork() async {
        let fake = FakeAuthService()
        let vm = filled(fake, password: "short", confirm: "short")
        await vm.submit()
        XCTAssertEqual(vm.state, .error(AuthRules.passwordTooShort))
        let calls = await fake.registerCalls.count
        XCTAssertEqual(calls, 0)
    }

    func testMinLengthBoundary() async {
        let fake = FakeAuthService()
        let vm = filled(fake, password: "12345678", confirm: "12345678")
        XCTAssertNil(vm.validationError)
        vm.password = "1234567"
        vm.confirmPassword = "1234567"
        XCTAssertEqual(vm.validationError, AuthRules.passwordTooShort)
    }

    func testEmailFormat() {
        XCTAssertTrue(AuthRules.isPlausibleEmail("a@b.co"))
        XCTAssertTrue(AuthRules.isPlausibleEmail("  a@b.co "))
        XCTAssertFalse(AuthRules.isPlausibleEmail("ab.co"))
        XCTAssertFalse(AuthRules.isPlausibleEmail("a@"))
        XCTAssertFalse(AuthRules.isPlausibleEmail("@b.co"))
        XCTAssertFalse(AuthRules.isPlausibleEmail("a@@b.co"))
        XCTAssertFalse(AuthRules.isPlausibleEmail("a b@c.co"))
    }

    func testInvalidEmailBlocksBeforeNetwork() async {
        let fake = FakeAuthService()
        let vm = filled(fake)
        vm.email = "nope"
        await vm.submit()
        XCTAssertEqual(vm.state, .error(AuthRules.emailInvalid))
        let calls = await fake.registerCalls.count
        XCTAssertEqual(calls, 0)
    }

    func testEmailTakenShowsServerMessageOrFallback() async {
        let fake = FakeAuthService()
        let vm = filled(fake)
        await fake.setSignIn(.failure(AuthError.emailTaken(message: "Taken.")))
        await vm.submit()
        XCTAssertEqual(vm.state, .error("Taken."))
        await fake.setSignIn(.failure(AuthError.emailTaken(message: nil)))
        await vm.submit()
        XCTAssertEqual(vm.state, .error(AuthRules.registerFallback))
    }

    func testOtherApiErrorMapping() async {
        let fake = FakeAuthService()
        let vm = filled(fake)
        await fake.setSignIn(.failure(AuthError.other(ApiError(status: 500, body: ApiErrorBody(error: "Boom")))))
        await vm.submit()
        XCTAssertEqual(vm.state, .error("Boom"))
        await fake.setSignIn(.failure(AuthError.other(ApiError(status: 429, body: nil))))
        await vm.submit()
        XCTAssertEqual(vm.state, .error(AuthRules.tooManyRequests))
        await fake.setSignIn(.failure(AuthError.other(ApiError(status: 500, body: nil))))
        await vm.submit()
        XCTAssertEqual(vm.state, .error(AuthRules.registerFallback))
    }

    func testEditingClearsLocalError() async {
        let fake = FakeAuthService()
        let vm = filled(fake, confirm: "other")
        await vm.submit()
        XCTAssertEqual(vm.state, .error(AuthRules.passwordMismatch))
        vm.confirmPassword = "password1"
        XCTAssertEqual(vm.state, .idle)
    }

    func testDoubleSubmitIsGuarded() async {
        let fake = FakeAuthService()
        await fake.setDelay(50_000_000)
        let vm = filled(fake)
        async let first: Void = vm.submit()
        async let second: Void = vm.submit()
        _ = await (first, second)
        let calls = await fake.registerCalls.count
        XCTAssertEqual(calls, 1)
    }

    func testRegistrationClosedStatus() async {
        let fake = FakeAuthService()
        await fake.setRegistration(.success(false))
        let vm = RegisterViewModel(service: fake)
        await vm.loadRegistrationStatus()
        XCTAssertEqual(vm.registrationEnabled, false)
    }

    func testGoogleFromRegister() async {
        let fake = FakeAuthService()
        let vm = RegisterViewModel(service: fake)
        await vm.signInWithGoogle(idToken: "t")
        XCTAssertEqual(vm.state, .success)
    }

    func testGoogleErrorDuringSubmitStaysSubmitting() async {
        let fake = FakeAuthService()
        let gate = SubmitGate()
        await fake.setGate(gate)
        let vm = filled(fake)
        let task = Task { await vm.submit() }
        await gate.waitUntilEntered()
        XCTAssertEqual(vm.state, .submitting)
        vm.reportGoogleError("Cancelled.")
        XCTAssertEqual(vm.state, .submitting)
        await gate.release()
        await task.value
        XCTAssertEqual(vm.state, .success)
    }

    func testGoogleErrorAfterSuccessStaysSuccess() async {
        let fake = FakeAuthService()
        let vm = filled(fake)
        await vm.submit()
        XCTAssertEqual(vm.state, .success)
        vm.reportGoogleError("Cancelled.")
        XCTAssertEqual(vm.state, .success)
    }
}

@MainActor
final class SessionNotSavedTests: XCTestCase {
    func testLoginSuccessThenNotSavedIsRetryableError() async {
        let fake = FakeAuthService()
        let vm = LoginViewModel(service: fake)
        vm.email = "a@b.co"
        vm.password = "secret123"
        await vm.submit()
        XCTAssertEqual(vm.state, .success)
        XCTAssertFalse(vm.canSubmit)
        vm.sessionNotSaved()
        XCTAssertEqual(vm.state, .error(AuthRules.sessionNotSaved))
        XCTAssertTrue(vm.canSubmit)
        await vm.submit()
        XCTAssertEqual(vm.state, .success)
        let calls = await fake.loginCalls.count
        XCTAssertEqual(calls, 2)
    }

    func testRegisterSuccessThenNotSavedIsRetryableError() async {
        let fake = FakeAuthService()
        let vm = RegisterViewModel(service: fake)
        vm.email = "a@b.co"
        vm.password = "secret123"
        vm.confirmPassword = "secret123"
        await vm.submit()
        XCTAssertEqual(vm.state, .success)
        XCTAssertFalse(vm.canSubmit)
        vm.sessionNotSaved()
        XCTAssertEqual(vm.state, .error(AuthRules.sessionNotSaved))
        XCTAssertTrue(vm.canSubmit)
    }

    func testNotSavedIgnoredOutsideSuccess() {
        let vm = LoginViewModel(service: FakeAuthService())
        vm.sessionNotSaved()
        XCTAssertEqual(vm.state, .idle)
    }
}
