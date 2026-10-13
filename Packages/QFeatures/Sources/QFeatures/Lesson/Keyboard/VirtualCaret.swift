import SwiftUI
import QDesign

/// A blinking bar standing in for the answer field's caret while an on-screen keyboard drives
/// it (web `VirtualCaret`). Never takes touches.
public struct VirtualCaret: View {
    private let palette: AppPalette
    private let height: CGFloat
    private let blinks: Bool
    @State private var visible = true

    public init(palette: AppPalette, height: CGFloat = 26, blinks: Bool = true) {
        self.palette = palette
        self.height = height
        self.blinks = blinks
    }

    public var body: some View {
        Rectangle()
            .fill(Color(argb: palette.current))
            .frame(width: 2, height: height)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard blinks else { return }
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}
