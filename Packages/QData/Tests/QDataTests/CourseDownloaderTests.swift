import XCTest
import QModel
import QNetwork
@testable import QData

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [DownloadProgress] = []
    var onEvent: (@Sendable (DownloadProgress) -> Void)?

    func record(_ progress: DownloadProgress) {
        lock.lock()
        items.append(progress)
        let callback = onEvent
        lock.unlock()
        callback?(progress)
    }

    var all: [DownloadProgress] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Error>?
    private var cancelRequested = false

    func set(_ value: Task<Void, Error>) {
        lock.lock()
        task = value
        let pending = cancelRequested
        lock.unlock()
        if pending { value.cancel() }
    }

    func cancel() {
        lock.lock()
        cancelRequested = true
        let current = task
        lock.unlock()
        current?.cancel()
    }
}

final class CourseDownloaderTests: XCTestCase {
    private let audioBody = "audio-one"
    private let variantBody = "audio-variant"
    private var audioSha: String { Sha256.hex(Data(audioBody.utf8)) }
    private var variantSha: String { Sha256.hex(Data(variantBody.utf8)) }

    private let manifestJSON = "{\"courseCode\":\"fa\",\"version\":3,\"units\":[{\"id\":\"u1\",\"path\":\"units/u1.json\"}],\"lexemeIndexPath\":\"lexemes.json\",\"themeIndexPath\":\"themes.json\",\"audioIndexPath\":\"audio.json\",\"verbIndexPath\":\"verbs.json\"}"

    /// URL path to body for every file the fixture course serves.
    private func fixture() -> [String: String] {
        let audioPath = "../../../audio/\(audioSha).mp3"
        let variantPath = "../../../audio/\(variantSha).mp3"
        return [
            "/course/fa/v3/manifest.json": manifestJSON,
            "/course/fa/v3/units/u1.json": "{\"id\":\"u1\",\"title\":\"U\",\"positions\":[{\"skills\":[{\"id\":\"s1\",\"path\":\"skills/s1.json\"}]}]}",
            "/course/fa/v3/lexemes.json": "{}",
            "/course/fa/v3/verbs.json": "{}",
            "/course/fa/v3/themes.json": "{\"themes\":[{\"id\":\"t1\",\"lessons\":[{\"id\":\"l1\",\"path\":\"lessons/l1.json\"}]}]}",
            "/course/fa/v3/audio.json": "{\"voices\":[{\"id\":\"v1\",\"name\":\"V\"}],\"phrases\":[{\"text\":\"x\",\"voice\":\"v1\",\"path\":\"\(audioPath)\"}]}",
            "/course/fa/v3/skills/s1.json": "{\"exercises\":[{\"answerVariantAudio\":[{\"v1\":[\"\(variantPath)\"]}]}]}",
            "/course/fa/v3/lessons/l1.json": "{\"exercises\":[]}",
            "/audio/\(audioSha).mp3": audioBody,
            "/audio/\(variantSha).mp3": variantBody,
        ]
    }

    private func serve(_ files: [String: String]) {
        StubURLProtocol.install { request in
            guard let path = request.url?.path, let body = files[path] else { return StubResponse(404) }
            return StubResponse(200, body)
        }
    }

    private func makeDownloader(_ store: ContentFileStore, parallelism: Int = 3) -> CourseDownloader {
        let session = StubURLProtocol.makeSession()
        let cdn = CdnClient(baseURL: URL(string: "https://cdn.test")!, session: session)
        return CourseDownloader(cdn: cdn, store: store, session: session, parallelism: parallelism)
    }

    private var manifestSha: String { Sha256.hex(Data(manifestJSON.utf8)) }

    private let expectedKeys: (String, String) -> Set<String> = { audio, variant in
        [
            "course/fa/v3/units/u1.json", "course/fa/v3/lexemes.json", "course/fa/v3/verbs.json",
            "course/fa/v3/themes.json", "course/fa/v3/audio.json", "course/fa/v3/skills/s1.json",
            "course/fa/v3/lessons/l1.json", "audio/\(audio).mp3", "audio/\(variant).mp3",
            "course/fa/v3/.complete", "course/fa/v3/manifest.json",
        ]
    }

    func testHappyPathStoresEveryFileAndMarksComplete() async throws {
        serve(fixture())
        let store = InMemoryContentStore()
        let log = ProgressLog()
        let downloader = makeDownloader(store)
        try await downloader.download(courseCode: "fa", version: 3, manifestSha256: manifestSha) { log.record($0) }

        XCTAssertEqual(store.keys, expectedKeys(audioSha, variantSha))
        XCTAssertTrue(downloader.isComplete(courseCode: "fa", version: 3, manifestSha256: manifestSha))
        XCTAssertEqual(try store.read("course/fa/v3/manifest.json"), Data(manifestJSON.utf8))
        let last = try XCTUnwrap(log.all.last)
        XCTAssertEqual(last.done, last.discovered)
        XCTAssertEqual(last.done, 9)
    }

    func testProgressIsMonotonic() async throws {
        serve(fixture())
        let log = ProgressLog()
        try await makeDownloader(InMemoryContentStore()).download(courseCode: "fa", version: 3, manifestSha256: manifestSha) { log.record($0) }

        let events = log.all
        XCTAssertFalse(events.isEmpty)
        var previous = DownloadProgress(done: 0, discovered: 0)
        for event in events {
            XCTAssertGreaterThanOrEqual(event.done, previous.done)
            XCTAssertGreaterThanOrEqual(event.discovered, previous.discovered)
            XCTAssertLessThanOrEqual(event.done, event.discovered)
            previous = event
        }
    }

    func testHashMismatchDiscardsFileAndFailsWithoutMarkingComplete() async throws {
        var files = fixture()
        files["/audio/\(audioSha).mp3"] = "tampered"
        serve(files)
        let store = InMemoryContentStore()
        let downloader = makeDownloader(store)
        do {
            try await downloader.download(courseCode: "fa", version: 3, manifestSha256: manifestSha)
            XCTFail("expected hash mismatch")
        } catch let error as FileHashMismatchError {
            XCTAssertEqual(error.path, "audio/\(audioSha).mp3")
            XCTAssertEqual(error.expected, audioSha)
        }
        XCTAssertFalse(store.keys.contains("audio/\(audioSha).mp3"))
        XCTAssertFalse(downloader.isComplete(courseCode: "fa", version: 3, manifestSha256: manifestSha))
    }

    func testResumeSkipsFilesAlreadyPresentAndVerified() async throws {
        serve(fixture())
        let store = InMemoryContentStore()
        try await makeDownloader(store).download(courseCode: "fa", version: 3, manifestSha256: manifestSha)
        try store.remove("course/fa/v3/.complete")

        serve(fixture())
        try await makeDownloader(store).download(courseCode: "fa", version: 3, manifestSha256: manifestSha)

        let paths = StubURLProtocol.requests.compactMap { $0.url?.path }
        XCTAssertEqual(paths, ["/course/fa/v3/manifest.json"])
        XCTAssertTrue(store.keys.contains("course/fa/v3/.complete"))
    }

    func testResumeRefetchesCorruptAudioOnly() async throws {
        serve(fixture())
        let store = InMemoryContentStore()
        try await makeDownloader(store).download(courseCode: "fa", version: 3, manifestSha256: manifestSha)
        try store.remove("course/fa/v3/.complete")
        try store.write(Data("junk".utf8), to: "audio/\(audioSha).mp3")

        serve(fixture())
        try await makeDownloader(store).download(courseCode: "fa", version: 3, manifestSha256: manifestSha)

        let paths = StubURLProtocol.requests.compactMap { $0.url?.path }
        XCTAssertEqual(Set(paths), ["/course/fa/v3/manifest.json", "/audio/\(audioSha).mp3"])
        XCTAssertEqual(try store.read("audio/\(audioSha).mp3"), Data(audioBody.utf8))
    }

    func testCompleteVersionIsNotFetchedAgain() async throws {
        serve(fixture())
        let store = InMemoryContentStore()
        let downloader = makeDownloader(store)
        try await downloader.download(courseCode: "fa", version: 3, manifestSha256: manifestSha)
        serve(fixture())
        try await downloader.download(courseCode: "fa", version: 3, manifestSha256: manifestSha)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testCancelLeavesVersionIncomplete() async throws {
        serve(fixture())
        let store = InMemoryContentStore()
        let downloader = makeDownloader(store, parallelism: 1)
        let box = TaskBox()
        let log = ProgressLog()
        log.onEvent = { event in
            if event.done == 1 { box.cancel() }
        }
        let task = Task {
            try await downloader.download(courseCode: "fa", version: 3, manifestSha256: self.manifestSha) { log.record($0) }
        }
        box.set(task)
        do {
            try await task.value
            XCTFail("expected cancellation")
        } catch {
            // CancellationError or URLError.cancelled; either way the download stopped.
        }
        XCTAssertFalse(downloader.isComplete(courseCode: "fa", version: 3, manifestSha256: manifestSha))
        XCTAssertFalse(store.keys.contains("course/fa/v3/.complete"))
    }

    func testFileContentStoreRoundTripAndRejectsEscapingKeys() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("qdata-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileContentStore(root: root)
        XCTAssertNil(try store.read("course/fa/v3/a.json"))
        try store.write(Data("one".utf8), to: "course/fa/v3/a.json")
        try store.write(Data("two".utf8), to: "course/fa/v3/a.json")
        XCTAssertEqual(try store.read("course/fa/v3/a.json"), Data("two".utf8))
        try store.remove("course/fa/v3/a.json")
        XCTAssertNil(try store.read("course/fa/v3/a.json"))
        XCTAssertThrowsError(try store.write(Data(), to: "../escape"))
        XCTAssertThrowsError(try store.read("/abs"))
    }
}
