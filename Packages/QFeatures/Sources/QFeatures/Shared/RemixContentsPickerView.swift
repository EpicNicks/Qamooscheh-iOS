import SwiftUI
import QDesign
import QDomain

/// The step before a Repack starts (web RemixContentsPicker, Android RemixContentsPicker): which kinds of exercise, and
/// flashcards, it holds. `hardcore` is the fill-in-the-blank switch: nil hides it, a value shows it (it is the one kind with
/// typo tolerance to turn off). `noneOfThat` shows `noneMessage` when the last Start found nothing of the picked kind.
public struct RemixContentsPickerView: View {
    private let options: [RemixContents]
    private let selected: RemixContents
    private let noneOfThat: Bool
    private let noneMessage: String
    private let backLabel: String
    private let hardcore: Bool?
    private let onSelect: (RemixContents) -> Void
    private let onHardcoreChange: (Bool) -> Void
    private let onStart: () -> Void
    private let onBack: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    public init(
        options: [RemixContents], selected: RemixContents, noneOfThat: Bool,
        noneMessage: String = "This Repack has none of those right now. Pick something else.",
        backLabel: String = "Back", hardcore: Bool? = nil,
        onSelect: @escaping (RemixContents) -> Void, onHardcoreChange: @escaping (Bool) -> Void = { _ in },
        onStart: @escaping () -> Void, onBack: @escaping () -> Void
    ) {
        self.options = options
        self.selected = selected
        self.noneOfThat = noneOfThat
        self.noneMessage = noneMessage
        self.backLabel = backLabel
        self.hardcore = hardcore
        self.onSelect = onSelect
        self.onHardcoreChange = onHardcoreChange
        self.onStart = onStart
        self.onBack = onBack
    }

    public var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        ZStack {
            Color(argb: p.bg).ignoresSafeArea()
            ScrollView {
                VStack(spacing: Spacing.standard.s3) {
                    Text("What should this Repack hold?")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(Color(argb: p.text))
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: Spacing.standard.s2) {
                        ForEach(options, id: \.self) { option in
                            optionRow(option, p)
                        }
                    }
                    .frame(maxWidth: 420)
                    if let hardcore = hardcore {
                        hardcoreRow(hardcore, p)
                    }
                    if noneOfThat {
                        Text(noneMessage)
                            .foregroundColor(Color(argb: p.danger))
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                    VStack(spacing: Spacing.standard.s2) {
                        Button(action: onStart) {
                            Text("Start")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Color(argb: p.primaryContrast))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(RoundedRectangle(cornerRadius: Radii.standard.md, style: .continuous).fill(Color(argb: p.primary)))
                        }
                        .buttonStyle(.plain)
                        Button(action: onBack) {
                            Text(backLabel)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Color(argb: p.text))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .overlay(RoundedRectangle(cornerRadius: Radii.standard.md, style: .continuous).stroke(Color(argb: p.border), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: 420)
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.standard.s4)
            }
        }
    }

    private func optionRow(_ option: RemixContents, _ p: AppPalette) -> some View {
        let isSelected = option == selected
        return Button(action: { onSelect(option) }) {
            Text(option.label)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color(argb: p.text))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.standard.s3)
                .overlay(
                    RoundedRectangle(cornerRadius: Radii.standard.md, style: .continuous)
                        .stroke(Color(argb: isSelected ? p.current : p.border), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func hardcoreRow(_ on: Bool, _ p: AppPalette) -> some View {
        return Button(action: { onHardcoreChange(!on) }) {
            HStack(spacing: Spacing.standard.s3) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundColor(Color(argb: on ? p.primary : p.border))
                Text("Hardcore: no typos forgiven (otherwise one wrong letter in a word of four or more is let through)")
                    .font(.system(size: 15))
                    .foregroundColor(Color(argb: p.textMuted))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 420)
        .accessibilityValue(on ? "On" : "Off")
    }
}
