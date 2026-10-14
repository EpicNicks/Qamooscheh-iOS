import Foundation
import QModel
import QNetwork

/// The three onboarding steps, in the order the web flow and Android use.
public enum OnboardingStep: String, Equatable, CaseIterable, Sendable {
    case name
    case languages
    case tutorial
}

/// The calls the onboarding view model needs; `OnboardingApi` conforms.
public protocol OnboardingService: Sendable {
    func catalog() async throws -> [CourseCatalogEntry]
    func setDisplayName(_ displayName: String) async throws -> ProfileResponse
    func enrollAll(courseCodes: [String], active: String) async throws -> BootstrapResponse
    func completeOnboarding() async throws -> Bool
    func enroll(courseCode: String) async throws -> BootstrapResponse
    func switchActive(courseCode: String) async throws -> BootstrapResponse
}

extension OnboardingApi: OnboardingService {}

/// Remembers the current step across a relaunch (Android keeps it in SavedStateHandle).
public protocol OnboardingStepStore: AnyObject {
    var step: OnboardingStep? { get set }
}

/// Keeps the step for the life of the object only.
public final class InMemoryOnboardingStepStore: OnboardingStepStore {
    public var step: OnboardingStep?

    public init(step: OnboardingStep? = nil) {
        self.step = step
    }
}

/// Persists the step in UserDefaults under `key` (use a per-user key).
public final class UserDefaultsOnboardingStepStore: OnboardingStepStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String) {
        self.defaults = defaults
        self.key = key
    }

    public var step: OnboardingStep? {
        get { defaults.string(forKey: key).flatMap(OnboardingStep.init(rawValue:)) }
        set {
            if let value = newValue {
                defaults.set(value.rawValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

/// Builds the per-account UserDefaults key for the saved step.
public enum OnboardingStepKey {
    public static func make(prefix: String, userId: String) -> String {
        "\(prefix).\(userId)"
    }
}

/// Limits and user-visible strings (web onboarding pages, Android OnboardingViewModel).
public enum OnboardingRules {
    /// ProfileService.MaxDisplayNameLength.
    public static let maxNameLength = 40

    public static let nameFallback = "Couldn't save that name."
    public static let enrollFallback = "Couldn't finish setting up your courses. Please try again."
    public static let catalogFallback = "Couldn't load the course list."
}
