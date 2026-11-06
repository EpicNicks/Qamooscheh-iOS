import Foundation
import QData
import QModel

/// Tells the Learn tab that a lesson was submitted, so the shell reloads the bootstrap and the path moves on.
/// A pass that cleared a stowed lesson names it, and the path drops it from the Stowage at once.
public enum LessonSubmitRefresh {
    public static let notification = Notification.Name("QamooschehLessonSubmitted")
    static let stowClearedKey = "stowCleared"
    static let completedSkillKeyKey = "completedSkillKey"

    /// Posts `notification` (on the main thread) when the server answered for the session.
    /// `session` names the lesson; a graded completion carries its skill key so the Journey can animate it.
    public static func announce(_ result: LessonSubmitResult, session: SubmittedSession? = nil, center: NotificationCenter = .default) {
        guard case .submitted(let response) = result else { return }
        let cleared = response.stowCleared
        let completed = (session?.completed == true && response.lessonCompleted != false) ? session?.skillKey : nil
        DispatchQueue.main.async {
            var info: [AnyHashable: Any] = [:]
            if let key = cleared { info[stowClearedKey] = key }
            if let key = completed { info[completedSkillKeyKey] = key }
            center.post(name: notification, object: nil, userInfo: info.isEmpty ? nil : info)
        }
    }

    /// The graded lesson this submit completed, if any.
    public static func completedSkillKey(in note: Notification) -> String? {
        note.userInfo?[completedSkillKeyKey] as? String
    }

    /// The stowed lesson this submit cleared, if any.
    public static func stowCleared(in note: Notification) -> String? {
        note.userInfo?[stowClearedKey] as? String
    }
}
