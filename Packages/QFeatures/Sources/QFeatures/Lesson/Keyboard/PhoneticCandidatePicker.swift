import SwiftUI
import QDesign

/// The strip of alternatives drawn above the pressed key (Android `ScriptKeyboard` candidate
/// cells). `rects` are in the parent's coordinate space; the first candidate (already typed)
/// is highlighted unless a drag is over another.
public struct PhoneticCandidatePicker: View {
    private let candidates: [String]
    private let rects: [CGRect]
    private let hovered: Int?
    private let palette: AppPalette
    private let onPick: (Int) -> Void

    public init(candidates: [String], rects: [CGRect], hovered: Int?, palette: AppPalette, onPick: @escaping (Int) -> Void) {
        self.candidates = candidates
        self.rects = rects
        self.hovered = hovered
        self.palette = palette
        self.onPick = onPick
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<min(candidates.count, rects.count), id: \.self) { index in
                cell(index)
            }
        }
    }

    private func cell(_ index: Int) -> some View {
        let active = index == hovered || (index == 0 && hovered == nil)
        let shape = RoundedRectangle(cornerRadius: 10)
        let rect = rects[index]
        return Button(action: { onPick(index) }) {
            Text(candidates[index])
                .font(.system(size: 24))
                .foregroundColor(Color(argb: active ? palette.primaryContrast : palette.text))
                .frame(width: rect.width, height: rect.height)
                .background(shape.fill(Color(argb: active ? palette.current : palette.bg)))
                .overlay(shape.stroke(Color(argb: palette.border), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use \(candidates[index])")
        .offset(x: rect.minX, y: rect.minY)
    }
}
