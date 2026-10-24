import Foundation
import QModel

/// Why a Stow call was refused. Anything not in the contract stays an `ApiError`.
public enum StowError: Error, Equatable, Sendable {
    /// 400 invalid_request: lessonKey missing or blank.
    case invalidRequest
    /// 404 unknown_lesson: no such skill in the active course.
    case unknownLesson
    /// 409 not_current_position: not a journey lesson.
    case notCurrentPosition
    /// 409 no_failed_attempt: no finished failed attempt (or already passed).
    case noFailedAttempt
    /// 409 already_cleared: stowed and later passed.
    case alreadyCleared
    /// 409 already_dropped: dropped from the Stowage.
    case alreadyDropped
    /// 409 not_provisioned: the account has no active course.
    case notProvisioned

    /// Maps a contract `{error, reason}` failure; nil for any other failure.
    static func from(_ error: ApiError) -> StowError? {
        guard let reason = error.body?.reason else { return nil }
        switch (error.status, reason) {
        case (400, "invalid_request"): return .invalidRequest
        case (404, "unknown_lesson"): return .unknownLesson
        case (409, "not_current_position"): return .notCurrentPosition
        case (409, "no_failed_attempt"): return .noFailedAttempt
        case (409, "already_cleared"): return .alreadyCleared
        case (409, "already_dropped"): return .alreadyDropped
        case (409, "not_provisioned"): return .notProvisioned
        default: return nil
        }
    }
}

/// Stow a failed journey lesson, and snooze or mute its reminder. Online-only.
/// Contract failures throw `StowError`; others (401, 5xx, transport) propagate unchanged.
public struct StowApi: Sendable {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    /// POST /v1/journey/stow.
    public func stow(lessonKey: String) async throws -> StowResponse {
        do {
            return try await client.send(.post, "/v1/journey/stow", body: StowRequest(lessonKey: lessonKey))
        } catch let error as ApiError {
            throw StowError.from(error) ?? error
        }
    }

    /// POST /v1/journey/stowage/snooze (no body): "Not yet".
    public func snoozeStowage() async throws -> StowageResponse {
        try await postStowage("/v1/journey/stowage/snooze")
    }

    /// POST /v1/journey/stowage/mute (no body): the X button.
    public func muteStowage() async throws -> StowageResponse {
        try await postStowage("/v1/journey/stowage/mute")
    }

    private func postStowage(_ path: String) async throws -> StowageResponse {
        do {
            return try await client.send(.post, path)
        } catch let error as ApiError {
            throw StowError.from(error) ?? error
        }
    }
}
