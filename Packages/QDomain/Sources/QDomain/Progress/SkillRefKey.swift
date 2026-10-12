import Foundation
import QModel

/// "unitKey/skillKey", null-safe: the shared key convention for skill-artifact maps, since a theme lesson's unitKey can be nil.
public func refKey(_ ref: SkillRef) -> String {
    return "\(ref.unitKey ?? "_")/\(ref.skillKey)"
}
