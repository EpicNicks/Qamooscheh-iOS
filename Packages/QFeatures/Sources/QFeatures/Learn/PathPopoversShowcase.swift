import SwiftUI
import QModel
import QDomain
import QDesign

public enum PathPopoversPage: Sendable {
    /// The popover for a current, a completed and a locked lesson.
    case popovers
    /// The group sheet with mixed states, then the Deep Dive chooser with remix.
    case sheets
    /// The Deep Dive chooser for a single-root lesson.
    case chooser
}

/// Gallery for snapshot tests, one page per screenful.
public struct PathPopoversShowcase: View {
    private let page: PathPopoversPage
    private let rtl: Bool

    @Environment(\.colorScheme) private var colorScheme

    public init(page: PathPopoversPage, rtl: Bool = false) {
        self.page = page
        self.rtl = rtl
    }

    static let themeIndex = ThemeIndexArtifact(themes: [
        ThemeEntry(id: "Food", parentId: nil, lessons: [ThemeLessonRef(id: "b1", path: "b1"), ThemeLessonRef(id: "c", path: "c")]),
        ThemeEntry(id: "Fruit", parentId: "Food", lessons: [ThemeLessonRef(id: "b1", path: "b1")]),
        ThemeEntry(id: "Travel", parentId: nil, lessons: [ThemeLessonRef(id: "c", path: "c")]),
    ])

    public var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        VStack(spacing: 16) {
            switch page {
            case .popovers:
                popovers()
            case .sheets:
                groupSheet(p)
                sheetFrame(p) { DeepDiveSheetView(lessonKey: "c", themeIndex: PathPopoversShowcase.themeIndex) }
            case .chooser:
                sheetFrame(p) { DeepDiveSheetView(lessonKey: "b1", themeIndex: PathPopoversShowcase.themeIndex) }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(argb: p.bg))
        .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
    }

    private var skip: PositionKey { PositionKey(unitKey: "u1", skillKey: "d1") }

    @ViewBuilder
    private func popovers() -> some View {
        let positions = PathRoadFixtures.positions()
        popover(positions[2].skills[0])
        popover(positions[0].skills[0])
        popover(positions[3].skills[0])
    }

    private func popover(_ skill: PathSkill) -> some View {
        let a = lessonPopoverActions(skill, nextSkipTarget: skip, themeIndex: PathPopoversShowcase.themeIndex)
        let view = LessonStartPopoverView(
            primaryLabel: a.primaryLabel,
            description: skill.title,
            onDeepDive: a.hasDeepDive ? {} : nil,
            onSkip: a.skipTarget == nil ? nil : {},
            onReviewVocabulary: {}
        )
        return view
            .clipShape(RoundedRectangle(cornerRadius: Radii.standard.md))
            .overlay(RoundedRectangle(cornerRadius: Radii.standard.md).strokeBorder(Color.gray.opacity(0.5), lineWidth: 2))
    }

    private func groupSheet(_ p: AppPalette) -> some View {
        let fork = PathRoadFixtures.positions()[1].skills
        let skipTarget = skip
        return sheetFrame(p) {
            SkillGroupSheetView(
                skills: fork,
                actions: { lessonPopoverActions($0, nextSkipTarget: skipTarget, themeIndex: PathPopoversShowcase.themeIndex) },
                selected: 1
            )
        }
    }

    private func sheetFrame<Content: View>(_ p: AppPalette, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(height: 380)
            .clipShape(RoundedRectangle(cornerRadius: Radii.standard.lg))
            .overlay(RoundedRectangle(cornerRadius: Radii.standard.lg).strokeBorder(Color(argb: p.border), lineWidth: 2))
    }
}
