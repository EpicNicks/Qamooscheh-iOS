import Foundation
import QModel
import QNetwork

/// The checkpoint ("test out") endpoints. Online only: the server picks the questions and moves the
/// cursor, so there is no offline fallback (Android LessonRepository.checkpointPlan / submitCheckpoint).
/// Errors surface as `ApiError` (HTTP) or `URLError` (network).
public struct CheckpointRepository: Sendable {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    /// GET /v1/checkpoint/{targetUnitKey}/{targetSkillKey}.
    public func plan(unitKey: String, skillKey: String) async throws -> CheckpointPlanResponse {
        let path = "/v1/checkpoint/\(LessonRepository.pathSegment(unitKey))/\(LessonRepository.pathSegment(skillKey))"
        return try await client.send(.get, path)
    }

    /// POST /v1/checkpoint/submit.
    public func submit(_ request: SubmitCheckpointRequest) async throws -> CheckpointSubmitResponse {
        try await client.send(.post, "/v1/checkpoint/submit", body: request)
    }
}
