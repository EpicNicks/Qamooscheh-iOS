import Foundation
import QModel
import QData

/// The learner's rough spots (GET /v1/sessions/rough-spots): the words they keep missing, each with the exercises that practise it.
public protocol RoughSpotsSource: Sendable {
    /// Up to `count` words; `words: []` means nothing is rough. Throws the server's 400 and 409 as `ApiError`.
    func roughSpots(count: Int) async throws -> StarredPracticeResponse
}

/// How many rough-spot words one Repack takes (the server's default).
public let roughSpotsWordCount = 10

/// Rough spots over the sessions endpoint.
public struct LiveRoughSpotsSource: RoughSpotsSource {
    private let repository: RoughSpotsRepository

    public init(repository: RoughSpotsRepository) {
        self.repository = repository
    }

    public func roughSpots(count: Int) async throws -> StarredPracticeResponse {
        try await repository.roughSpots(words: count)
    }
}
