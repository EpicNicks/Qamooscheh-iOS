import Foundation

/// Where downloaded course files live. Keys are paths relative to the CDN base
/// (for example "course/fa/v3/units/u1.json" or "audio/<sha256>.mp3"), so the
/// course tree is pinned per version while audio is shared and hash-addressed.
/// Writes must be atomic: a key that reads back is a whole file.
public protocol ContentFileStore: Sendable {
    func read(_ key: String) throws -> Data?
    func write(_ data: Data, to key: String) throws
    func remove(_ key: String) throws
}

public struct InvalidStoreKeyError: Error, Equatable, Sendable {
    public let key: String

    public init(key: String) {
        self.key = key
    }
}

public enum ContentStoreKeys {
    /// Marker written only after every file of a version has verified.
    public static func completeMarker(courseCode: String, version: Int) -> String {
        "course/\(courseCode)/v\(version)/.complete"
    }

    public static func isComplete(_ store: ContentFileStore, courseCode: String, version: Int, manifestSha256: String) -> Bool {
        let key = completeMarker(courseCode: courseCode, version: version)
        guard let data = try? store.read(key), let text = String(data: data, encoding: .utf8) else { return false }
        return text.lowercased() == manifestSha256.lowercased()
    }

    public static func markComplete(_ store: ContentFileStore, courseCode: String, version: Int, manifestSha256: String) throws {
        try store.write(Data(manifestSha256.lowercased().utf8), to: completeMarker(courseCode: courseCode, version: version))
    }

    static func validate(_ key: String) throws {
        let parts = key.split(separator: "/", omittingEmptySubsequences: false)
        let bad = key.isEmpty || key.hasPrefix("/") || key.contains("\\")
            || parts.contains(where: { $0.isEmpty || $0 == ".." || $0 == "." })
        if bad { throw InvalidStoreKeyError(key: key) }
    }
}

/// FileManager-backed store rooted at a directory. Writes are atomic
/// (unique temp file, then atomic replace).
public struct FileContentStore: ContentFileStore {
    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    private func fileURL(_ key: String) throws -> URL {
        try ContentStoreKeys.validate(key)
        return root.appendingPathComponent(key, isDirectory: false)
    }

    public func read(_ key: String) throws -> Data? {
        let url = try fileURL(key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func write(_ data: Data, to key: String) throws {
        let url = try fileURL(key)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Data's atomic write uses a unique temp file and an atomic replace,
        // so concurrent writers of the same key are safe.
        try data.write(to: url, options: .atomic)
    }

    public func remove(_ key: String) throws {
        let url = try fileURL(key)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

/// In-memory store for tests and previews.
public final class InMemoryContentStore: ContentFileStore, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private var writeLog: [String] = []

    public init() {}

    public func read(_ key: String) throws -> Data? {
        try ContentStoreKeys.validate(key)
        lock.lock()
        defer { lock.unlock() }
        return files[key]
    }

    public func write(_ data: Data, to key: String) throws {
        try ContentStoreKeys.validate(key)
        lock.lock()
        defer { lock.unlock() }
        files[key] = data
        writeLog.append(key)
    }

    public func remove(_ key: String) throws {
        try ContentStoreKeys.validate(key)
        lock.lock()
        defer { lock.unlock() }
        files[key] = nil
    }

    public var keys: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(files.keys)
    }

    /// Every key written, in order, including rewrites.
    public var writes: [String] {
        lock.lock()
        defer { lock.unlock() }
        return writeLog
    }
}
