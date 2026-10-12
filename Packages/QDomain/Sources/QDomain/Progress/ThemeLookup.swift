import Foundation
import QModel

/// Every theme bucket (in themes.json) that lists this lesson key; a lesson typically has 1-3.
public func themesForLesson(_ themeIndex: ThemeIndexArtifact?, lessonKey: String) -> [ThemeEntry] {
    guard let themeIndex = themeIndex else { return [] }
    return themeIndex.themes.filter { theme in theme.lessons.contains { $0.id == lessonKey } }
}
