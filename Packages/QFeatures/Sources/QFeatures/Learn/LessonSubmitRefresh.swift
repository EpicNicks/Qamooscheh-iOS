import Foundation
import QData

/// Tells the Learn tab that a lesson was submitted, so the shell reloads the bootstrap and the path moves on.
/// A pass that cleared a stowed lesson names it, and the path drops it from the Stowage at once.
public enum LessonSubmitRefresh {
    public static let notification = Notification.Name("QamooschehLessonSubmitted")
    static let stowClearedKey = "stowCleared"

    /// Posts `notification` (on the main thread) when the server answered for the session.
    public static func announce(_ result: LessonSubmitResult, center: NotificationCenter = .default) {
        guard case .submitted(let response) = result else { return }
        let cleared = response.stowCleared
        DispatchQueue.main.async {
            var info: [AnyHashable: Any]?
            if let key = cleared { info = [stowClearedKey: key] }
            center.post(name: notification, object: nil, userInfo: info)
        }
    }

    /// The stowed lesson this submit cleared, if any.
    public static func stowCleared(in note: Notification) -> String? {
        note.userInfo?[stowClearedKey] as? String
    }
}
