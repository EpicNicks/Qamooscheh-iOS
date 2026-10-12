import SwiftUI
import QDesign

/// "Skip ahead" into the next unit (web PlacementTestNode, Android PlacementTestNode): the one node
/// that behaves unlike every other locked node, so it gets its own hue and a dashed border.
public struct PlacementTestNodeView: View {
    private let palette: AppPalette?
    private let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    public init(palette: AppPalette? = nil, onTap: @escaping () -> Void = {}) {
        self.palette = palette
        self.onTap = onTap
    }

    public var body: some View {
        let p = palette ?? (colorScheme == .dark ? AppPalette.dark : AppPalette.light)
        let radius = Radii.standard.md
        Button(action: onTap) {
            HStack(spacing: Spacing.standard.s3) {
                Text("\u{26A1}")
                    .font(.system(size: 20))
                    .foregroundColor(Color(argb: p.placement))
                Text("Skip ahead")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(argb: p.placement))
                Spacer(minLength: 0)
            }
            .padding(Spacing.standard.s3)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(Color(argb: lerpARGB(p.surface, p.placement, 0.14)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Color(argb: p.placement), style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Skip ahead")
        .accessibilityAddTraits(.isButton)
    }
}
