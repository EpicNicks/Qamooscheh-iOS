import Foundation
import QModel
import QNetwork

/// The Repack race (backend Race/, API_SPEC 2.8b). The deck is built and graded on the device like any cloze round; the
/// server issues the FSRS weights at `start`, then times the run and recomputes the score at `finish`. A race needs the
/// network at both ends. Errors surface as `ApiError` (HTTP) or `URLError` (network).
public struct RaceRepository: Sendable {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    /// iOS is always a touch device.
    public static let deviceClass: RaceDeviceClass = .touch

    /// POST /v1/race/runs: opens a run for the deck's `tags`; the response says which of them are learned words (the rest must not be dealt).
    public func start(courseCode: String, mode: RaceMode, hardcore: Bool, tags: [String]) async throws -> StartRaceResponse {
        let body = StartRaceRequest(courseCode: courseCode, mode: mode, hardcore: hardcore, deviceClass: RaceRepository.deviceClass, tags: tags)
        return try await client.send(.post, "/v1/race/runs", body: body)
    }

    /// POST /v1/race/runs/{id}/finish: ends the run with every answer in order. Finishing twice is safe: the server answers with what it banked.
    public func finish(runId: String, answers: [RaceAnswer], deckDone: Bool) async throws -> FinishRaceResponse {
        guard RaceRepository.isRunId(runId) else { throw URLError(.badURL) }
        return try await client.send(.post, "/v1/race/runs/\(runId)/finish", body: FinishRaceRequest(answers: answers, deckDone: deckDone))
    }

    /// GET /v1/race/boards: Perfect Delivery's board; `weekOf` (any date, `yyyy-MM-dd`) picks the week for the weekly scope.
    public func board(courseCode: String, scope: RaceScope, hardcore: Bool, weekOf: String? = nil) async throws -> RaceBoardResponse {
        var query = [
            URLQueryItem(name: "courseCode", value: courseCode),
            URLQueryItem(name: "mode", value: RaceMode.perfectDelivery.rawValue),
            URLQueryItem(name: "scope", value: scope.rawValue),
            URLQueryItem(name: "deviceClass", value: RaceRepository.deviceClass.rawValue),
            URLQueryItem(name: "hardcore", value: hardcore ? "true" : "false"),
        ]
        if let weekOf = weekOf { query.append(URLQueryItem(name: "week", value: weekOf)) }
        var components = URLComponents()
        components.queryItems = query
        let encoded = components.percentEncodedQuery ?? ""
        return try await client.send(.get, "/v1/race/boards?\(encoded)")
    }

    /// A run id is a GUID; anything else would put other characters into the path.
    static func isRunId(_ text: String) -> Bool {
        return UUID(uuidString: text) != nil
    }
}
