import Foundation

// Story reader completion (Qamooscheh-Web#146). PROVISIONAL: the backend path is not built and the contract is not
// final, so names and shape may change. Nothing here is a wire type, URL or network call.

/// A finished read of one story skill: recorded server side as an ungraded completion for the course version,
/// touching no card state. Carries no items. `submissionId` is the offline-queue identity (like a session submit).
public struct StoryReaderCompletionRequest: Equatable, Sendable {
    public var submissionId: String
    public var unitKey: String
    public var skillKey: String
    public var courseCode: String
    public var occurredAt: Date

    public init(submissionId: String = UUID().uuidString, unitKey: String, skillKey: String, courseCode: String, occurredAt: Date) {
        self.submissionId = submissionId
        self.unitKey = unitKey
        self.skillKey = skillKey
        self.courseCode = courseCode
        self.occurredAt = occurredAt
    }
}

/// Hands a completion to the app. The real implementation (a later item) enqueues it on the offline queue the way a
/// session submit is queued; callers neither wait nor see failures.
public protocol StoryReaderCompletionSubmitting: AnyObject {
    func submitCompletion(_ request: StoryReaderCompletionRequest)
}

/// Stub transport: records requests in memory and never touches the network.
public final class RecordingStoryReaderCompletionSubmitter: StoryReaderCompletionSubmitting, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [StoryReaderCompletionRequest] = []

    public init() {}

    public var requests: [StoryReaderCompletionRequest] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    public func submitCompletion(_ request: StoryReaderCompletionRequest) {
        lock.lock()
        stored.append(request)
        lock.unlock()
    }
}

/// Fires the completion once per open of the reader: when the main chain finishes, or the last line is reached.
public final class StoryReaderCompletionTrigger {
    private let submitter: StoryReaderCompletionSubmitting
    private let unitKey: String
    private let skillKey: String
    private let courseCode: String
    private let now: () -> Date
    public private(set) var hasFired = false

    public init(unitKey: String, skillKey: String, courseCode: String, submitter: StoryReaderCompletionSubmitting, now: @escaping () -> Date = { Date() }) {
        self.unitKey = unitKey
        self.skillKey = skillKey
        self.courseCode = courseCode
        self.submitter = submitter
        self.now = now
    }

    /// Call when the chain ended or the last line was reached; later calls do nothing.
    public func fire() {
        if hasFired { return }
        hasFired = true
        submitter.submitCompletion(StoryReaderCompletionRequest(
            unitKey: unitKey, skillKey: skillKey, courseCode: courseCode, occurredAt: now()))
    }
}
