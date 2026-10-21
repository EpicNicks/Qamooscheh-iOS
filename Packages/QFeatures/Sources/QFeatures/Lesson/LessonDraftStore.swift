import Foundation

/// Where a lesson in progress is kept so a killed app resumes it (Android keeps `LessonState` in a SavedStateHandle).
/// One draft per user + lesson; written after every step, cleared when the lesson is saved or left.
public struct LessonDraftStore: Sendable {
    public var load: @Sendable () -> LessonState?
    public var save: @Sendable (LessonState) -> Void
    public var clear: @Sendable () -> Void

    public init(
        load: @escaping @Sendable () -> LessonState?,
        save: @escaping @Sendable (LessonState) -> Void,
        clear: @escaping @Sendable () -> Void
    ) {
        self.load = load
        self.save = save
        self.clear = clear
    }

    /// Keeps nothing.
    public static let none = LessonDraftStore(load: { nil }, save: { _ in }, clear: {})

    /// The draft's identity: the user and the lesson (a practice run and a counted run of one skill are different lessons).
    public static func key(userId: String, courseCode: String, unitKey: String?, skillKey: String, practice: Bool, checkpoint: Bool) -> String {
        let parts = [userId, courseCode, unitKey ?? "-", skillKey, practice ? "practice" : "counted", checkpoint ? "checkpoint" : "lesson"]
        return parts.joined(separator: "|")
    }

    /// A file-safe name for a key.
    public static func fileName(for key: String) -> String {
        var out = ""
        for scalar in key.unicodeScalars {
            let v = scalar.value
            let safe = (v >= 48 && v <= 57) || (v >= 65 && v <= 90) || (v >= 97 && v <= 122) || v == 45 || v == 46 || v == 95
            out += safe ? String(scalar) : "_"
        }
        return out + ".json"
    }

    /// One JSON file per key under `directory`. Write failures are swallowed (a lost draft only costs the resume).
    public static func file(directory: URL, key: String) -> LessonDraftStore {
        let url = directory.appendingPathComponent(fileName(for: key))
        return LessonDraftStore(
            load: {
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(LessonState.self, from: data)
            },
            save: { state in
                guard let data = try? JSONEncoder().encode(state) else { return }
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? data.write(to: url, options: .atomic)
            },
            clear: { try? FileManager.default.removeItem(at: url) }
        )
    }
}

extension LessonDraftStore {
    /// Deletes every draft file the user owns under `directory` (sign-out cleanup).
    public static func removeAll(directory: URL, userId: String) {
        guard !userId.isEmpty else { return }
        let prefix = String(fileName(for: userId + "|").dropLast(".json".count))
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}

/// An in-memory draft, for tests.
public final class MemoryLessonDraft: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: LessonState?
    public private(set) var clears = 0

    public init(_ initial: LessonState? = nil) { stored = initial }

    public var state: LessonState? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    public var store: LessonDraftStore {
        LessonDraftStore(
            load: { [self] in state },
            save: { [self] next in
                lock.lock()
                stored = next
                lock.unlock()
            },
            clear: { [self] in
                lock.lock()
                stored = nil
                clears += 1
                lock.unlock()
            }
        )
    }
}
