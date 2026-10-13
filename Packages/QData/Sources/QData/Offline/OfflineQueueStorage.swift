import Foundation

/// Byte-level storage behind `OfflineQueue`: one named blob per user.
/// Implementations must make `write` atomic (all-or-nothing) and must throw,
/// never silently succeed, when the bytes could not be persisted.
public protocol OfflineQueueStorage: Sendable {
    /// The blob for `name`, or nil when it does not exist. Throws on I/O errors.
    func read(_ name: String) throws -> Data?
    func write(_ name: String, _ data: Data) throws
    func remove(_ name: String) throws
    /// Names of all stored blobs (used to clear quarantined leftovers).
    func list() throws -> [String]
    /// Identifies the storage location; queues with equal keys share one process-wide lock.
    var lockKey: String { get }
}

/// Files in a directory, written atomically (temp file then rename).
public struct FileOfflineQueueStorage: OfflineQueueStorage {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func read(_ name: String) throws -> Data? {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func write(_ name: String, _ data: Data) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name), options: [.atomic])
    }

    public var lockKey: String { directory.standardizedFileURL.path }

    public func list() throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
    }

    public func remove(_ name: String) throws {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

/// Dictionary-backed storage for tests and previews.
public final class InMemoryOfflineQueueStorage: OfflineQueueStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var blobs: [String: Data] = [:]
    private var failWrites = false

    public init() {}

    /// Test hook: while true, `write` throws and leaves the stored bytes untouched.
    public func setFailWrites(_ fail: Bool) {
        lock.lock(); defer { lock.unlock() }
        failWrites = fail
    }

    public var lockKey: String { "mem-" + String(UInt(bitPattern: ObjectIdentifier(self).hashValue)) }

    public func list() throws -> [String] { names }

    public var names: [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(blobs.keys)
    }

    public func read(_ name: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return blobs[name]
    }

    public func write(_ name: String, _ data: Data) throws {
        lock.lock(); defer { lock.unlock() }
        if failWrites { throw CocoaError(.fileWriteUnknown) }
        blobs[name] = data
    }

    public func remove(_ name: String) throws {
        lock.lock(); defer { lock.unlock() }
        blobs[name] = nil
    }
}
