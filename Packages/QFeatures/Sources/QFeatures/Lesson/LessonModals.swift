import SwiftUI
import QDesign
import QDomain
import QData
import QModel

// The lesson's close button, its two leave warnings and the language settings popover
// (web CloseLessonButton, SkipLessonModal, LeaveCheckpointModal, LanguageSettingsPopover; the
// behaviour follows Android LessonScreen.kt / LessonSettings.kt).

private func modalPalette(_ scheme: ColorScheme) -> AppPalette {
    return scheme == .dark ? AppPalette.dark : AppPalette.light
}

/// The red x at the top right of a lesson. While the leave warning is up it turns into a sad face,
/// the moment meant to give the learner pause (web CloseLessonButton).
public struct CloseLessonButton: View {
    private let isConfirming: Bool
    private let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    public init(isConfirming: Bool, action: @escaping () -> Void) {
        self.isConfirming = isConfirming
        self.action = action
    }

    public var body: some View {
        let p = modalPalette(colorScheme)
        Button(action: action) {
            Group {
                if isConfirming {
                    Text(":(").font(.system(size: 20, weight: .bold))
                } else {
                    Image(systemName: "xmark").font(.system(size: 18, weight: .bold))
                }
            }
            .foregroundColor(Color(argb: p.danger))
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close lesson")
    }
}

/// A confirmation card over a dimmed screen: a title, a sentence, a danger button and a way back.
struct LessonConfirmDialog: View {
    let title: String
    let message: String
    let confirmLabel: String
    let cancelLabel: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = modalPalette(colorScheme)
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.standard.s3) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color(argb: p.text))
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.system(size: 16))
                    .foregroundColor(Color(argb: p.text))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: Spacing.standard.s2) {
                    button(cancelLabel, fill: p.surface, text: p.text, border: p.border, action: onCancel)
                    button(confirmLabel, fill: p.danger, text: 0xFFFFFFFF, border: p.danger, action: onConfirm)
                }
            }
            .padding(Spacing.standard.s4)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: Radii.standard.lg, style: .continuous).fill(Color(argb: p.bg))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radii.standard.lg, style: .continuous).stroke(Color(argb: p.border))
            )
            .padding(Spacing.standard.s4)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }

    private func button(_ label: String, fill: UInt32, text: UInt32, border: UInt32, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(argb: text))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: Radii.standard.md, style: .continuous).fill(Color(argb: fill)))
                .overlay(RoundedRectangle(cornerRadius: Radii.standard.md, style: .continuous).stroke(Color(argb: border)))
        }
        .buttonStyle(.plain)
    }
}

/// "Leave this lesson?" (web SkipLessonModal; Android's AlertDialog, which has no "don't ask again").
public struct SkipLessonModal: View {
    private let onKeepGoing: () -> Void
    private let onLeave: () -> Void

    public init(onKeepGoing: @escaping () -> Void, onLeave: @escaping () -> Void) {
        self.onKeepGoing = onKeepGoing
        self.onLeave = onLeave
    }

    public var body: some View {
        LessonConfirmDialog(
            title: LessonScreenLogic.leaveLessonTitle,
            message: LessonScreenLogic.leaveLessonBody,
            confirmLabel: LessonScreenLogic.leaveConfirm,
            cancelLabel: LessonScreenLogic.keepGoing,
            onConfirm: onLeave,
            onCancel: onKeepGoing
        )
    }
}

/// "Leave this checkpoint?" (web LeaveCheckpointModal).
public struct LeaveCheckpointModal: View {
    private let onKeepGoing: () -> Void
    private let onLeave: () -> Void

    public init(onKeepGoing: @escaping () -> Void, onLeave: @escaping () -> Void) {
        self.onKeepGoing = onKeepGoing
        self.onLeave = onLeave
    }

    public var body: some View {
        LessonConfirmDialog(
            title: LessonScreenLogic.leaveCheckpointTitle,
            message: LessonScreenLogic.leaveCheckpointBody,
            confirmLabel: LessonScreenLogic.leaveConfirm,
            cancelLabel: LessonScreenLogic.keepGoing,
            onConfirm: onLeave,
            onCancel: onKeepGoing
        )
    }
}

/// A labelled switch row, at least 48 pt tall (Android Toggle).
struct LessonToggleRow: View {
    let label: String
    let isOn: Bool
    let palette: AppPalette
    let onChange: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { onChange($0) })) {
            Text(label)
                .font(.system(size: 16))
                .foregroundColor(Color(argb: palette.text))
        }
        .tint(Color(argb: palette.primary))
        .frame(minHeight: 48)
    }
}

/// A two or three way segmented choice (Android SegmentedToggle).
struct LessonSegmented<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    let selected: Value
    let palette: AppPalette
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = option.value == selected
                Button(action: { onSelect(option.value) }) {
                    Text(option.label)
                        .font(.system(size: 15, weight: on ? .bold : .regular))
                        .foregroundColor(Color(argb: on ? palette.primaryContrast : palette.text))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(on ? Color(argb: palette.primary) : Color.clear)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? AccessibilityTraits([.isSelected, .isButton]) : AccessibilityTraits.isButton)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radii.standard.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radii.standard.md, style: .continuous).stroke(Color(argb: palette.border)))
    }
}

/// The lesson's settings cog (web LanguageSettingsPopover, Android LessonSettingsSheet): the course language's
/// text mode, alignment, furigana, hints, reading aids and keyboard, changed without leaving the lesson.
/// Pure values and closures; the lesson session applies and saves the changes.
public struct LanguageSettingsPopover: View {
    private let courseCode: String
    private let prefs: LocalPrefs
    private let serverPrefs: LessonServerPrefs?
    private let onPrefsChange: (LocalPrefs) -> Void
    private let onScriptModeChange: (ScriptMode) -> Void
    private let onKeyboardModeChange: (KeyboardMode) -> Void
    private let onDismiss: () -> Void
    private let fontAvailable: (String) -> Bool
    @Environment(\.colorScheme) private var colorScheme

    public init(
        courseCode: String,
        prefs: LocalPrefs,
        serverPrefs: LessonServerPrefs?,
        onPrefsChange: @escaping (LocalPrefs) -> Void,
        onScriptModeChange: @escaping (ScriptMode) -> Void,
        onKeyboardModeChange: @escaping (KeyboardMode) -> Void,
        onDismiss: @escaping () -> Void,
        fontAvailable: @escaping (String) -> Bool = ScriptFonts.systemHasFamily
    ) {
        self.fontAvailable = fontAvailable
        self.courseCode = courseCode
        self.prefs = prefs
        self.serverPrefs = serverPrefs
        self.onPrefsChange = onPrefsChange
        self.onScriptModeChange = onScriptModeChange
        self.onKeyboardModeChange = onKeyboardModeChange
        self.onDismiss = onDismiss
    }

    public var body: some View {
        let p = modalPalette(colorScheme)
        let languageName = Languages.languageInfo(courseCode)?.displayName ?? "course language"
        let rows = LessonSettingsRows.rows(courseCode: courseCode, prefs: prefs, hasServerPrefs: serverPrefs != nil)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.standard.s2) {
                HStack {
                    Text(LessonScreenLogic.settingsTitle)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Color(argb: p.text))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Done", action: onDismiss)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(argb: p.primary))
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    rowView(row, languageName: languageName, p: p)
                }
            }
            .padding(Spacing.standard.s4)
        }
        .background(Color(argb: p.bg))
    }

    @ViewBuilder
    private func rowView(_ row: LessonSettingsRow, languageName: String, p: AppPalette) -> some View {
        switch row {
        case .textMode:
            heading(LessonSettingsRows.label(row, languageName: languageName), p)
            LessonSegmented(options: LessonSettingsRows.textModes.map { (value: $0.mode, label: $0.label) }, selected: serverPrefs?.scriptMode ?? .native, palette: p, onSelect: onScriptModeChange)
            Text(LessonSettingsRows.textModeHelp)
                .font(.system(size: 13))
                .foregroundColor(Color(argb: p.textMuted))
        case .textAlignment:
            heading(LessonSettingsRows.label(row, languageName: languageName), p)
            LessonSegmented(options: LessonSettingsRows.alignments.map { (value: $0.align, label: $0.label) }, selected: prefs.nativeTextAlign, palette: p) { align in
                var next = prefs
                next.nativeTextAlign = align
                onPrefsChange(next)
            }
        case .keyboardMode:
            heading(LessonSettingsRows.label(row, languageName: languageName), p)
            LessonSegmented(options: LessonSettingsRows.keyboardModes.map { (value: $0.mode, label: $0.label) }, selected: serverPrefs?.keyboardMode ?? .contextual, palette: p, onSelect: onKeyboardModeChange)
        case .font:
            fontGroup(row, languageName: languageName, p: p)
        default:
            LessonToggleRow(label: LessonSettingsRows.label(row, languageName: languageName), isOn: LessonSettingsRows.isOn(row, prefs: prefs) ?? false, palette: p) { on in
                onPrefsChange(LessonSettingsRows.setting(row, to: on, in: prefs))
            }
        }
    }

    @ViewBuilder
    private func fontGroup(_ row: LessonSettingsRow, languageName: String, p: AppPalette) -> some View {
        if let group = LessonSettingsRows.fontGroup(courseCode: courseCode, prefs: prefs, isAvailable: fontAvailable) {
            heading(LessonSettingsRows.label(row, languageName: languageName), p)
            if !group.options.isEmpty {
                HStack(spacing: Spacing.standard.s2) {
                    ForEach(Array(group.options.enumerated()), id: \.offset) { _, option in
                        let selected = option.family == group.selectedFamily
                        Button(action: { onPrefsChange(LessonSettingsRows.settingFontFamily(option.family, courseCode: courseCode, in: prefs)) }) {
                            Text(option.label)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color(argb: selected ? p.primaryContrast : p.text))
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Capsule().fill(Color(argb: selected ? p.primary : p.bg)))
                                .overlay(Capsule().stroke(Color(argb: p.border)))
                        }
                        .buttonStyle(.plain)
                        .disabled(!option.available)
                        .opacity(option.available ? 1 : 0.4)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            Text("\(languageName) text size (\(group.sizePct)%)")
                .font(.system(size: 13))
                .foregroundColor(Color(argb: p.textMuted))
            Slider(value: Binding(get: { Double(group.sizePct) }, set: { v in
                onPrefsChange(LessonSettingsRows.settingFontSize(v, courseCode: courseCode, in: prefs))
            }), in: 75...150, step: 5)
        }
    }

    private func heading(_ text: String, _ p: AppPalette) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(Color(argb: p.textMuted))
            .padding(.top, Spacing.standard.s2)
    }
}
