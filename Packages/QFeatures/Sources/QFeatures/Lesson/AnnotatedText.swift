import SwiftUI
import QDesign
import QDomain
import QModel

// Course-language text, word by word (web AnnotatedText). Ruby technique, matching Android:
// Android has no ruby primitive either, so with a reading to show it lays each word out as a
// small Column (reading above, word below) in a FlowRow. Here that is a VStack per word in
// WordFlowLayout (a custom Layout). CoreText CTRubyAnnotation was not used: it is UIKit-only,
// would need a UIViewRepresentable with its own hit-testing and RTL handling, and Android's
// per-word readings (hint.ruby) are not per-kanji spans anyway.

private struct LessonTextLookKey: EnvironmentKey {
    static let defaultValue = LessonTextLook.standard
}

public extension EnvironmentValues {
    /// How this lesson's course-language text looks; set once per lesson screen.
    var lessonTextLook: LessonTextLook {
        get { self[LessonTextLookKey.self] }
        set { self[LessonTextLookKey.self] = newValue }
    }

    /// The word the current saved-words practice exercise drills (`ExerciseInstance.focusTag`), highlighted wherever it's written.
    var practiceFocusTag: String? {
        get { self[PracticeFocusTagKey.self] }
        set { self[PracticeFocusTagKey.self] = newValue }
    }

    /// The current exercise's lesson's new words (`ExerciseInstance.newLexemes`), highlighted and free to reveal.
    var lessonNewLexemes: Set<String> {
        get { self[LessonNewLexemesKey.self] }
        set { self[LessonNewLexemesKey.self] = newValue }
    }
}

private struct PracticeFocusTagKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

private struct LessonNewLexemesKey: EnvironmentKey {
    static let defaultValue: Set<String> = []
}

private struct WordFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct GapKey: LayoutValueKey {
    static let defaultValue = false
}

/// Flows its subviews in lines, bottom-aligned within a line, right-to-left when `rtl`.
/// A custom Layout cannot read the layout direction, so the caller passes it.
struct WordFlowLayout: Layout {
    var rtl: Bool
    var centered: Bool
    var lineSpacing: CGFloat = 2

    private func items(_ subviews: Subviews) -> [WordFlowGeometry.Item] {
        return subviews.map { WordFlowGeometry.Item(size: $0.sizeThatFits(.unspecified), isGap: $0[GapKey.self]) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let list = items(subviews)
        let natural = list.reduce(CGFloat(0)) { $0 + $1.size.width }
        let width: CGFloat
        if let w = proposal.width, w.isFinite { width = w } else { width = natural }
        let frames = WordFlowGeometry.frames(items: list, width: width, rtl: rtl, centered: centered, lineSpacing: lineSpacing)
        return CGSize(width: width, height: WordFlowGeometry.height(of: frames))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let list = items(subviews)
        let frames = WordFlowGeometry.frames(items: list, width: bounds.width, rtl: rtl, centered: centered, lineSpacing: lineSpacing)
        for (i, subview) in subviews.enumerated() {
            let f = frames[i]
            subview.place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), anchor: .topLeading, proposal: ProposedViewSize(f.size))
        }
    }
}

private extension View {
    func flowGap(_ isGap: Bool) -> some View {
        layoutValue(key: GapKey.self, value: isGap)
    }
}

public struct AnnotatedText: View {
    private let text: String
    private let scriptMode: ExerciseScriptMode
    private let tags: [String]
    private let fontSize: CGFloat
    private let persianFamily: String?
    private let onTip: ((WordTip) -> Void)?

    @Environment(\.lessonTextLook) private var look
    @Environment(\.practiceFocusTag) private var focusTag
    @Environment(\.lessonNewLexemes) private var newLexemes
    @Environment(\.colorScheme) private var colorScheme
    @State private var frames: [Int: CGRect] = [:]

    /// With `onTip` nil (word-bank tiles, which are taps already) nothing is tappable.
    public init(
        _ text: String,
        scriptMode: ExerciseScriptMode,
        tags: [String] = [],
        fontSize: CGFloat = 20,
        persianFamily: String? = nil,
        onTip: ((WordTip) -> Void)? = nil
    ) {
        self.text = text
        self.scriptMode = scriptMode
        self.tags = tags
        self.fontSize = fontSize
        self.persianFamily = persianFamily
        self.onTip = onTip
    }

    public var body: some View {
        let plan = planAnnotatedText(text, scriptMode: scriptMode, tags: tags, look: look, focusTag: focusTag, newLexemes: newLexemes)
        let palette = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        let ink = Color(argb: palette.text)
        let muted = Color(argb: palette.textMuted)
        let marker = Color(argb: palette.warningBg)
        let fresh = Color(argb: palette.infoBg)
        let font = DirectionalText.font(size: fontSize * plan.fontScale, rtl: plan.rtl, family: persianFamily)
        Group {
            if plan.kind == .ruby {
                rubyBody(plan, font: font, ink: ink, muted: muted, marker: marker, fresh: fresh)
            } else {
                inlineBody(plan, font: font, ink: ink, marker: marker, fresh: fresh)
            }
        }
        .directionalText(rtl: plan.rtl)
    }

    /// The practice word's marker, else a new word's blue, behind the word.
    private func highlight(_ run: AnnotatedRun, marker: Color, fresh: Color) -> Color? {
        if run.isFocus { return marker }
        return run.isNew ? fresh : nil
    }

    // One Text, so Persian letters still join across the tappable words.
    private func inlineBody(_ plan: AnnotatedPlan, font: Font, ink: Color, marker: Color, fresh: Color) -> some View {
        var attributed = AttributedString()
        for run in plan.runs {
            var piece = AttributedString(run.text)
            if onTip != nil && run.isTappable, let url = URL(string: "qamooscheh-tip://run/\(run.index)") {
                piece.link = url
                piece.underlineStyle = .single
                piece.foregroundColor = ink
            }
            if let color = highlight(run, marker: marker, fresh: fresh) { piece.backgroundColor = color }
            attributed.append(piece)
        }
        let alignment: Alignment = plan.centered ? .center : .leading
        return Text(attributed)
            .font(font)
            .foregroundStyle(ink)
            .multilineTextAlignment(plan.centered ? .center : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: alignment)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "qamooscheh-tip", let index = Int(url.lastPathComponent),
                      let run = plan.runs.first(where: { $0.index == index }), run.isTappable else { return .discarded }
                onTip?(WordTip(word: run.source, lines: run.tip))
                return .handled
            })
    }

    // A reading over every word, a blank one where there's none, so the line doesn't jump.
    private func rubyBody(_ plan: AnnotatedPlan, font: Font, ink: Color, muted: Color, marker: Color, fresh: Color) -> some View {
        WordFlowLayout(rtl: plan.rtl, centered: plan.centered) {
            ForEach(plan.runs, id: \.index) { run in
                runView(run, font: font, ink: ink, muted: muted, marker: marker, fresh: fresh)
            }
        }
        .frame(maxWidth: .infinity)
        .onPreferenceChange(WordFramesKey.self) { frames = $0 }
    }

    @ViewBuilder
    private func runView(_ run: AnnotatedRun, font: Font, ink: Color, muted: Color, marker: Color, fresh: Color) -> some View {
        if !run.isWord {
            Text(run.text).font(font).foregroundStyle(ink).flowGap(run.isGap)
        } else {
            let cell = VStack(spacing: 0) {
                Text((run.reading ?? "").isEmpty ? " " : (run.reading ?? ""))
                    .font(.system(size: 11))
                    .foregroundStyle(muted)
                Text(run.text).font(font).foregroundStyle(ink)
                    .background(highlight(run, marker: marker, fresh: fresh) ?? Color.clear)
            }
            if onTip != nil && run.isTappable {
                cell
                    .contentShape(Rectangle())
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: WordFramesKey.self, value: [run.index: proxy.frame(in: .global)])
                        }
                    )
                    .onTapGesture {
                        onTip?(WordTip(word: run.source, lines: run.tip, anchor: frames[run.index] ?? .zero))
                    }
                    .accessibilityAddTraits(.isButton)
            } else {
                cell
            }
        }
    }
}

/// The whole sentence romanized above it (web SentenceRomanization).
public struct SentenceRomanization: View {
    private let text: String
    private let authored: String?
    private let scriptMode: ExerciseScriptMode
    private let tags: [String]

    @Environment(\.lessonTextLook) private var look
    @Environment(\.colorScheme) private var colorScheme

    public init(_ text: String, authored: String? = nil, scriptMode: ExerciseScriptMode, tags: [String] = []) {
        self.text = text
        self.authored = authored
        self.scriptMode = scriptMode
        self.tags = tags
    }

    public var body: some View {
        if let line = sentenceRomanizationLine(text, authored: authored, scriptMode: scriptMode, tags: tags, look: look) {
            let palette = colorScheme == .dark ? AppPalette.dark : AppPalette.light
            Text(line)
                .font(.system(size: 15))
                .foregroundStyle(Color(argb: palette.textMuted))
                .environment(\.layoutDirection, .leftToRight)
        }
    }
}
