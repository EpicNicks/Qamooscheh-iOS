import Foundation
import CryptoKit
import QModel
import QNetwork

/// The `v1/contacts` routes (API_SPEC.md 2.6, Contacts matching).
public struct ContactsRepository: Sendable {
    /// Most hashes one match call accepts.
    public static let maxHashesPerCall = 500
    /// A caller's distinct-hash allowance per day (the server answers 429 past it).
    public static let maxHashesPerDay = 1000

    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    /// GET /v1/contacts/findable.
    public func findable() async throws -> ContactsFindableResponse {
        try await client.send(.get, "/v1/contacts/findable")
    }

    /// PUT /v1/contacts/findable.
    public func setFindable(_ value: Bool) async throws -> ContactsFindableResponse {
        try await client.send(.put, "/v1/contacts/findable", body: SetContactsFindableRequest(findable: value))
    }

    /// POST /v1/contacts/match. Callers pass at most `maxHashesPerCall` hashes.
    public func match(_ hashes: [String]) async throws -> [ContactMatchResponse] {
        let response: ContactsMatchResponse = try await client.send(
            .post, "/v1/contacts/match", body: ContactsMatchRequest(hashes: hashes))
        return response.matches
    }
}

/// How a contact email becomes the hash the server matches on.
public enum ContactHashing {
    /// Trimmed and lower-cased; nil when nothing is left.
    public static func normalize(_ email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Lower-case hex SHA-256 of the UTF-8 bytes.
    public static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The hash of one email, or nil when it normalises to nothing.
    public static func hash(email: String) -> String? {
        normalize(email).map(sha256Hex)
    }

    /// Distinct hashes in first-seen order, at most `limit`. Raw emails never leave this function.
    public static func hashes(emails: [String], limit: Int) -> (hashes: [String], truncated: Bool) {
        var seen = Set<String>()
        var out: [String] = []
        var truncated = false
        for email in emails {
            guard let h = hash(email: email), !seen.contains(h) else { continue }
            if out.count >= limit {
                truncated = true
                break
            }
            seen.insert(h)
            out.append(h)
        }
        return (out, truncated)
    }
}
