import Foundation
import QModel
import QNetwork

public struct DownloadProgress: Equatable, Sendable {
    public let done: Int
    public let discovered: Int

    public init(done: Int, discovered: Int) {
        self.done = done
        self.discovered = discovered
    }
}

/// A content-addressed file did not hash to the sha256 in its name. It is not kept.
public struct FileHashMismatchError: Error, Equatable, Sendable {
    public let path: String
    public let expected: String
    public let actual: String

    public init(path: String, expected: String, actual: String) {
        self.path = path
        self.expected = expected
        self.actual = actual
    }
}

/// Downloads a whole pinned course version to a ContentFileStore.
///
/// The manifest is verified against the bootstrap hash by CdnClient; every
/// other file is reached through its relative paths. The course manifest
/// carries no per-file hashes, so only the content-addressed audio files
/// (named `<sha256>.<ext>`) are hash-checked, as on Android.
/// Resumable: files already in the store are skipped (audio is re-verified).
/// The version is marked complete only after every file is in.
public struct CourseDownloader: Sendable {
    private let cdn: CdnClient
    private let store: ContentFileStore
    private let session: URLSession
    private let parallelism: Int

    public init(cdn: CdnClient, store: ContentFileStore, session: URLSession = .shared, parallelism: Int = 6) {
        self.cdn = cdn
        self.store = store
        self.session = session
        self.parallelism = max(1, parallelism)
    }

    public func isComplete(courseCode: String, version: Int, manifestSha256: String) -> Bool {
        ContentStoreKeys.isComplete(store, courseCode: courseCode, version: version, manifestSha256: manifestSha256)
    }

    public func download(
        courseCode: String, version: Int, manifestSha256: String,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void = { _ in }
    ) async throws {
        if isComplete(courseCode: courseCode, version: version, manifestSha256: manifestSha256) { return }
        let manifest = try await cdn.courseManifest(courseCode: courseCode, version: version, manifestSha256: manifestSha256)
        let tracker = Tracker(onProgress)
        let decoder = QJSON.makeDecoder()

        func locate(_ path: String) throws -> Target {
            let url = try cdn.contentURL(courseCode: courseCode, version: version, relativePath: path)
            return Target(key: try key(for: url, courseCode: courseCode, version: version), url: url)
        }

        func readStored<T: Decodable>(_ target: Target, as type: T.Type) throws -> T {
            guard let data = try store.read(target.key) else { throw InvalidStoreKeyError(key: target.key) }
            return try decoder.decode(T.self, from: data)
        }

        // Level 1: units and indexes. Their contents name level 2.
        let unitTargets = try manifest.units.map { try locate($0.path) }
        var level1 = unitTargets
        level1.append(try locate(manifest.lexemeIndexPath))
        var themeTarget: Target?
        if let path = manifest.themeIndexPath {
            let target = try locate(path)
            themeTarget = target
            level1.append(target)
        }
        var audioTarget: Target?
        if let path = manifest.audioIndexPath {
            let target = try locate(path)
            audioTarget = target
            level1.append(target)
        }
        if let path = manifest.verbIndexPath { level1.append(try locate(path)) }
        try await fetchAll(level1, tracker)

        var skillPaths: [String] = []
        for target in unitTargets {
            let unit = try readStored(target, as: UnitArtifact.self)
            skillPaths += unit.positions.flatMap { $0.skills.map { $0.path } }
        }
        var lessonPaths: [String] = []
        if let themeTarget {
            let themes = try readStored(themeTarget, as: ThemeIndexArtifact.self)
            lessonPaths = themes.themes.flatMap { $0.lessons.map { $0.path } }
        }
        var audioIndex: AudioIndexArtifact?
        if let audioTarget { audioIndex = try readStored(audioTarget, as: AudioIndexArtifact.self) }
        let defaultVoice = audioIndex?.voices.first?.id
        let audioPaths = Self.defaultVoicePaths(audioIndex)

        let contentPaths = Self.unique(skillPaths + lessonPaths)
        try await fetchAll(try (contentPaths + audioPaths).map(locate), tracker)

        // Level 3: accepted answers' takes, named only by the exercises.
        var variantPaths: [String] = []
        for path in contentPaths {
            let target = try locate(path)
            guard let data = try store.read(target.key),
                  let skill = try? decoder.decode(VariantSkill.self, from: data) else { continue }
            variantPaths += Self.variantAudioPaths(skill, voice: defaultVoice)
        }
        let known = Set(audioPaths)
        let extra = Self.unique(variantPaths).filter { !known.contains($0) }
        try await fetchAll(try extra.map(locate), tracker)

        try Task.checkCancellation()
        try ContentStoreKeys.markComplete(store, courseCode: courseCode, version: version, manifestSha256: manifestSha256)
    }

    // MARK: - Fetching

    private struct Target: Sendable {
        let key: String
        let url: URL

        /// `audio/<sha256>.<ext>` names its own hash.
        var expectedSha256: String? {
            let parts = key.split(separator: "/")
            guard parts.count == 2, parts[0] == "audio" else { return nil }
            let stem = String(parts[1].split(separator: ".", maxSplits: 1)[0]).lowercased()
            let isHex = stem.count == 64 && stem.allSatisfy { $0.isHexDigit }
            return isHex ? stem : nil
        }
    }

    private func key(for url: URL, courseCode: String, version: Int) throws -> String {
        let parts = cdn.courseRoot(courseCode: courseCode, version: version).split(separator: "/", omittingEmptySubsequences: false)
        let base = parts.dropLast(3).joined(separator: "/") + "/"
        let text = url.absoluteString
        guard text.hasPrefix(base), let decoded = String(text.dropFirst(base.count)).removingPercentEncoding else {
            throw InvalidContentPathError(path: text)
        }
        try ContentStoreKeys.validate(decoded)
        return decoded
    }

    private func fetchAll(_ targets: [Target], _ tracker: Tracker) async throws {
        var seen = Set<String>()
        let unique = targets.filter { seen.insert($0.key).inserted }
        try Task.checkCancellation()
        tracker.discover(unique.count)
        try await withThrowingTaskGroup(of: Void.self) { group in
            var iterator = unique.makeIterator()
            var running = 0
            while running < parallelism, let target = iterator.next() {
                group.addTask { try await self.fetchOne(target, tracker) }
                running += 1
            }
            while try await group.next() != nil {
                try Task.checkCancellation()
                if let target = iterator.next() {
                    group.addTask { try await self.fetchOne(target, tracker) }
                }
            }
        }
    }

    private func fetchOne(_ target: Target, _ tracker: Tracker) async throws {
        let expected = target.expectedSha256
        if let existing = try store.read(target.key) {
            if let expected, Sha256.hex(existing) != expected {
                try store.remove(target.key)
            } else {
                tracker.finished()
                return
            }
        }
        let (data, response) = try await session.data(from: target.url)
        guard let http = response as? HTTPURLResponse else { throw InvalidResponseError() }
        guard (200..<300).contains(http.statusCode) else {
            throw CdnFetchError(url: target.url.absoluteString, status: http.statusCode)
        }
        if let expected {
            let actual = Sha256.hex(data)
            guard actual == expected else {
                throw FileHashMismatchError(path: target.key, expected: expected, actual: actual)
            }
        }
        try Task.checkCancellation()
        try store.write(data, to: target.key)
        tracker.finished()
    }

    // MARK: - Audio selection

    private static func unique(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }

    /// Offline download takes one voice, the default (first listed). Versions
    /// without voices have one take per phrase.
    private static func defaultVoicePaths(_ index: AudioIndexArtifact?) -> [String] {
        guard let index else { return [] }
        guard let voice = index.voices.first?.id else { return index.phrases.map { $0.path } }
        return index.phrases.filter { $0.voice == nil || $0.voice == voice }.map { $0.path }
    }

    private static func variantAudioPaths(_ skill: VariantSkill, voice: String?) -> [String] {
        var result: [String] = []
        for exercise in skill.exercises ?? [] {
            for takes in (exercise.answerVariantAudio ?? []).compactMap({ $0 }) {
                if let voice {
                    if let first = takes[voice]?.first { result.append(first) }
                } else {
                    for name in takes.keys.sorted() {
                        if let first = takes[name]?.first { result.append(first) }
                    }
                }
            }
        }
        return result
    }

    /// Just the part of a skill or lesson file the download reads.
    private struct VariantSkill: Decodable {
        var exercises: [VariantExercise]?
    }

    private struct VariantExercise: Decodable {
        var answerVariantAudio: [AudioMap?]?
    }

    /// Serialises progress callbacks so `done` and `discovered` never go backwards.
    private final class Tracker: @unchecked Sendable {
        private let lock = NSLock()
        private let onProgress: @Sendable (DownloadProgress) -> Void
        private var done = 0
        private var discovered = 0

        init(_ onProgress: @escaping @Sendable (DownloadProgress) -> Void) {
            self.onProgress = onProgress
        }

        func discover(_ count: Int) {
            lock.lock()
            defer { lock.unlock() }
            discovered += count
            onProgress(DownloadProgress(done: done, discovered: discovered))
        }

        func finished() {
            lock.lock()
            defer { lock.unlock() }
            done += 1
            onProgress(DownloadProgress(done: done, discovered: discovered))
        }
    }
}
