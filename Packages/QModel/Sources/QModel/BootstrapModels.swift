import Foundation


/// Active course pin.
public struct CourseRef: Codable, Equatable, Sendable {
    public var code: String
    public var version: Int
    public var manifestSha256: String

    public init(code: String, version: Int, manifestSha256: String) {
        self.code = code
        self.version = version
        self.manifestSha256 = manifestSha256
    }
}

/// Learner position.
public struct PositionRef: Codable, Equatable, Sendable {
    public var unitKey: String
    public var skillKey: String

    public init(unitKey: String, skillKey: String) {
        self.unitKey = unitKey
        self.skillKey = skillKey
    }
}

/// Grader artifact pin.
public struct GraderRef: Codable, Equatable, Sendable {
    public var language: String
    public var variant: String
    public var version: Int
    public var manifestSha256: String

    public init(language: String, variant: String, version: Int, manifestSha256: String) {
        self.language = language
        self.variant = variant
        self.version = version
        self.manifestSha256 = manifestSha256
    }
}

/// Newer course version offer.
public struct CourseUpdateRef: Codable, Equatable, Sendable {
    public var version: Int
    public var manifestSha256: String
    public var eligible: Bool
    public var notes: String?

    public init(version: Int, manifestSha256: String, eligible: Bool, notes: String? = nil) {
        self.version = version
        self.manifestSha256 = manifestSha256
        self.eligible = eligible
        self.notes = notes
    }
}

/// GET /v1/bootstrap.
public struct BootstrapResponse: Codable, Equatable, Sendable {
    public var course: CourseRef?
    public var position: PositionRef?
    public var graders: [GraderRef]
    public var enrolledCourseCodes: [String]
    public var onboardingComplete: Bool
    public var update: CourseUpdateRef?
    /// Stowed lessons by unit, units in descending position order. Empty when absent.
    public var stowage: [StowageUnit]
    /// Lesson keys at the cursor that pass the Stow gate, sorted by key. Empty when absent.
    public var stowableLessonKeys: [String]

    public init(course: CourseRef? = nil, position: PositionRef? = nil, graders: [GraderRef], enrolledCourseCodes: [String], onboardingComplete: Bool, update: CourseUpdateRef? = nil, stowage: [StowageUnit] = [], stowableLessonKeys: [String] = []) {
        self.course = course
        self.position = position
        self.graders = graders
        self.enrolledCourseCodes = enrolledCourseCodes
        self.onboardingComplete = onboardingComplete
        self.update = update
        self.stowage = stowage
        self.stowableLessonKeys = stowableLessonKeys
    }

    private enum CodingKeys: String, CodingKey {
        case course, position, graders, enrolledCourseCodes, onboardingComplete, update, stowage, stowableLessonKeys
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.course = try c.decodeIfPresent(CourseRef.self, forKey: .course)
        self.position = try c.decodeIfPresent(PositionRef.self, forKey: .position)
        self.graders = try c.decode([GraderRef].self, forKey: .graders)
        self.enrolledCourseCodes = try c.decode([String].self, forKey: .enrolledCourseCodes)
        self.onboardingComplete = try c.decode(Bool.self, forKey: .onboardingComplete)
        self.update = try c.decodeIfPresent(CourseUpdateRef.self, forKey: .update)
        self.stowage = try c.decodeIfPresent([StowageUnit].self, forKey: .stowage) ?? []
        self.stowableLessonKeys = try c.decodeIfPresent([String].self, forKey: .stowableLessonKeys) ?? []
    }
}

/// One course in the catalog.
public struct CourseCatalogEntry: Codable, Equatable, Sendable {
    public var code: String
    public var nativeName: String
    public var latinName: String
    public var cultureFacts: [String]

    public init(code: String, nativeName: String, latinName: String, cultureFacts: [String]) {
        self.code = code
        self.nativeName = nativeName
        self.latinName = latinName
        self.cultureFacts = cultureFacts
    }
}

/// GET /v1/courses.
public struct CourseCatalogResponse: Codable, Equatable, Sendable {
    public var courses: [CourseCatalogEntry]

    public init(courses: [CourseCatalogEntry]) {
        self.courses = courses
    }
}

/// Switch the active course.
public struct SwitchActiveCourseRequest: Codable, Equatable, Sendable {
    public var courseCode: String

    public init(courseCode: String) {
        self.courseCode = courseCode
    }
}

/// Roll the pin forward.
public struct RollForwardRequest: Codable, Equatable, Sendable {
    public var toVersion: Int

    public init(toVersion: Int) {
        self.toVersion = toVersion
    }
}

/// A position in a roll-forward preview.
public struct RollForwardPositionRef: Codable, Equatable, Sendable {
    public var unitKey: String
    public var skillKey: String
    public var unitIndex: Int
    public var lessonIndex: Int

    public init(unitKey: String, skillKey: String, unitIndex: Int, lessonIndex: Int) {
        self.unitKey = unitKey
        self.skillKey = skillKey
        self.unitIndex = unitIndex
        self.lessonIndex = lessonIndex
    }
}

/// Roll-forward preview.
public struct RollForwardPreviewResponse: Codable, Equatable, Sendable {
    public var courseCode: String
    public var fromVersion: Int
    public var toVersion: Int
    public var manifestSha256: String
    public var updateNotes: String?
    public var from: RollForwardPositionRef?
    public var to: RollForwardPositionRef?
    public var clamped: Bool
    public var unitClamped: Bool
    public var lessonClamped: Bool

    public init(courseCode: String, fromVersion: Int, toVersion: Int, manifestSha256: String, updateNotes: String? = nil, from: RollForwardPositionRef? = nil, to: RollForwardPositionRef? = nil, clamped: Bool, unitClamped: Bool, lessonClamped: Bool) {
        self.courseCode = courseCode
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.manifestSha256 = manifestSha256
        self.updateNotes = updateNotes
        self.from = from
        self.to = to
        self.clamped = clamped
        self.unitClamped = unitClamped
        self.lessonClamped = lessonClamped
    }
}

/// Onboarding completion.
public struct OnboardingCompleteResponse: Codable, Equatable, Sendable {
    public var onboardingComplete: Bool

    public init(onboardingComplete: Bool) {
        self.onboardingComplete = onboardingComplete
    }
}
