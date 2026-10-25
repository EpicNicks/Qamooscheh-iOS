import Foundation
import QModel
import QDomain

// SwiftUI-free rules for the lesson popover, skill group sheet and Deep Dive sheet
// (Android PathActions.kt skillActions + PathPopups.kt).

/// Everything a lesson's popover or group sheet offers (Android SkillActions, minus the closures).
public struct LessonPopoverActions: Equatable, Sendable {
    public var primaryLabel: String
    public var startsLesson: Bool
    /// "Test out" target; nil hides the button.
    public var skipTarget: PositionKey?
    /// Whether this lesson is a standard one tagged with any theme.
    public var hasDeepDive: Bool
    /// "Stow": the last action; only for a key the server lists as stowable.
    public var stowOffered: Bool

    public init(primaryLabel: String, startsLesson: Bool, skipTarget: PositionKey?, hasDeepDive: Bool, stowOffered: Bool = false) {
        self.primaryLabel = primaryLabel
        self.startsLesson = startsLesson
        self.skipTarget = skipTarget
        self.hasDeepDive = hasDeepDive
        self.stowOffered = stowOffered
    }
}

public func lessonPopoverActions(_ skill: PathSkill, nextSkipTarget: PositionKey?, themeIndex: ThemeIndexArtifact?, stowableLessonKeys: Set<String> = []) -> LessonPopoverActions {
    let base = skillActions(skill, nextSkipTarget: nextSkipTarget, stowableLessonKeys: stowableLessonKeys)
    let tagged = !themesForLesson(themeIndex, lessonKey: skill.skillKey).isEmpty
    return LessonPopoverActions(
        primaryLabel: base.primaryLabel,
        startsLesson: base.startsLesson,
        skipTarget: base.skipTarget,
        hasDeepDive: skill.category == .standard && tagged,
        stowOffered: base.stowOffered
    )
}

/// The group sheet's selection, kept inside the list (Android coerceIn).
public func clampedSelection(_ index: Int, count: Int) -> Int {
    if count <= 0 { return 0 }
    return min(max(index, 0), count - 1)
}

/// One topic button in the Deep Dive sheet.
public struct DeepDiveRow: Equatable, Sendable {
    public var themeId: String
    public var depth: Int
    /// Indent steps (16pt each): depth - 1, at most 5.
    public var step: Int
    /// Surface-to-deepDive mix, 0.08 per step.
    public var tint: Double
    /// Border alpha: 0.35 + 0.13 per step.
    public var borderAlpha: Double

    public var title: String { "Dive Level \(depth)" }
}

/// What the Deep Dive sheet shows (Android DeepDiveSheet).
public struct DeepDiveContent: Equatable, Sendable {
    /// More than one root topic: offer "Remix all topics".
    public var showRemix: Bool
    public var rows: [DeepDiveRow]

    public var intro: String {
        showRemix
            ? "Practice a blend across everything this lesson touches on, or pick one topic to browse."
            : "Pick a topic to browse \u{2014} go broad, or dive deeper into something specific."
    }

    /// "Or pick one topic:" only sits under the remix button.
    public var showsPickPrompt: Bool { showRemix && !rows.isEmpty }
}

public func deepDiveContent(themeIndex: ThemeIndexArtifact?, lessonKey: String) -> DeepDiveContent {
    let rows = dfsThemesForLesson(themeIndex, lessonKey: lessonKey).map { item -> DeepDiveRow in
        let step = min(max(item.depth - 1, 0), 5)
        return DeepDiveRow(
            themeId: item.theme.id,
            depth: item.depth,
            step: step,
            tint: Double(step) * 0.08,
            borderAlpha: 0.35 + Double(step) * 0.13
        )
    }
    return DeepDiveContent(showRemix: rootThemesForLesson(themeIndex, lessonKey: lessonKey).count > 1, rows: rows)
}
