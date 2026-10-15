import SwiftUI
import QDesign

// The checkpoint's last screens (Android LessonScreen CheckpointResults, web CheckpointPage): "Ready to submit" /
// "No test needed" with the submit and exit buttons, then the verdict. Text comes from `CheckpointLogic`.

private func checkpointPalette(_ scheme: ColorScheme) -> AppPalette {
    return scheme == .dark ? AppPalette.dark : AppPalette.light
}

private func checkpointButton(_ title: String, primary: Bool, enabled: Bool = true, p: AppPalette, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(Color(argb: primary ? p.primaryContrast : p.text))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: Radii.standard.md, style: .continuous).fill(Color(argb: primary ? p.primary : p.surface)))
            .overlay(RoundedRectangle(cornerRadius: Radii.standard.md, style: .continuous).stroke(Color(argb: primary ? p.primary : p.border)))
            .opacity(enabled ? 1 : 0.5)
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
}

/// After the last answer: submit everything at once, or leave without submitting.
public struct CheckpointReadyView: View {
    private let noTest: Bool
    private let summary: String?
    private let error: String?
    private let submitting: Bool
    private let onSubmit: () -> Void
    private let onExit: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    public init(noTest: Bool, summary: String?, error: String?, submitting: Bool, onSubmit: @escaping () -> Void, onExit: @escaping () -> Void) {
        self.noTest = noTest
        self.summary = summary
        self.error = error
        self.submitting = submitting
        self.onSubmit = onSubmit
        self.onExit = onExit
    }

    public var body: some View {
        let p = checkpointPalette(colorScheme)
        let copy = CheckpointLogic.readyCopy(noTest: noTest)
        ScrollView {
            VStack(spacing: Spacing.standard.s3) {
                Text(copy.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color(argb: p.text))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(copy.body)
                    .font(.system(size: 17))
                    .foregroundColor(Color(argb: p.textMuted))
                    .multilineTextAlignment(.center)
                if let summary = summary {
                    Text(summary)
                        .font(.system(size: 13))
                        .foregroundColor(Color(argb: p.textMuted))
                        .multilineTextAlignment(.center)
                }
                if let error = error {
                    Text(error)
                        .font(.system(size: 15))
                        .foregroundColor(Color(argb: p.danger))
                        .multilineTextAlignment(.center)
                        .padding(Spacing.standard.s2)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: Radii.standard.md, style: .continuous).fill(Color(argb: p.dangerBg)))
                        .accessibilityLabel(error)
                }
                VStack(spacing: Spacing.standard.s2) {
                    checkpointButton(CheckpointLogic.primaryLabel(noTest: noTest, submitting: submitting), primary: true, enabled: !submitting, p: p, action: onSubmit)
                    checkpointButton(CheckpointLogic.secondaryLabel(noTest: noTest), primary: false, p: p, action: onExit)
                }
                .frame(maxWidth: 420)
            }
            .padding(Spacing.standard.s4)
            .frame(maxWidth: .infinity)
        }
        .background(Color(argb: p.bg))
    }
}

/// The server's verdict on the checkpoint.
public struct CheckpointResultView: View {
    private let outcome: CheckpointOutcome
    private let onBack: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    public init(outcome: CheckpointOutcome, onBack: @escaping () -> Void) {
        self.outcome = outcome
        self.onBack = onBack
    }

    public var body: some View {
        let p = checkpointPalette(colorScheme)
        let copy = CheckpointLogic.resultCopy(outcome)
        ScrollView {
            VStack(spacing: Spacing.standard.s3) {
                Text(copy.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color(argb: p.text))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(copy.body)
                    .font(.system(size: 17))
                    .foregroundColor(Color(argb: p.textMuted))
                    .multilineTextAlignment(.center)
                checkpointButton(CheckpointLogic.backToPath, primary: true, p: p, action: onBack)
                    .frame(maxWidth: 420)
            }
            .padding(Spacing.standard.s4)
            .frame(maxWidth: .infinity)
        }
        .background(Color(argb: p.bg))
    }
}
