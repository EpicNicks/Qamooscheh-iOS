import SwiftUI
import QModel
import QDomain
import QDesign

/// Type the answer (web TypeInExercise, Android `TypeInExercise`). With the in-app keyboard the
/// field only shows the text, since the keys below edit it, and the system keyboard stays down;
/// otherwise it is an ordinary field on the phone's keyboard. On review, each typed word is
/// colored against the closest accepted answer.
public struct TypeInExercise: View {
    private let exercise: ExerciseArtifact
    private let courseCode: String
    private let instanceKey: String
    private let reviewed: Reviewed?
    private let text: Binding<String>
    private let onDone: () -> Void
    private let inAppKeyboard: Bool
    private let pending: String?
    private let caret: Int?
    private let onUseInAppKeyboard: (() -> Void)?
    private let onCaretTap: ((Int) -> Void)?
    private let onHintUsed: () -> Void
    private let hint: String?
    private let vowelMarks: Bool
    private let persianFamily: String?
    private let palette: AppPalette?

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focused: Bool
    @State private var hintShown = false
    @State private var fieldWidth: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @ScaledMetric(relativeTo: .title3) private var entrySize: CGFloat = 22
    @ScaledMetric(relativeTo: .title3) private var reviewSize: CGFloat = 20

    // Persian in a custom family scales with Dynamic Type by itself; the system face needs the scaled metric.
    private func courseFont(size: CGFloat, scaled: CGFloat, rtl: Bool) -> Font {
        if rtl, let family = persianFamily, !family.isEmpty {
            return DirectionalText.font(size: size, rtl: rtl, family: persianFamily)
        }
        return DirectionalText.font(size: scaled, rtl: rtl, family: persianFamily)
    }

    public init(
        exercise: ExerciseArtifact,
        courseCode: String,
        instanceKey: String,
        reviewed: Reviewed? = nil,
        text: Binding<String>,
        onDone: @escaping () -> Void = {},
        inAppKeyboard: Bool = false,
        pending: String? = nil,
        caret: Int? = nil,
        onUseInAppKeyboard: (() -> Void)? = nil,
        onCaretTap: ((Int) -> Void)? = nil,
        onHintUsed: @escaping () -> Void = {},
        hint: String? = nil,
        vowelMarks: Bool = true,
        persianFamily: String? = nil,
        palette: AppPalette? = nil
    ) {
        self.exercise = exercise
        self.courseCode = courseCode
        self.instanceKey = instanceKey
        self.reviewed = reviewed
        self.text = text
        self.onDone = onDone
        self.inAppKeyboard = inAppKeyboard
        self.pending = pending
        self.caret = caret
        self.onUseInAppKeyboard = onUseInAppKeyboard
        self.onCaretTap = onCaretTap
        self.onHintUsed = onHintUsed
        self.hint = hint
        self.vowelMarks = vowelMarks
        self.persianFamily = persianFamily
        self.palette = palette
    }

    private var p: AppPalette { palette ?? (colorScheme == .dark ? AppPalette.dark : AppPalette.light) }

    public var body: some View {
        if let reviewed = reviewed {
            reviewBody(reviewed)
        } else {
            VStack(alignment: .leading, spacing: Spacing.standard.s2) {
                entryBody
                if let note = TypeInModel.arabicVariantNote(courseCode: courseCode, scriptMode: exercise.scriptMode, text: text.wrappedValue) {
                    Text(note).font(.footnote).foregroundColor(Color(argb: p.warning))
                }
                hintBody
            }
        }
    }

    // MARK: Review

    @ViewBuilder
    private func reviewBody(_ reviewed: Reviewed) -> some View {
        let words = TypeInModel.reviewWords(courseCode: courseCode, exercise: exercise, reviewed: reviewed, vowelMarks: vowelMarks)
        let rtl = TypeInModel.isRtl(courseCode: courseCode, text: reviewed.text)
        VStack(alignment: .leading, spacing: Spacing.standard.s1) {
            if let missing = TypeInModel.missingWordsText(words) {
                // The label is app chrome and stays left to right; only the words take the course direction.
                HStack(spacing: 4) {
                    Text(TypeInModel.missingLabel).fontWeight(.bold)
                    Text(missing)
                        .fontWeight(.bold)
                        .environment(\.layoutDirection, DirectionalText.layoutDirection(rtl: TypeInModel.isRtl(courseCode: courseCode, text: missing)))
                }
                .foregroundColor(Color(argb: p.info))
                .environment(\.layoutDirection, .leftToRight)
            }
            Group {
                if words.isEmpty {
                    Text(TypeInModel.nothingSubmitted).foregroundColor(Color(argb: p.textMuted))
                } else {
                    WordFlowLayout(rtl: rtl, centered: false, lineSpacing: 6) {
                        ForEach(0..<words.count, id: \.self) { i in
                            markedWord(words[i], rtl: rtl)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.standard.s2)
            .overlay(RoundedRectangle(cornerRadius: Radii.standard.md).stroke(Color(argb: p.border), lineWidth: 2))
            .directionalText(rtl: rtl)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TypeInModel.answerDescription(reviewed.text, reviewing: true))
            .accessibilityValue(TypeInModel.reviewAccessibilityValue(words))
        }
    }

    private func markedWord(_ word: MarkedWord, rtl: Bool) -> some View {
        let color: UInt32
        let background: UInt32?
        switch word.mark {
        case .right: color = p.success; background = nil
        case .swapped: color = p.warning; background = p.warningBg
        case .wrong: color = p.danger; background = p.dangerBg
        case .missing: color = p.info; background = p.infoBg
        }
        return Text(word.text)
            .font(courseFont(size: 20, scaled: reviewSize, rtl: rtl).weight(.semibold))
            .strikethrough(word.mark == .wrong)
            .foregroundColor(Color(argb: color))
            .padding(.horizontal, 3)
            .background(
                RoundedRectangle(cornerRadius: 4).fill(background.map { Color(argb: $0) } ?? Color.clear)
            )
    }

    // MARK: Entry

    @ViewBuilder
    private var entryBody: some View {
        let rtl = TypeInModel.fieldIsRtl(courseCode: courseCode, scriptMode: exercise.scriptMode)
        if inAppKeyboard {
            inAppField(rtl: rtl)
        } else {
            VStack(alignment: .leading, spacing: Spacing.standard.s2) {
                TextField(
                    TypeInModel.placeholder(scriptMode: exercise.scriptMode, inAppKeyboard: false),
                    text: text
                )
                .font(courseFont(size: 22, scaled: entrySize, rtl: rtl))
                .focused($focused)
                .submitLabel(.done)
                .autocorrectionDisabled(true)
                .onSubmit {
                    if !text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { onDone() }
                }
                .padding(.horizontal, Spacing.standard.s3)
                .frame(minHeight: 48)
                .overlay(RoundedRectangle(cornerRadius: Radii.standard.md).stroke(Color(argb: focused ? p.current : p.border), lineWidth: 2))
                .directionalText(rtl: rtl)
                .task(id: instanceKey) { focused = true }
                if let onUse = onUseInAppKeyboard {
                    Button(action: onUse) {
                        Text(TypeInModel.inAppKeyboardLabel).font(.footnote).foregroundColor(Color(argb: p.current))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func inAppField(rtl: Bool) -> some View {
        let value = text.wrappedValue
        let shown = TypeInModel.shownText(text: value, caret: caret ?? value.unicodeScalars.count, pending: pending)
        let font = courseFont(size: 22, scaled: entrySize, rtl: rtl)
        let empty = value.isEmpty && pending == nil
        ZStack(alignment: .leading) {
            if empty {
                Text(TypeInModel.placeholder(scriptMode: exercise.scriptMode, inAppKeyboard: true))
                    .font(font)
                    .foregroundColor(Color(argb: p.textMuted))
                    .padding(.leading, 6)
            }
            // A caret at the end keeps the text in one Text (Persian letters still join); mid-text it splits there.
            HStack(spacing: 0) {
                Text(leading(shown)).font(font)
                VirtualCaret(palette: p, height: 28)
                if !shown.after.isEmpty { Text(shown.after).font(font).foregroundColor(Color(argb: p.text)) }
            }
            .fixedSize()
            .background(GeometryReader { g in Color.clear.preference(key: TypeInTextWidthKey.self, value: g.size.width) })
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(GeometryReader { g in Color.clear.preference(key: TypeInFieldWidthKey.self, value: g.size.width) })
        .onPreferenceChange(TypeInTextWidthKey.self) { textWidth = $0 }
        .onPreferenceChange(TypeInFieldWidthKey.self) { fieldWidth = $0 }
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { tap in
                guard let onCaretTap = onCaretTap, textWidth > 0 else { return }
                // The tap is in the field's own (physical) coordinates; the text starts at its leading edge.
                let fromLeading = rtl ? fieldWidth - tap.location.x : tap.location.x
                let fraction = Double((fromLeading - Spacing.standard.s3) / textWidth)
                onCaretTap(TypeInModel.caretForTap(text: value, fraction: fraction))
            }
        )
        .padding(.horizontal, Spacing.standard.s3)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Radii.standard.md).stroke(Color(argb: p.current), lineWidth: 2))
        .directionalText(rtl: rtl)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TypeInModel.answerDescription(value, reviewing: false))
    }

    private func leading(_ shown: TypeInShownText) -> AttributedString {
        var out = AttributedString(shown.before)
        out.foregroundColor = Color(argb: p.text)
        if !shown.pending.isEmpty {
            var pend = AttributedString(shown.pending)
            pend.foregroundColor = Color(argb: p.textMuted)
            out.append(pend)
        }
        return out
    }

    @ViewBuilder
    private var hintBody: some View {
        if let hint = hint {
            if hintShown {
                Text(hint).font(.subheadline).foregroundColor(Color(argb: p.textMuted))
            } else {
                Button(action: {
                    hintShown = true
                    onHintUsed()
                }) {
                    Text(TypeInModel.hintLink).font(.subheadline).foregroundColor(Color(argb: p.current))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct TypeInTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct TypeInFieldWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// A speak exercise (web SpeakExercise): speech capture is not wired up on web or Android, so
/// it is a type-in with a note saying so (Android renders SPEAK through TypeInExercise too).
public struct SpeakExercise: View {
    private let exercise: ExerciseArtifact
    private let courseCode: String
    private let instanceKey: String
    private let reviewed: Reviewed?
    private let text: Binding<String>
    private let onDone: () -> Void
    private let inAppKeyboard: Bool
    private let pending: String?
    private let caret: Int?
    private let onUseInAppKeyboard: (() -> Void)?
    private let onCaretTap: ((Int) -> Void)?
    private let onHintUsed: () -> Void
    private let hint: String?
    private let vowelMarks: Bool
    private let persianFamily: String?
    private let palette: AppPalette?

    @Environment(\.colorScheme) private var colorScheme

    public init(
        exercise: ExerciseArtifact,
        courseCode: String,
        instanceKey: String,
        reviewed: Reviewed? = nil,
        text: Binding<String>,
        onDone: @escaping () -> Void = {},
        inAppKeyboard: Bool = false,
        pending: String? = nil,
        caret: Int? = nil,
        onUseInAppKeyboard: (() -> Void)? = nil,
        onCaretTap: ((Int) -> Void)? = nil,
        onHintUsed: @escaping () -> Void = {},
        hint: String? = nil,
        vowelMarks: Bool = true,
        persianFamily: String? = nil,
        palette: AppPalette? = nil
    ) {
        self.exercise = exercise
        self.courseCode = courseCode
        self.instanceKey = instanceKey
        self.reviewed = reviewed
        self.text = text
        self.onDone = onDone
        self.inAppKeyboard = inAppKeyboard
        self.pending = pending
        self.caret = caret
        self.onUseInAppKeyboard = onUseInAppKeyboard
        self.onCaretTap = onCaretTap
        self.onHintUsed = onHintUsed
        self.hint = hint
        self.vowelMarks = vowelMarks
        self.persianFamily = persianFamily
        self.palette = palette
    }

    public var body: some View {
        let p = palette ?? (colorScheme == .dark ? AppPalette.dark : AppPalette.light)
        VStack(alignment: .leading, spacing: Spacing.standard.s2) {
            TypeInExercise(
                exercise: exercise,
                courseCode: courseCode,
                instanceKey: instanceKey,
                reviewed: reviewed,
                text: text,
                onDone: onDone,
                inAppKeyboard: inAppKeyboard,
                pending: pending,
                caret: caret,
                onUseInAppKeyboard: onUseInAppKeyboard,
                onCaretTap: onCaretTap,
                onHintUsed: onHintUsed,
                hint: hint,
                vowelMarks: vowelMarks,
                persianFamily: persianFamily,
                palette: palette
            )
            if reviewed == nil {
                Text(TypeInModel.speakNote).font(.footnote).foregroundColor(Color(argb: p.textMuted))
            }
        }
    }
}
