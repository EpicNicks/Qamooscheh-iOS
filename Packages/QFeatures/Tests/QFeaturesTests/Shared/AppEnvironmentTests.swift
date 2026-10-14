import XCTest
import QModel
import QDomain
import QNetwork
import QData
@testable import QFeatures

private struct EnvStub {
    var status: Int
    var body: Data
    init(_ status: Int, _ json: String = "{}") {
        self.status = status
        self.body = Data(json.utf8)
    }
}

private final class EnvStubProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var handler: ((URLRequest) -> EnvStub)?
    private static var recorded: [URLRequest] = []

    static func install(_ handler: @escaping (URLRequest) -> EnvStub) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
        recorded = []
    }

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [EnvStubProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        EnvStubProtocol.lock.lock()
        EnvStubProtocol.recorded.append(request)
        let handler = EnvStubProtocol.handler
        EnvStubProtocol.lock.unlock()
        let stub = handler?(request) ?? EnvStub(500)
        let url = request.url ?? URL(string: "https://stub.invalid")!
        let response = HTTPURLResponse(
            url: url, statusCode: stub.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private let course = CourseRef(code: "fa", version: 3, manifestSha256: "abc")

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

final class AppEnvironmentTests: XCTestCase {
    private func makeSessions() -> InMemorySessionStore {
        InMemorySessionStore(session: StoredSession(
            userId: "u1", accessToken: "tok",
            accessTokenExpiresAt: Date().addingTimeInterval(3600), refreshToken: "r"))
    }

    private func makeEnv(store: ContentFileStore = InMemoryContentStore(), after: (@Sendable () async -> Void)? = nil) -> AppEnvironment {
        let sessions = makeSessions()
        let client = ApiClient(
            baseURL: URL(string: "https://api.test")!, clientHeader: "ios/test",
            session: EnvStubProtocol.makeSession(), store: sessions)
        return AppEnvironment.live(client: client, sessions: sessions, contentStore: store, afterFlashcardSubmit: after)
    }

    private func lastRequest() -> URLRequest? { EnvStubProtocol.requests.last }

    private func put<T: Encodable>(_ store: InMemoryContentStore, _ key: String, _ value: T) throws {
        try store.write(try QJSON.makeEncoder().encode(value), to: key)
    }

    /// A one-unit, one-skill course on disk, with themes.
    private func seededStore() throws -> InMemoryContentStore {
        let store = InMemoryContentStore()
        let manifest = CourseManifest(
            courseCode: "fa", version: 3, units: [ManifestRef(id: "u1", path: "units/u1.json")],
            lexemeIndexPath: "lexemes.json", themeIndexPath: "themes.json")
        try put(store, "course/fa/v3/manifest.json", manifest)
        try put(store, "course/fa/v3/units/u1.json", UnitArtifact(
            id: "u1", title: "Unit 1", positions: [UnitPosition(skills: [ManifestRef(id: "s1", path: "skills/s1.json")])]))
        let exercise = ExerciseArtifact(type: .typeIn, scriptMode: .native, prompt: "p", answer: ["a"], tags: ["salaam"])
        try put(store, "course/fa/v3/skills/s1.json", SkillArtifact(id: "s1", title: "Greetings", exercises: [exercise]))
        try put(store, "course/fa/v3/lexemes.json", ["salaam": LexemeIndexEntry(gloss: "hello", romanizationIsAuthored: false)])
        try put(store, "course/fa/v3/themes.json", ThemeIndexArtifact(themes: [
            ThemeEntry(id: "food", lessons: [ThemeLessonRef(id: "l1", path: "skills/s1.json")]),
        ]))
        try ContentStoreKeys.markComplete(store, courseCode: "fa", version: 3, manifestSha256: "abc")
        return store
    }

    private let bootstrapWithCourse = #"{"course":{"code":"fa","version":3,"manifestSha256":"abc"},"graders":[],"enrolledCourseCodes":["fa"],"onboardingComplete":true}"#
    private let bootstrapNoCourse = #"{"graders":[],"enrolledCourseCodes":[],"onboardingComplete":true}"#

    func testProfileFetchAndSave() async throws {
        EnvStubProtocol.install { _ in EnvStub(200, #"{"displayName":"Ali"}"#) }
        let env = makeEnv()
        let fetched = try await env.profile.fetch()
        XCTAssertEqual(fetched.displayName, "Ali")
        XCTAssertEqual(lastRequest()?.httpMethod, "GET")
        XCTAssertEqual(lastRequest()?.url?.path, "/v1/profile")
        _ = try await env.profile.save(UpdateProfileRequest(displayName: "Ali"))
        XCTAssertEqual(lastRequest()?.httpMethod, "PUT")
        XCTAssertEqual(lastRequest()?.url?.path, "/v1/profile")
    }

    func testStreakPauseAndCancel() async throws {
        EnvStubProtocol.install { _ in EnvStub(200, "{}") }
        let env = makeEnv()
        try await env.streak.pause(StreakPauseRequest(startDay: "2026-10-14", endDay: "2026-10-16"))
        XCTAssertEqual(lastRequest()?.httpMethod, "POST")
        XCTAssertEqual(lastRequest()?.url?.path, "/v1/streak/pause")
        try await env.streak.cancelPause()
        XCTAssertEqual(lastRequest()?.httpMethod, "DELETE")
        XCTAssertEqual(lastRequest()?.url?.path, "/v1/streak/pause")
    }

    func testFriendsAndLeaguesUseRepositories() async throws {
        EnvStubProtocol.install { _ in EnvStub(200, "[]") }
        let env = makeEnv()
        let friends = try await env.friends.friends()
        XCTAssertEqual(friends, [])
        XCTAssertEqual(lastRequest()?.url?.path, "/v1/friends")
        _ = try await env.friends.incomingRequests()
        XCTAssertEqual(lastRequest()?.url?.path, "/v1/friends/requests")
        EnvStubProtocol.install { _ in EnvStub(404, #"{"error":"none"}"#) }
        let league = try await env.leagues.current()
        XCTAssertNil(league)
        XCTAssertEqual(lastRequest()?.url?.path, "/v1/leagues/current")
    }

    func testStarredCalls() async throws {
        EnvStubProtocol.install { _ in EnvStub(200, #"{"tags":["a"],"limit":100,"refused":[]}"#) }
        let env = makeEnv()
        let starred = try await env.vocabulary.starred()
        XCTAssertEqual(starred.tags, ["a"])
        XCTAssertEqual(lastRequest()?.httpMethod, "GET")
        XCTAssertEqual(lastRequest()?.url?.path, "/v1/vocab/starred")
        _ = try await env.vocabulary.setStarred(tag: "a", starred: true)
        XCTAssertEqual(lastRequest()?.httpMethod, "PUT")
        XCTAssertEqual(lastRequest()?.url?.path, "/v1/vocab/starred")
    }

    func testFlashcardSubmitPostsThenRefreshes() async throws {
        EnvStubProtocol.install { _ in EnvStub(200, #"{"alreadyProcessed":false,"xp":10}"#) }
        let flag = Flag()
        let env = makeEnv(after: { flag.set() })
        let request = SubmitFlashcardsRequest(
            submissionId: "s", courseCode: "fa", occurredAt: Date(timeIntervalSince1970: 0), inRemix: false,
            cards: [SubmittedFlashcard(tag: "a", kind: .translation, correct: true)])
        let response = try await env.flashcards.submit(request)
        XCTAssertEqual(response.xp, 10)
        XCTAssertEqual(lastRequest()?.httpMethod, "POST")
        XCTAssertEqual(lastRequest()?.url?.path, "/v1/flashcards/submit")
        XCTAssertTrue(flag.isSet)
    }

    func testVocabularyLoadNoCourse() async throws {
        EnvStubProtocol.install { _ in EnvStub(200, self.bootstrapNoCourse) }
        let load = try await makeEnv().vocabulary.load()
        XCTAssertEqual(load, .noCourse)
        XCTAssertEqual(lastRequest()?.url?.path, "/v1/bootstrap")
    }

    func testVocabularyLoadNotDownloaded() async throws {
        EnvStubProtocol.install { _ in EnvStub(200, self.bootstrapWithCourse) }
        let load = try await makeEnv().vocabulary.load()
        XCTAssertEqual(load, .notDownloaded)
    }

    func testVocabularyLoadReadsPinnedCourseFromDisk() async throws {
        EnvStubProtocol.install { _ in EnvStub(200, self.bootstrapWithCourse) }
        let load = try await makeEnv(store: try seededStore()).vocabulary.load()
        guard case .ready(let content) = load else { return XCTFail("expected ready, got \(load)") }
        XCTAssertEqual(content.courseCode, "fa")
        XCTAssertEqual(content.units.map { $0.unitKey }, ["u1"])
        XCTAssertEqual(content.units.first?.lessons.first?.tags, ["salaam"])
        XCTAssertEqual(content.lexemes["salaam"]?.gloss, "hello")
    }

    func testCardStatesReadTheSignedInUsersMirror() async throws {
        EnvStubProtocol.install { _ in EnvStub(200) }
        let store = InMemoryContentStore()
        let card = CardState(lexemeTag: "salaam", stability: 1, difficulty: 2, reviewCount: 1, lapseCount: 0)
        try await CardStateStore(store: store).merge(userId: "u1", cards: [card])
        try await CardStateStore(store: store).merge(userId: "other", cards: [
            CardState(lexemeTag: "x", stability: 1, difficulty: 2, reviewCount: 1, lapseCount: 0),
        ])
        let cards = await makeEnv(store: store).vocabulary.cardStates()
        XCTAssertEqual(Array(cards.keys), ["salaam"])
    }

    func testThemesLoadHeadersFromDisk() async throws {
        EnvStubProtocol.install { _ in EnvStub(200, self.bootstrapWithCourse) }
        let data = try await makeEnv(store: try seededStore()).themes.load()
        XCTAssertEqual(data?.index.themes.map { $0.id }, ["food"])
        XCTAssertEqual(data?.headers["l1"], ThemeLessonHeader(title: "Greetings", category: .standard))
    }

    func testThemesNilWhenNotDownloaded() async throws {
        EnvStubProtocol.install { _ in EnvStub(200, self.bootstrapWithCourse) }
        let data = try await makeEnv().themes.load()
        XCTAssertNil(data)
    }

    func testGlossaryIsTheBundledOne() {
        EnvStubProtocol.install { _ in EnvStub(200) }
        XCTAssertEqual(makeEnv().glossary, loadGlossary())
    }

    func testContentKeyResolvesDotDot() {
        XCTAssertEqual(CourseContentReader.key(course: course, path: "units/u1.json"), "course/fa/v3/units/u1.json")
        XCTAssertEqual(CourseContentReader.key(course: course, path: "../../../audio/x.mp3"), "audio/x.mp3")
        XCTAssertNil(CourseContentReader.key(course: course, path: "../../../../x"))
        XCTAssertNil(CourseContentReader.key(course: course, path: "a//b"))
    }
}
