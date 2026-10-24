import Foundation

/// One stowed lesson in the Stowage.
public struct StowedLesson: Codable, Equatable, Sendable {
    public var lessonKey: String
    public var stowedAt: Date
    public var lessonsCompletedSince: Int
    public var readyPromptDue: Bool
    public var muted: Bool

    public init(lessonKey: String, stowedAt: Date, lessonsCompletedSince: Int, readyPromptDue: Bool, muted: Bool) {
        self.lessonKey = lessonKey
        self.stowedAt = stowedAt
        self.lessonsCompletedSince = lessonsCompletedSince
        self.readyPromptDue = readyPromptDue
        self.muted = muted
    }
}

/// Stowed lessons of one unit, lessons ascending by position.
public struct StowageUnit: Codable, Equatable, Sendable {
    public var unitKey: String
    public var lessons: [StowedLesson]

    public init(unitKey: String, lessons: [StowedLesson]) {
        self.unitKey = unitKey
        self.lessons = lessons
    }
}

/// POST /v1/journey/stow body.
public struct StowRequest: Codable, Equatable, Sendable {
    public var lessonKey: String

    public init(lessonKey: String) {
        self.lessonKey = lessonKey
    }
}

/// POST /v1/journey/stow response. `applied` is false for an idempotent repeat.
public struct StowResponse: Codable, Equatable, Sendable {
    public var applied: Bool
    public var position: PositionRef
    public var stowage: [StowageUnit]

    public init(applied: Bool, position: PositionRef, stowage: [StowageUnit]) {
        self.applied = applied
        self.position = position
        self.stowage = stowage
    }
}

/// POST /v1/journey/stowage/snooze and /mute response.
public struct StowageResponse: Codable, Equatable, Sendable {
    public var applied: Bool
    public var stowage: [StowageUnit]

    public init(applied: Bool, stowage: [StowageUnit]) {
        self.applied = applied
        self.stowage = stowage
    }
}
