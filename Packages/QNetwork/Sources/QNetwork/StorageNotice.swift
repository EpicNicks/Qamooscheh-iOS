import Foundation

/// Raised when a session can't be saved because the device is out of space. The app shows one
/// plain alert on whatever screen is up; the posters never touch UI.
public final class StorageNotice: @unchecked Sendable {
    public static let shared = StorageNotice()
    public static let message = "Your device is low on storage, so the app may not work as intended."

    /// Below this much free space a failed write counts as low storage.
    public static let lowBytes: Int64 = 50 * 1024 * 1024

    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?

    public init() {}

    /// Set by the app's root view. Posts before a handler is set are dropped.
    public func setHandler(_ handler: (@Sendable () -> Void)?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    public func post() {
        lock.lock()
        let current = handler
        lock.unlock()
        current?()
    }

    /// Free bytes for important-usage writes on the main volume, or nil when unknown.
    public static func freeBytes() -> Int64? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let free = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return free
    }
}
