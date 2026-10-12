import XCTest
import QModel
import QNetwork
@testable import QData

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var versions: [Int] = []

    func record(_ version: Int) {
        lock.lock()
        versions.append(version)
        lock.unlock()
    }

    var all: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return versions
    }
}

private struct CommitFailed: Error {}

final class ContentUpdateTests: XCTestCase {
    private let audioBody = "audio-one"
    private var audioSha: String { Sha256.hex(Data(audioBody.utf8)) }

    private func manifest(_ version: Int) -> String {
        "{\"courseCode\":\"fa\",\"version\":\(version),\"units\":[{\"id\":\"u1\",\"path\":\"units/u1.json\"}],\"lexemeIndexPath\":\"lexemes.json\",\"themeIndexPath\":\"themes.json\",\"audioIndexPath\":\"audio.json\",\"verbIndexPath\":\"verbs.json\"}"
    }

    private func manifestSha(_ version: Int) -> String { Sha256.hex(Data(manifest(version).utf8)) }

    private func audioIndex(_ sha: String) -> String {
        "{\"voices\":[{\"id\":\"v1\",\"name\":\"V\"}],\"phrases\":[{\"text\":\"x\",\"voice\":\"v1\",\"path\":\"../../../audio/\(sha).mp3\"}]}"
    }

    private func version(_ v: Int) -> [String: String] {
        let root = "/course/fa/v\(v)"
        return [
            "\(root)/manifest.json": manifest(v),
            "\(root)/units/u1.json": "{\"id\":\"u1\",\"title\":\"U\",\"positions\":[{\"skills\":[{\"id\":\"s1\",\"path\":\"skills/s1.json\"}]}]}",
            "\(root)/lexemes.json": "{}",
            "\(root)/verbs.json": "{}",
            "\(root)/themes.json": "{\"themes\":[]}",
            "\(root)/audio.json": audioIndex(audioSha),
            "\(root)/skills/s1.json": "{\"exercises\":[]}",
        ]
    }

    private func serve(_ files: [String: String]) {
        StubURLProtocol.install { request in
            guard let path = request.url?.path, let body = files[path] else { return StubResponse(404) }
            return StubResponse(200, body)
        }
    }

    /// v3 and v4 plus the shared audio file.
    private func world() -> [String: String] {
        var files = version(3)
        for (key, value) in version(4) { files[key] = value }
        files["/audio/\(audioSha).mp3"] = audioBody
        return files
    }

    private func makeDownloader(_ store: ContentFileStore) -> CourseDownloader {
        let session = StubURLProtocol.makeSession()
        let cdn = CdnClient(baseURL: URL(string: "https://cdn.test")!, session: session)
        return CourseDownloader(cdn: cdn, store: store, session: session, parallelism: 3)
    }

    /// A store with v3 fully downloaded, as if pinned.
    private func installed(serving files: [String: String]) async throws -> (InMemoryContentStore, ContentUpdater) {
        serve(files)
        let store = InMemoryContentStore()
        let downloader = makeDownloader(store)
        try await downloader.download(courseCode: "fa", version: 3, manifestSha256: manifestSha(3))
        return (store, ContentUpdater(downloader: downloader))
    }

    private func isComplete(_ store: ContentFileStore, _ v: Int) -> Bool {
        ContentStoreKeys.isComplete(store, courseCode: "fa", version: v, manifestSha256: manifestSha(v))
    }

    // MARK: - Detection

    func testDetectNeedsNewerUpdateThanPin() {
        let course = CourseRef(code: "fa", version: 3, manifestSha256: "a")
        let newer = CourseUpdateRef(version: 4, manifestSha256: "b", eligible: true)
        XCTAssertEqual(ContentUpdateOffer.detect(course: course, update: newer)?.version, 4)
        XCTAssertNil(ContentUpdateOffer.detect(course: course, update: CourseUpdateRef(version: 3, manifestSha256: "b", eligible: true)))
        XCTAssertNil(ContentUpdateOffer.detect(course: course, update: nil))
        XCTAssertNil(ContentUpdateOffer.detect(course: nil, update: newer))
    }

    func testIneligibleUpdateIsStillOfferedWithHint() throws {
        let course = CourseRef(code: "fa", version: 3, manifestSha256: "a")
        let update = CourseUpdateRef(version: 4, manifestSha256: "b", eligible: false)
        let offer = try XCTUnwrap(ContentUpdateOffer.detect(course: course, update: update))
        XCTAssertEqual(offer.hint, "Tap Update to see what's going on.")
        XCTAssertEqual(offer.title, "Course update available \u{2014} version 4")
    }

    func testNotesWinOverHintAndEligibleHasNone() {
        XCTAssertEqual(ContentUpdateOffer(version: 4, manifestSha256: "b", eligible: false, notes: "New words").hint, "New words")
        XCTAssertNil(ContentUpdateOffer(version: 4, manifestSha256: "b", eligible: true).hint)
    }

    func testStateFraction() {
        XCTAssertNil(ContentUpdateState.idle.fraction)
        XCTAssertNil(ContentUpdateState.downloading(DownloadProgress(done: 0, discovered: 0)).fraction)
        XCTAssertEqual(ContentUpdateState.downloading(DownloadProgress(done: 1, discovered: 4)).fraction, 0.25)
        XCTAssertTrue(ContentUpdateState.downloading(DownloadProgress(done: 0, discovered: 0)).isBusy)
        XCTAssertFalse(ContentUpdateState.failed("x").isBusy)
    }

    // MARK: - Roll-forward

    func testVersionBumpDownloadsNewThenCommits() async throws {
        let (store, updater) = try await installed(serving: world())
        let committed = Counter()
        let offer = ContentUpdateOffer(version: 4, manifestSha256: manifestSha(4), eligible: true)
        try await updater.accept(courseCode: "fa", offer: offer) { committed.record($0) }

        XCTAssertEqual(committed.all, [4])
        XCTAssertTrue(isComplete(store, 4))
        XCTAssertTrue(isComplete(store, 3), "old version stays usable")
    }

    func testManifestHashMismatchKeepsOldAndDoesNotCommit() async throws {
        let (store, updater) = try await installed(serving: world())
        let committed = Counter()
        let offer = ContentUpdateOffer(version: 4, manifestSha256: String(repeating: "0", count: 64), eligible: true)
        do {
            try await updater.accept(courseCode: "fa", offer: offer) { committed.record($0) }
            XCTFail("expected manifest mismatch")
        } catch is ManifestHashMismatchError {
        }
        XCTAssertEqual(committed.all, [])
        XCTAssertTrue(isComplete(store, 3))
        XCTAssertFalse(isComplete(store, 4))
    }

    func testAudioHashMismatchKeepsOldAndDoesNotCommit() async throws {
        let wrongSha = Sha256.hex(Data("other".utf8))
        var files = world()
        files["/course/fa/v4/audio.json"] = audioIndex(wrongSha)
        files["/audio/\(wrongSha).mp3"] = "not-other"
        let (store, updater) = try await installed(serving: files)
        // v4's manifest bytes are unchanged, so its pinned hash still verifies; the audio file is what fails.
        let committed = Counter()
        let offer = ContentUpdateOffer(version: 4, manifestSha256: manifestSha(4), eligible: true)
        do {
            try await updater.accept(courseCode: "fa", offer: offer) { committed.record($0) }
            XCTFail("expected file hash mismatch")
        } catch is FileHashMismatchError {
        }
        XCTAssertEqual(committed.all, [])
        XCTAssertTrue(isComplete(store, 3))
        XCTAssertFalse(isComplete(store, 4))
        XCTAssertNil(try store.read("audio/\(wrongSha).mp3"), "mismatched file is not kept")
    }

    func testInterruptedDownloadKeepsOldAndDoesNotCommit() async throws {
        var files = world()
        files["/course/fa/v4/skills/s1.json"] = nil
        let (store, updater) = try await installed(serving: files)
        let committed = Counter()
        let offer = ContentUpdateOffer(version: 4, manifestSha256: manifestSha(4), eligible: true)
        do {
            try await updater.accept(courseCode: "fa", offer: offer) { committed.record($0) }
            XCTFail("expected a failed fetch")
        } catch let error as CdnFetchError {
            XCTAssertEqual(error.status, 404)
        }
        XCTAssertEqual(committed.all, [])
        XCTAssertTrue(isComplete(store, 3))
        XCTAssertFalse(isComplete(store, 4))
        XCTAssertNil(try store.read("course/fa/v4/manifest.json"), "manifest is stored last")
    }

    func testFailedCommitLeavesDownloadedVersionAndOldPin() async throws {
        let (store, updater) = try await installed(serving: world())
        let offer = ContentUpdateOffer(version: 4, manifestSha256: manifestSha(4), eligible: true)
        do {
            try await updater.accept(courseCode: "fa", offer: offer) { _ in throw CommitFailed() }
            XCTFail("expected commit failure")
        } catch is CommitFailed {
        }
        XCTAssertTrue(isComplete(store, 3))
        XCTAssertTrue(isComplete(store, 4))
    }

    func testMessages() {
        XCTAssertEqual(ContentUpdater.message(for: CancellationError()), "Update cancelled.")
        XCTAssertEqual(
            ContentUpdater.message(for: ManifestHashMismatchError(expected: "a", actual: "b")),
            "The update didn't verify, so your course wasn't changed.")
        XCTAssertEqual(ContentUpdater.message(for: CdnFetchError(url: "u", status: 500)), "Couldn't update the course.")
    }
}
