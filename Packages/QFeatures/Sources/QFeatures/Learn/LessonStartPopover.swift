import SwiftUI
import QDesign

/// What tapping a lesson offers (Android LessonStartPopover): start or practice, Deep Dive, test out,
/// review vocabulary. Plain values and closures; routing belongs to the caller.
public struct LessonStartPopoverView: View {
    private let primaryLabel: String
    private let description: String?
    private let palette: AppPalette?
    private let onPrimary: () -> Void
    private let onDeepDive: (() -> Void)?
    private let onSkip: (() -> Void)?
    private let onReviewVocabulary: (() -> Void)?
    private let onStow: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    public init(
        primaryLabel: String,
        description: String? = nil,
        palette: AppPalette? = nil,
        onPrimary: @escaping () -> Void = {},
        onDeepDive: (() -> Void)? = nil,
        onSkip: (() -> Void)? = nil,
        onReviewVocabulary: (() -> Void)? = nil,
        onStow: (() -> Void)? = nil
    ) {
        self.primaryLabel = primaryLabel
        self.description = description
        self.palette = palette
        self.onPrimary = onPrimary
        self.onDeepDive = onDeepDive
        self.onSkip = onSkip
        self.onReviewVocabulary = onReviewVocabulary
        self.onStow = onStow
    }

    public var body: some View {
        let p = palette ?? (colorScheme == .dark ? AppPalette.dark : AppPalette.light)
        VStack(spacing: Spacing.standard.s2) {
            if let description = description {
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(Color(argb: p.text))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            PathPopupButton(text: primaryLabel, kind: .primary, palette: p, action: onPrimary)
            if let onDeepDive = onDeepDive {
                PathPopupButton(text: "Deep Dive", kind: .deepDive, palette: p, action: onDeepDive)
            }
            if let onSkip = onSkip {
                PathPopupButton(text: "Test out", kind: .secondary, palette: p, action: onSkip)
            }
            if let onReviewVocabulary = onReviewVocabulary {
                PathPopupButton(text: "Review vocabulary", kind: .secondary, palette: p, action: onReviewVocabulary)
            }
            // Stow is always the last action (stow-placement). Only the journey screen passes it.
            if let onStow = onStow {
                PathPopupButton(text: StowCopy.actionLabel, kind: .secondary, palette: p, action: onStow)
            }
        }
        .padding(Spacing.standard.s3)
        .frame(width: 240)
        .background(Color(argb: p.bg))
    }
}

public extension View {
    /// Anchors a lesson popover to this node, above it (Android Popup above the node, flipping below;
    /// the system flips when there is no room). Stays a popover on iPhone instead of adapting to a sheet.
    func lessonStartPopover<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        popover(isPresented: isPresented, arrowEdge: .bottom) {
            content().presentationCompactAdaptation(.popover)
        }
    }
}

enum PathPopupButtonKind {
    case primary
    case deepDive
    case secondary
}

/// The buttons the popover and sheets share: solid primary, solid purple Deep Dive, outlined secondary.
struct PathPopupButton: View {
    let text: String
    let kind: PathPopupButtonKind
    let palette: AppPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(foreground)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: Radii.standard.md).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: Radii.standard.md).strokeBorder(stroke, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private var fill: Color {
        switch kind {
        case .primary: return Color(argb: palette.primary)
        case .deepDive: return Color(argb: palette.deepDive)
        case .secondary: return Color(argb: palette.bg)
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Color(argb: palette.primaryContrast)
        case .deepDive: return Color.white
        case .secondary: return Color(argb: palette.text)
        }
    }

    private var stroke: Color {
        kind == .secondary ? Color(argb: palette.border) : Color.clear
    }
}
