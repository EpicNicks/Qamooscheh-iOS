import Foundation
import QModel

/// Typed calls the onboarding flow needs: the course catalog, the display name,
/// enrollment and the onboarding-complete flag. Errors surface as `ApiError`.
public struct OnboardingApi: Sendable {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    /// GET /v1/courses.
    public func catalog() async throws -> [CourseCatalogEntry] {
        let response: CourseCatalogResponse = try await client.send(.get, "/v1/courses")
        return response.courses
    }

    /// PUT /v1/profile with only the display name (the endpoint is a full overwrite; full name and country go as null).
    @discardableResult
    public func setDisplayName(_ displayName: String) async throws -> ProfileResponse {
        let body = UpdateProfileRequest(
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            fullName: nil, country: nil)
        return try await client.send(.put, "/v1/profile", body: body)
    }

    /// POST /v1/courses/{code}/enroll. Idempotent server-side.
    @discardableResult
    public func enroll(courseCode: String) async throws -> BootstrapResponse {
        try await client.send(.post, "/v1/courses/\(OnboardingApi.pathSegment(courseCode))/enroll")
    }

    /// PUT /v1/courses/active.
    @discardableResult
    public func switchActive(courseCode: String) async throws -> BootstrapResponse {
        try await client.send(
            .put, "/v1/courses/active", body: SwitchActiveCourseRequest(courseCode: courseCode))
    }

    /// Enrolls in each course one after another (every answer is a full bootstrap, so no
    /// concurrency), then makes `active` the active course. Returns only the final
    /// bootstrap: applying an earlier one would already count as onboarded.
    public func enrollAll(courseCodes: [String], active: String) async throws -> BootstrapResponse {
        for code in courseCodes {
            _ = try await enroll(courseCode: code)
        }
        return try await switchActive(courseCode: active)
    }

    /// POST /v1/onboarding/complete (no body). Always true when it succeeds.
    public func completeOnboarding() async throws -> Bool {
        let response: OnboardingCompleteResponse = try await client.send(.post, "/v1/onboarding/complete")
        return response.onboardingComplete
    }

    static func pathSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
