import Foundation


/// PUT /v1/prefs.
public struct UpdatePrefsRequest: Codable, Equatable, Sendable {
    public var scriptMode: ScriptMode
    public var register: Register
    public var autoplayAudio: Bool
    public var keyboardMode: KeyboardMode
    public var desiredRetention: Double
    public var dailyGoalXp: Int
    public var preferredVoice: String?

    public init(scriptMode: ScriptMode, register: Register, autoplayAudio: Bool, keyboardMode: KeyboardMode, desiredRetention: Double, dailyGoalXp: Int, preferredVoice: String? = nil) {
        self.scriptMode = scriptMode
        self.register = register
        self.autoplayAudio = autoplayAudio
        self.keyboardMode = keyboardMode
        self.desiredRetention = desiredRetention
        self.dailyGoalXp = dailyGoalXp
        self.preferredVoice = preferredVoice
    }
}

/// GET /v1/prefs.
public struct PrefsResponse: Codable, Equatable, Sendable {
    public var scriptMode: ScriptMode
    public var register: Register
    public var autoplayAudio: Bool
    public var keyboardMode: KeyboardMode
    public var desiredRetention: Double
    public var dailyGoalXp: Int
    public var preferredVoice: String?

    public init(scriptMode: ScriptMode, register: Register, autoplayAudio: Bool, keyboardMode: KeyboardMode, desiredRetention: Double, dailyGoalXp: Int, preferredVoice: String? = nil) {
        self.scriptMode = scriptMode
        self.register = register
        self.autoplayAudio = autoplayAudio
        self.keyboardMode = keyboardMode
        self.desiredRetention = desiredRetention
        self.dailyGoalXp = dailyGoalXp
        self.preferredVoice = preferredVoice
    }
}

/// PUT /v1/profile.
public struct UpdateProfileRequest: Codable, Equatable, Sendable {
    public var displayName: String
    public var fullName: String?
    public var country: String?

    public init(displayName: String, fullName: String? = nil, country: String? = nil) {
        self.displayName = displayName
        self.fullName = fullName
        self.country = country
    }
}

/// GET /v1/profile.
public struct ProfileResponse: Codable, Equatable, Sendable {
    public var displayName: String?
    public var fullName: String?
    public var country: String?

    public init(displayName: String? = nil, fullName: String? = nil, country: String? = nil) {
        self.displayName = displayName
        self.fullName = fullName
        self.country = country
    }
}
