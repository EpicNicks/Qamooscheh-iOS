import SwiftUI
import QDesign

/// The arrow the web draws: M12 3 L21 12.5 H15.5 V21 H8.5 V12.5 H3 Z in a 24 box.
struct JumpArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        let u = rect.width / 24
        let ox = rect.minX
        let oy = rect.minY
        var path = Path()
        path.move(to: CGPoint(x: ox + 12 * u, y: oy + 3 * u))
        path.addLine(to: CGPoint(x: ox + 21 * u, y: oy + 12.5 * u))
        path.addLine(to: CGPoint(x: ox + 15.5 * u, y: oy + 12.5 * u))
        path.addLine(to: CGPoint(x: ox + 15.5 * u, y: oy + 21 * u))
        path.addLine(to: CGPoint(x: ox + 8.5 * u, y: oy + 21 * u))
        path.addLine(to: CGPoint(x: ox + 8.5 * u, y: oy + 12.5 * u))
        path.addLine(to: CGPoint(x: ox + 3 * u, y: oy + 12.5 * u))
        path.closeSubpath()
        return path
    }
}

/// Scrolls back to the current lesson once it is off screen (Android JumpToCurrentButton): the arrow points
/// the way it is. A white face with a green ring in both themes.
public struct JumpToCurrentButton: View {
    private let direction: JumpDirection
    private let palette: AppPalette?
    private let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    public init(direction: JumpDirection, palette: AppPalette? = nil, onTap: @escaping () -> Void = {}) {
        self.direction = direction
        self.palette = palette
        self.onTap = onTap
    }

    public var body: some View {
        let p = palette ?? (colorScheme == .dark ? AppPalette.dark : AppPalette.light)
        Button(action: onTap) {
            JumpArrowShape()
                .fill(Color.black)
                .frame(width: 28, height: 28)
                .rotationEffect(.degrees(jumpArrowRotation(direction)))
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.white))
                .overlay(Circle().strokeBorder(Color(argb: p.primary), lineWidth: 3))
                .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: direction)
        .accessibilityLabel("Jump to current lesson")
        .accessibilityAddTraits(.isButton)
    }
}
