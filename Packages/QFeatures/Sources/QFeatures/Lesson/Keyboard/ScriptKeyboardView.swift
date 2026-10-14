import SwiftUI
import QKeyboard
import QDesign
#if canImport(UIKit)
import UIKit
#endif

private struct KeyFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct HeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private let keyboardSpace = "scriptKeyboard"

/// The in-app keyboard for one input method (Android `ScriptKeyboard`): rows of keys, an
/// optional header in the band above them, and a strip of alternatives above the key that
/// produced the current letter. Tap a candidate, or slide onto one and let go, to swap it in.
public struct ScriptKeyboardView<Header: View>: View {
    @ObservedObject private var state: KeyboardState
    private let textBefore: () -> String
    private let onEdit: (Edit) -> Void
    private let hapticsEnabled: Bool
    private let palette: AppPalette?
    private let header: Header

    @Environment(\.colorScheme) private var colorScheme
    @GestureState private var touching = false
    @State private var headerHeight: CGFloat = 0

    public init(
        state: KeyboardState,
        palette: AppPalette? = nil,
        hapticsEnabled: Bool = true,
        textBefore: @escaping () -> String,
        onEdit: @escaping (Edit) -> Void,
        @ViewBuilder header: () -> Header
    ) {
        self.state = state
        self.palette = palette
        self.hapticsEnabled = hapticsEnabled
        self.textBefore = textBefore
        self.onEdit = onEdit
        self.header = header()
    }

    private var reserve: CGFloat { KeyboardMetrics.bandHeight }
    private var keysTop: CGFloat { KeyboardMetrics.keysTop(headerHeight: headerHeight) }

    public var body: some View {
        let p = palette ?? (colorScheme == .dark ? AppPalette.dark : AppPalette.light)
        let layout = state.layout
        let rects = state.stripRects(reserve: reserve)
        ZStack(alignment: .topLeading) {
            header
                .frame(maxWidth: .infinity, minHeight: reserve, alignment: .leading)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: HeaderHeightKey.self, value: proxy.size.height)
                    }
                )
                .onPreferenceChange(HeaderHeightKey.self) { headerHeight = $0 }
            VStack(spacing: KeyboardMetrics.rowSpacing) {
                ForEach(0..<layout.rows.count, id: \.self) { r in
                    row(layout.rows[r], rowIndex: r, palette: p)
                }
            }
            .padding(.top, keysTop)
            if let list = state.candidates, !rects.isEmpty {
                PhoneticCandidatePicker(candidates: list, rects: rects, hovered: state.hovered, palette: p) { index in
                    onEdit(state.pick(index))
                }
            }
        }
        .padding(.horizontal, KeyboardMetrics.sidePadding)
        .padding(.bottom, KeyboardMetrics.bottomPadding)
        .frame(maxWidth: .infinity)
        .background(Color(argb: p.surface))
        .coordinateSpace(name: keyboardSpace)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: KeyFramesKey.self, value: ["__width": proxy.frame(in: .named(keyboardSpace))])
            }
        )
        .onChange(of: touching) { isDown in
            if !isDown { state.cancelTouch() }
        }
        .onPreferenceChange(KeyFramesKey.self) { frames in
            var keys = frames
            if let w = keys.removeValue(forKey: "__width") { state.width = w.width }
            let before = state.keyFrames
            state.keyFrames.merge(keys, uniquingKeysWith: { _, new in new })
            // The open strip is positioned from these frames, so redraw it once they change.
            if state.anchorKeyId != nil && before != state.keyFrames { state.objectWillChange.send() }
        }
    }

    private func row(_ keys: [Key], rowIndex: Int, palette p: AppPalette) -> some View {
        GeometryReader { proxy in
            let widths = CandidateStripGeometry.keyWidths(weights: keys.map { $0.weight }, total: proxy.size.width, spacing: KeyboardMetrics.keySpacing)
            HStack(spacing: KeyboardMetrics.keySpacing) {
                ForEach(0..<keys.count, id: \.self) { i in
                    keyView(keys[i], id: KeyboardState.keyId(row: rowIndex, index: i), palette: p)
                        .frame(width: widths[i])
                }
            }
            .frame(width: proxy.size.width, alignment: .center)
        }
        .frame(height: KeyboardMetrics.keyHeight)
    }

    @ViewBuilder
    private func keyView(_ key: Key, id: String, palette p: AppPalette) -> some View {
        let cap = VirtualKey(key: key, palette: p)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: KeyFramesKey.self, value: [id: proxy.frame(in: .named(keyboardSpace))])
                }
            )
        if key.enabled {
            cap
                .contentShape(Rectangle())
                .gesture(keyGesture(key, id: id))
                .accessibilityAction(.default) {
                    onEdit(state.press(key.action, keyId: id, textBefore: textBefore()))
                }
        } else {
            cap
        }
    }

    private func keyGesture(_ key: Key, id: String) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(keyboardSpace))
            .updating($touching) { _, isDown, _ in isDown = true }
            .onChanged { value in
                if state.beginTouch(keyId: id) {
                    haptic()
                    onEdit(state.press(key.action, keyId: id, textBefore: textBefore()))
                }
                let rects = state.stripRects(reserve: reserve)
                let over = CandidateStripGeometry.hitIndex(at: value.location, in: rects)
                if over != state.hovered { state.hovered = over }
            }
            .onEnded { _ in
                let over = state.endTouch()
                if let over = over { onEdit(state.pick(over)) }
            }
    }

    private func haptic() {
        #if canImport(UIKit) && !os(macOS)
        if hapticsEnabled {
            UISelectionFeedbackGenerator().selectionChanged()
        }
        #endif
    }
}

public extension ScriptKeyboardView where Header == EmptyView {
    init(
        state: KeyboardState,
        palette: AppPalette? = nil,
        hapticsEnabled: Bool = true,
        textBefore: @escaping () -> String,
        onEdit: @escaping (Edit) -> Void
    ) {
        self.init(state: state, palette: palette, hapticsEnabled: hapticsEnabled, textBefore: textBefore, onEdit: onEdit) { EmptyView() }
    }
}
