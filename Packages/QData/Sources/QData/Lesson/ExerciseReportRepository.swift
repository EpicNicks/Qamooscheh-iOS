import Foundation
import QModel
import QNetwork

/// A learner's report that an exercise itself is wrong (Android LessonRepository.report). Online only:
/// a report that can't be sent fails, and the form says so. Errors surface as `ApiError` (HTTP) or `URLError` (network).
public struct ExerciseReportRepository: Sendable {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    /// POST /v1/exercise-reports.
    @discardableResult
    public func submit(_ request: SubmitExerciseReportRequest) async throws -> SubmitExerciseReportResponse {
        try await client.send(.post, "/v1/exercise-reports", body: request)
    }
}
