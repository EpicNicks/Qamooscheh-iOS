import Foundation
import QModel
import QNetwork

/// GET /v1/lessons/completed (LessonsController.CompletedLessonsResponse).
public struct CompletedLessonsResponse: Codable, Equatable, Sendable {
    public var courseCode: String
    public var completedLessonKeys: [String]

    public init(courseCode: String, completedLessonKeys: [String]) {
        self.courseCode = courseCode
        self.completedLessonKeys = completedLessonKeys
    }
}

/// Lesson endpoints: what to study, a picked lesson's plan, submitting results
/// and the completed-lesson keys. Errors surface as `ApiError` (HTTP) or
/// `URLError` (network); the offline fallbacks of `plan` and `deepDivePlan`
/// mirror the Android LessonRepository.
public struct LessonRepository: Sendable {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    /// GET /v1/sessions/next, raw.
    public func fetchPlan() async throws -> SessionPlanResponse {
        try await client.send(.get, "/v1/sessions/next")
    }

    /// The plan for the next lesson. Offline, or when the server has nothing
    /// due, falls back to the learner's current position (on the device), so a
    /// lesson never waits on the network once the course is downloaded.
    public func plan(course: CourseRef, position: PositionRef?) async throws -> SessionPlanResponse {
        var fallbackSkills: [SkillRef] = []
        if let position = position {
            fallbackSkills = [SkillRef(unitKey: position.unitKey, skillKey: position.skillKey)]
        }
        do {
            var plan = try await fetchPlan()
            if plan.skills.isEmpty {
                plan.skills = fallbackSkills
            }
            return plan
        } catch is URLError {
            return LessonRepository.fallbackPlan(courseVersion: course.version, skills: fallbackSkills)
        }
    }

    /// GET /v1/sessions/for-lesson/{lessonKey}. Nil when the server does not
    /// know the lesson (404). Offline, the lesson is played whole from disk.
    public func deepDivePlan(course: CourseRef, lessonKey: String) async throws -> SessionPlanResponse? {
        do {
            let plan: SessionPlanResponse = try await client.send(
                .get, "/v1/sessions/for-lesson/\(LessonRepository.pathSegment(lessonKey))")
            return plan
        } catch let error as ApiError where error.status == 404 {
            return nil
        } catch is URLError {
            return LessonRepository.fallbackPlan(
                courseVersion: course.version, skills: [SkillRef(unitKey: nil, skillKey: lessonKey)])
        }
    }

    /// POST /v1/sessions/submit. Always an array, even for one session.
    public func submit(_ sessions: [SubmittedSession]) async throws -> SubmitSessionsResponse {
        try await client.send(.post, "/v1/sessions/submit", body: SubmitSessionsRequest(sessions: sessions))
    }

    /// GET /v1/lessons/completed?courseCode=.
    public func completedLessons(courseCode: String) async throws -> CompletedLessonsResponse {
        try await client.send(
            .get, "/v1/lessons/completed?courseCode=\(LessonRepository.queryValue(courseCode))")
    }

    static func fallbackPlan(courseVersion: Int, skills: [SkillRef]) -> SessionPlanResponse {
        SessionPlanResponse(
            courseVersion: courseVersion, skills: skills, reviewTags: [], newTags: [], prefetchTags: [])
    }

    static func pathSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    static func queryValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#?/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
