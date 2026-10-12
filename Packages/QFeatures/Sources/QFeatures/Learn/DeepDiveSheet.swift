import SwiftUI
import QModel
import QDomain
import QDesign

/// Deep Dive (Android DeepDiveSheet): remix every topic the lesson touches when it has more than one
/// root topic, or browse one topic at any depth. Sheet content; the caller presents it.
public struct DeepDiveSheetView: View {
    private let content: DeepDiveContent
    private let palette: AppPalette?
    private let onRemix: () -> Void
    private let onOpenTheme: (String) -> Void
    private let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    public init(
        lessonKey: String,
        themeIndex: ThemeIndexArtifact?,
        palette: AppPalette? = nil,
        onRemix: @escaping () -> Void = {},
        onOpenTheme: @escaping (String) -> Void = { _ in },
        onDismiss: @escaping () -> Void = {}
    ) {
        self.content = deepDiveContent(themeIndex: themeIndex, lessonKey: lessonKey)
        self.palette = palette
        self.onRemix = onRemix
        self.onOpenTheme = onOpenTheme
        self.onDismiss = onDismiss
    }

    public var body: some View {
        let p = palette ?? (colorScheme == .dark ? AppPalette.dark : AppPalette.light)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.standard.s2) {
                Text("Deep Dive")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Color(argb: p.text))
                Text(content.intro)
                    .font(.system(size: 16))
                    .foregroundColor(Color(argb: p.textMuted))
                if content.showRemix {
                    PathPopupButton(text: "Remix all topics", kind: .deepDive, palette: p) { onDismiss(); onRemix() }
                    if content.showsPickPrompt {
                        Text("Or pick one topic:")
                            .font(.system(size: 16))
                            .foregroundColor(Color(argb: p.textMuted))
                    }
                }
                ForEach(Array(content.rows.enumerated()), id: \.offset) { _, row in
                    topicRow(row, palette: p)
                }
            }
            .padding(.horizontal, Spacing.standard.s3)
            .padding(.top, Spacing.standard.s4)
            .padding(.bottom, Spacing.standard.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(argb: p.bg).ignoresSafeArea())
    }

    private func topicRow(_ row: DeepDiveRow, palette p: AppPalette) -> some View {
        Button {
            onDismiss()
            onOpenTheme(row.themeId)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(row.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(argb: p.deepDive))
                Text(row.themeId)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(argb: p.text))
            }
            .padding(.horizontal, Spacing.standard.s3)
            .padding(.vertical, Spacing.standard.s2)
            .frame(maxWidth: 520, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radii.standard.sm).fill(Color(argb: lerpARGB(p.surface, p.deepDive, row.tint))))
            .overlay(RoundedRectangle(cornerRadius: Radii.standard.sm).strokeBorder(Color(argb: p.deepDive).opacity(row.borderAlpha), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .padding(.leading, CGFloat(row.step) * 16)
    }
}
