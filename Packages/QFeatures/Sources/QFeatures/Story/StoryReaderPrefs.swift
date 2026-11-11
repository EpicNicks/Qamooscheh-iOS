import Foundation

/// The story reader's autoscroll switch: a per-device, per-user bool, on by default. Kept here rather than in
/// LocalPrefs (QData is outside this item's paths); inject a suite for tests.
public final class StoryReaderPrefs: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ userId: String) -> String { "qamooscheh.storyAutoscroll.\(userId)" }

    public func autoscroll(userId: String) -> Bool {
        let k = key(userId)
        if defaults.object(forKey: k) == nil { return true }
        return defaults.bool(forKey: k)
    }

    public func setAutoscroll(_ on: Bool, userId: String) {
        defaults.set(on, forKey: key(userId))
    }
}
