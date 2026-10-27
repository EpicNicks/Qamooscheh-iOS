import Foundation

// The local "Hint warning" preference: whether to ask before a hint is revealed,
// because a hint halves the award. Device-local, default on.

public protocol HintWarningPrefs: AnyObject {
    /// True (the default) when the learner wants to be asked before a hint is revealed.
    var showsHintWarning: Bool { get set }
}

public final class UserDefaultsHintWarningPrefs: HintWarningPrefs {
    public static let key = "pref.hintWarning"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var showsHintWarning: Bool {
        get { defaults.object(forKey: Self.key) == nil ? true : defaults.bool(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}

/// Whether to ask before a hint is revealed.
public enum HintWarningGate {
    /// Ask only when the learner has the warning on and this answer has not already used a hint (a second reveal costs nothing more).
    public static func shouldWarn(prefEnabled: Bool, hintAlreadyUsed: Bool) -> Bool {
        return prefEnabled && !hintAlreadyUsed
    }

    public static func shouldWarn(prefs: HintWarningPrefs, hintAlreadyUsed: Bool) -> Bool {
        return shouldWarn(prefEnabled: prefs.showsHintWarning, hintAlreadyUsed: hintAlreadyUsed)
    }
}
