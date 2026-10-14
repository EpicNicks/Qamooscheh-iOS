import SwiftUI
import QDesign
import QData
import QDomain
import QKeyboard

/// Which input method a segmented toggle option stands for.
enum InputMethodChoice: Equatable {
    case persian(PersianInputMethod)
    case japanese(JapaneseInputMethod)
}

/// A two-option pill toggle for the keyboard's header band.
struct InputMethodToggle: View {
    let options: [(choice: InputMethodChoice, title: String)]
    let selected: InputMethodChoice
    let palette: AppPalette
    let onChange: (InputMethodChoice) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<options.count, id: \.self) { i in
                let on = options[i].choice == selected
                Button(action: { onChange(options[i].choice) }) {
                    Text(options[i].title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(on ? Color.white : Color(argb: palette.text))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(on ? Color(argb: palette.current) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: Radii.standard.sm - 2))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: Radii.standard.sm).fill(Color(argb: palette.bg)))
        .overlay(RoundedRectangle(cornerRadius: Radii.standard.sm).stroke(Color(argb: palette.border), lineWidth: 1))
    }
}

/// The keyboard docked under a type-in exercise (Android `TypeInKeyboardPanel`): which input
/// method, a way out to the phone's own keyboard, and the keys. The toggle and the exit sit in
/// the keyboard's own candidate band, so there is no row of their own.
public struct TypeInKeyboardPanel: View {
    private let courseCode: String
    private let prefs: LocalPrefs
    @ObservedObject private var state: KeyboardState
    private let palette: AppPalette?
    private let text: () -> String
    private let onEdit: (Edit) -> Void
    private let onPrefsChange: (LocalPrefs) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(
        courseCode: String,
        prefs: LocalPrefs,
        state: KeyboardState,
        palette: AppPalette? = nil,
        text: @escaping () -> String,
        onEdit: @escaping (Edit) -> Void,
        onPrefsChange: @escaping (LocalPrefs) -> Void
    ) {
        self.courseCode = courseCode
        self.prefs = prefs
        self.state = state
        self.palette = palette
        self.text = text
        self.onEdit = onEdit
        self.onPrefsChange = onPrefsChange
    }

    public var body: some View {
        let p = palette ?? (colorScheme == .dark ? AppPalette.dark : AppPalette.light)
        ScriptKeyboardView(
            state: state,
            palette: p,
            hapticsEnabled: prefs.hapticsEnabled,
            textBefore: text,
            onEdit: onEdit
        ) {
            header(p)
        }
    }

    // Past about 1.3x the two controls no longer fit side by side, so they stack and the band grows to hold them.
    private var stacked: Bool { typeSize >= .xxxLarge }

    @ViewBuilder
    private func header(_ p: AppPalette) -> some View {
        if stacked {
            VStack(spacing: 4) {
                toggle(p)
                phoneButton(p)
            }
            .padding(.horizontal, 4)
        } else {
            HStack(spacing: 8) {
                toggle(p).frame(maxWidth: .infinity)
                phoneButton(p).frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private func toggle(_ p: AppPalette) -> some View {
        switch Languages.languageInfo(courseCode)?.language {
        case "fa":
            InputMethodToggle(
                options: [(.persian(.phonetic), "Phonetic"), (.persian(.layout), "Persian")],
                selected: .persian(prefs.persianInputMethod),
                palette: p
            ) { choice in
                if case let .persian(method) = choice {
                    var next = prefs
                    next.persianInputMethod = method
                    onPrefsChange(next)
                }
            }
        case "ja":
            InputMethodToggle(
                options: [(.japanese(.romaji), "Romaji"), (.japanese(.kana), "Kana")],
                selected: .japanese(prefs.japaneseInputMethod),
                palette: p
            ) { choice in
                if case let .japanese(method) = choice {
                    var next = prefs
                    next.japaneseInputMethod = method
                    onPrefsChange(next)
                }
            }
        default:
            EmptyView()
        }
    }

    private func phoneButton(_ p: AppPalette) -> some View {
        Button(action: {
            var next = prefs
            next.deviceInputEnabled = true
            onPrefsChange(next)
        }) {
            Text(TypeInModel.phoneKeyboardLabel)
                .font(.system(size: 15))
                .foregroundColor(Color(argb: p.textMuted))
                .lineLimit(1)
                .frame(minHeight: 32)
        }
        .buttonStyle(.plain)
    }
}
