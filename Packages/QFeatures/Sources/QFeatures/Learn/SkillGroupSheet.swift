import SwiftUI
import QDomain
import QDesign

/// A collapsed fork's lessons (Android SkillGroupSheet): pick one, then act on it. Sheet content; the
/// caller presents it with `skillGroupSheet`. Every action but Deep Dive dismisses first.
public struct SkillGroupSheetView: View {
    private let skills: [PathSkill]
    private let actions: (PathSkill) -> LessonPopoverActions
    private let theme: PathTheme
    private let palette: AppPalette?
    private let onPrimary: (PathSkill) -> Void
    private let onDeepDive: (PathSkill) -> Void
    private let onSkip: (PathSkill, PositionKey) -> Void
    private let onReviewVocabulary: (PathSkill) -> Void
    private let onDismiss: () -> Void

    @State private var selected: Int

    @Environment(\.colorScheme) private var colorScheme

    public init(
        skills: [PathSkill],
        actions: @escaping (PathSkill) -> LessonPopoverActions,
        selected: Int = 0,
        theme: PathTheme = .standard,
        palette: AppPalette? = nil,
        onPrimary: @escaping (PathSkill) -> Void = { _ in },
        onDeepDive: @escaping (PathSkill) -> Void = { _ in },
        onSkip: @escaping (PathSkill, PositionKey) -> Void = { _, _ in },
        onReviewVocabulary: @escaping (PathSkill) -> Void = { _ in },
        onDismiss: @escaping () -> Void = {}
    ) {
        self.skills = skills
        self.actions = actions
        self.theme = theme
        self.palette = palette
        self.onPrimary = onPrimary
        self.onDeepDive = onDeepDive
        self.onSkip = onSkip
        self.onReviewVocabulary = onReviewVocabulary
        self.onDismiss = onDismiss
        self._selected = State(initialValue: selected)
    }

    public var body: some View {
        let p = palette ?? (colorScheme == .dark ? AppPalette.dark : AppPalette.light)
        ScrollView {
            if !skills.isEmpty {
                content(palette: p)
            }
        }
        .background(Color(argb: p.bg).ignoresSafeArea())
    }

    private func content(palette p: AppPalette) -> some View {
        let index = clampedSelection(selected, count: skills.count)
        let active = skills[index]
        let a = actions(active)
        return VStack(spacing: Spacing.standard.s2) {
            VStack(spacing: Spacing.standard.s2) {
                ForEach(Array(skills.enumerated()), id: \.offset) { offset, skill in
                    row(skill, selected: offset == index, palette: p)
                        .onTapGesture { selected = offset }
                }
            }
            PathPopupButton(text: a.primaryLabel, kind: .primary, palette: p) { onDismiss(); onPrimary(active) }
            if a.hasDeepDive {
                PathPopupButton(text: "Deep Dive", kind: .deepDive, palette: p) { onDeepDive(active) }
            }
            if let target = a.skipTarget {
                PathPopupButton(text: "Test out", kind: .secondary, palette: p) { onDismiss(); onSkip(active, target) }
            }
            PathPopupButton(text: "Review vocabulary", kind: .secondary, palette: p) { onDismiss(); onReviewVocabulary(active) }
        }
        .padding(.horizontal, Spacing.standard.s3)
        .padding(.top, Spacing.standard.s4)
        .padding(.bottom, Spacing.standard.s3)
    }

    private func row(_ skill: PathSkill, selected: Bool, palette p: AppPalette) -> some View {
        HStack(spacing: Spacing.standard.s2) {
            if let icon = theme.icons[skill.category] {
                Text(icon)
            }
            Text(skill.title)
                .font(.system(size: 16, weight: selected ? .bold : .regular))
                .foregroundColor(Color(argb: p.text))
                .frame(maxWidth: .infinity, alignment: .leading)
            if skill.completed {
                Text("\u{2713}")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(argb: p.current))
                    .accessibilityLabel("Completed")
            }
        }
        .padding(Spacing.standard.s3)
        .background(RoundedRectangle(cornerRadius: Radii.standard.md).fill(Color(argb: selected ? p.surface : p.bg)))
        .overlay(RoundedRectangle(cornerRadius: Radii.standard.md).strokeBorder(Color(argb: selected ? p.current : p.border), lineWidth: 2))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

public extension View {
    /// Presents sheet content as a bottom sheet that opens expanded (Android ModalBottomSheet, skipPartiallyExpanded).
    func pathBottomSheet<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        sheet(isPresented: isPresented) {
            content().presentationDetents(pathSheetDetents)
        }
    }
}

/// The Path bottom sheet opens at the large detent only, as Android opens it expanded.
public let pathSheetDetents: Set<PresentationDetent> = [.large]
