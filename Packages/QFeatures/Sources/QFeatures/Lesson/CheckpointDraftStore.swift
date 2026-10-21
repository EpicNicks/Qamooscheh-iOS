import Foundation

/// A finished checkpoint's answers with the identity they will be sent under, kept so a killed app resumes at "Ready to submit"
/// and the retry reuses the same submission id and time.
public struct CheckpointDraft: Codable, Equatable, Sendable {
    public var submissionId: String
    public var occurredAt: Date
    /// Instance key to submitted text.
    public var answers: [String: String]

    public init(submissionId: String, occurredAt: Date, answers: [String: String]) {
        self.submissionId = submissionId
        self.occurredAt = occurredAt
        self.answers = answers
    }
}

public struct CheckpointDraftStore: Sendable {
    public var load: @Sendable () -> CheckpointDraft?
    public var save: @Sendable (CheckpointDraft) -> Void
    public var clear: @Sendable () -> Void

    public init(
        load: @escaping @Sendable () -> CheckpointDraft?,
        save: @escaping @Sendable (CheckpointDraft) -> Void,
        clear: @escaping @Sendable () -> Void
    ) {
        self.load = load
        self.save = save
        self.clear = clear
    }

    /// Keeps nothing.
    public static let none = CheckpointDraftStore(load: { nil }, save: { _ in }, clear: {})

    /// The checkpoint's key: its lesson-draft key plus a suffix, so sign-out's per-user sweep finds it too.
    public static func key(lessonKey: String) -> String { lessonKey + "|answers" }

    /// One JSON file under `directory`. Write failures are swallowed (a lost draft only costs the resume).
    public static func file(directory: URL, key: String) -> CheckpointDraftStore {
        let url = directory.appendingPathComponent(LessonDraftStore.fileName(for: key))
        return CheckpointDraftStore(
            load: {
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(CheckpointDraft.self, from: data)
            },
            save: { draft in
                guard let data = try? JSONEncoder().encode(draft) else { return }
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? data.write(to: url, options: .atomic)
            },
            clear: { try? FileManager.default.removeItem(at: url) }
        )
    }
}
