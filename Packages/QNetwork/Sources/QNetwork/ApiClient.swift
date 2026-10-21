import Foundation
import QModel

/// HTTP method for an API request.
public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

/// The one place that talks to Qamooscheh.Api. Attaches the bearer token,
/// refreshes up front near expiry, and on a 401 refreshes once (shared across
/// concurrent callers) and retries the request exactly once. A refresh that is
/// definitively rejected clears the session and throws SessionExpiredError.
public actor ApiClient {
    /// How close to expiry a token must be before it is refreshed up front.
    public static let expiryRefreshBuffer: TimeInterval = 30

    private let baseURL: URL
    private let clientHeader: String
    private let session: URLSession
    private let store: SessionStore
    private let now: @Sendable () -> Date
    private let timeZoneProvider: @Sendable () -> String?
    private let onSessionExpired: (@Sendable () -> Void)?
    private let decoder = QJSON.makeDecoder()
    private let encoder = QJSON.makeEncoder()
    private var refreshTask: Task<String, Error>?

    public init(
        baseURL: URL,
        clientHeader: String,
        session: URLSession = .shared,
        store: SessionStore,
        now: @escaping @Sendable () -> Date = { Date() },
        timeZoneProvider: @escaping @Sendable () -> String? = { TimeZone.current.identifier },
        onSessionExpired: (@Sendable () -> Void)? = nil
    ) {
        self.baseURL = baseURL
        self.clientHeader = clientHeader
        self.session = session
        self.store = store
        self.now = now
        self.timeZoneProvider = timeZoneProvider
        self.onSessionExpired = onSessionExpired
    }

    // MARK: Public requests

    /// Sends a request and decodes the JSON response.
    public func send<Response: Decodable>(
        _ method: HTTPMethod,
        _ path: String,
        body: (any Encodable)? = nil,
        anonymous: Bool = false,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let data = try await sendRaw(method, path, body: body, anonymous: anonymous)
        return try decoder.decode(Response.self, from: data)
    }

    /// Sends a request whose response body is ignored (204 or otherwise).
    public func sendNoContent(
        _ method: HTTPMethod,
        _ path: String,
        body: (any Encodable)? = nil,
        anonymous: Bool = false
    ) async throws {
        _ = try await sendRaw(method, path, body: body, anonymous: anonymous)
    }

    /// Sends a request and returns the raw response bytes.
    public func sendRaw(
        _ method: HTTPMethod,
        _ path: String,
        body: (any Encodable)? = nil,
        anonymous: Bool = false
    ) async throws -> Data {
        var bodyData: Data? = nil
        if let body = body {
            bodyData = try encoder.encode(AnyEncodable(body))
        }
        let stored: StoredSession? = anonymous ? nil : await store.load()

        var accessToken: String? = stored?.accessToken
        if let stored = stored, isExpiringSoon(stored.accessTokenExpiresAt) {
            do {
                accessToken = try await refreshAccessToken()
            } catch is SessionExpiredError {
                throw SessionExpiredError()
            } catch is StaleRefreshError {
                // The session changed mid-refresh; keep going only if it is still this account.
                accessToken = try await currentToken(for: stored.userId)
            } catch {
                // Transient refresh failure (5xx/408/429/network): the access token
                // may still be valid, so send with it. A 401 takes the normal path.
            }
        }

        var result = try await perform(method, path, bodyData: bodyData, accessToken: accessToken)

        if result.1.statusCode == 401 && !anonymous && stored != nil {
            // Another caller may have refreshed while this request was in
            // flight; only refresh when storage still holds the token we used.
            // Never retry under a different account's token.
            let current = await store.load()
            if let current = current, current.userId != stored?.userId { throw AccountChangedError() }
            let retryToken: String
            if let current = current, current.accessToken != accessToken {
                retryToken = current.accessToken
            } else {
                retryToken = try await refreshOrCurrent(for: stored?.userId)
            }
            result = try await perform(method, path, bodyData: bodyData, accessToken: retryToken)
        }

        // The account changed while the request was out: the response is not this user's to apply.
        if let stored = stored {
            let now = await store.load()
            if now?.userId != stored.userId { throw AccountChangedError() }
        }

        let data = result.0
        let status = result.1.statusCode
        guard (200..<300).contains(status) else {
            throw ApiError(status: status, body: try? decoder.decode(ApiErrorBody.self, from: data))
        }
        return data
    }

    // MARK: Internals

    private func isExpiringSoon(_ expiresAt: Date) -> Bool {
        expiresAt.timeIntervalSince(now()) <= ApiClient.expiryRefreshBuffer
    }

    private func perform(
        _ method: HTTPMethod, _ path: String, bodyData: Data?, accessToken: String?
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url(for: path))
        request.httpMethod = method.rawValue
        if let bodyData = bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let accessToken = accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(clientHeader, forHTTPHeaderField: "X-Client")
            if let zone = timeZoneProvider() {
                request.setValue(zone, forHTTPHeaderField: "X-Time-Zone")
            }
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw InvalidResponseError() }
        return (data, http)
    }

    private func url(for path: String) -> URL {
        URL(string: baseURL.absoluteString + path) ?? baseURL.appendingPathComponent(path)
    }

    /// Refreshes, but if the session was replaced mid-flight returns the new
    /// session's token instead of failing; throws SessionExpiredError if none remains.
    private func refreshOrCurrent(for userId: String?) async throws -> String {
        do {
            return try await refreshAccessToken()
        } catch is StaleRefreshError {
            return try await currentToken(for: userId)
        }
    }

    /// The signed-in token, provided it still belongs to `userId`.
    private func currentToken(for userId: String?) async throws -> String {
        guard let current = await store.load() else { throw SessionExpiredError() }
        if let userId = userId, current.userId != userId { throw AccountChangedError() }
        return current.accessToken
    }

    /// Refreshes once at a time; concurrent callers share the in-flight task.
    private func refreshAccessToken() async throws -> String {
        if let task = refreshTask { return try await task.value }
        let task = Task { try await self.performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> String {
        guard let start = await store.load() else { throw SessionExpiredError() }

        var request = URLRequest(url: url(for: "/v1/auth/refresh"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientHeader, forHTTPHeaderField: "X-Client")
        request.httpBody = try encoder.encode(RefreshRequest(refreshToken: start.refreshToken))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw InvalidResponseError() }

        // The user may have signed out or in as someone else mid-flight.
        let stillCurrent = await isCurrent(start)
        if !stillCurrent { throw StaleRefreshError() }

        guard (200..<300).contains(http.statusCode) else {
            // Only a briefly unwell API is recoverable; anything else ends the session.
            let retryable = http.statusCode == 408 || http.statusCode == 429 || http.statusCode >= 500
            if retryable {
                throw ApiError(status: http.statusCode, body: try? decoder.decode(ApiErrorBody.self, from: data))
            }
            await store.clear()
            onSessionExpired?()
            throw SessionExpiredError()
        }

        let auth = try decoder.decode(AuthResponse.self, from: data)
        let stillCurrentAfterDecode = await isCurrent(start)
        if !stillCurrentAfterDecode { throw StaleRefreshError() }
        // The old refresh token is spent. If the new one can't be kept, end the session now:
        // the spent token left on disk would trip reuse detection at the next launch.
        let saved = await store.saveChecked(StoredSession(
            userId: auth.userId,
            accessToken: auth.accessToken,
            accessTokenExpiresAt: auth.accessTokenExpiresAt,
            refreshToken: auth.refreshToken))
        guard saved == .saved else {
            await store.clear()
            onSessionExpired?()
            throw SessionExpiredError()
        }
        return auth.accessToken
    }

    private func isCurrent(_ start: StoredSession) async -> Bool {
        guard let current = await store.load() else { return false }
        return current.userId == start.userId && current.refreshToken == start.refreshToken
    }
}

/// Type-erases an Encodable existential for JSONEncoder.
struct AnyEncodable: Encodable {
    private let value: any Encodable

    init(_ value: any Encodable) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}
