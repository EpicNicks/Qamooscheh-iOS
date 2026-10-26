import SwiftUI
import QDomain
import QDesign

/// One Stow dialog card: the confirmation, the encouraging popup after a stow, or the "You got this!"
/// popup after declining. Plain values and closures; `StowFlowModel` drives it through `stowDialogs`.
public struct StowDialogCardView: View {
    private let state: StowFlowState
    private let palette: AppPalette?
    private let onConfirm: () -> Void
    private let onDecline: () -> Void
    private let onContinue: () -> Void
    private let onClose: () -> Void
    private let onRetry: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    public init(
        state: StowFlowState,
        palette: AppPalette? = nil,
        onConfirm: @escaping () -> Void = {},
        onDecline: @escaping () -> Void = {},
        onContinue: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {},
        onRetry: @escaping () -> Void = {}
    ) {
        self.state = state
        self.palette = palette
        self.onConfirm = onConfirm
        self.onDecline = onDecline
        self.onContinue = onContinue
        self.onClose = onClose
        self.onRetry = onRetry
    }

    public var body: some View {
        let p = palette ?? (colorScheme == .dark ? AppPalette.dark : AppPalette.light)
        VStack(spacing: Spacing.standard.s3) {
            Text(titleText)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Color(argb: p.text))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            Text(bodyText)
                .font(.system(size: 16))
                .foregroundColor(Color(argb: p.text))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if let error = state.error {
                Text(error)
                    .font(.system(size: 14))
                    .foregroundColor(Color(argb: p.textMuted))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            if state.busy {
                ProgressView().accessibilityLabel("Stowing")
            }
            buttons(p)
        }
        .padding(Spacing.standard.s3)
        .frame(maxWidth: 320)
        .background(Color(argb: p.bg))
    }

    private var titleText: String {
        switch state.step {
        case .confirm: return StowCopy.confirmTitle
        case .encouraged: return StowCopy.encouragedTitle
        case .declined: return StowCopy.declinedTitle
        }
    }

    private var bodyText: String {
        switch state.step {
        case .confirm: return StowCopy.confirmBody
        case .encouraged: return StowCopy.encouragedBody
        case .declined: return StowCopy.declinedBody
        }
    }

    @ViewBuilder
    private func buttons(_ p: AppPalette) -> some View {
        switch state.step {
        case .confirm:
            PathPopupButton(text: StowCopy.confirmAction, kind: .primary, palette: p, action: onConfirm)
                .disabled(state.busy)
            PathPopupButton(text: StowCopy.confirmCancel, kind: .secondary, palette: p, action: onDecline)
                .disabled(state.busy)
        case .encouraged:
            PathPopupButton(text: StowCopy.encouragedContinue, kind: .primary, palette: p, action: onContinue)
        case .declined:
            PathPopupButton(text: StowCopy.declinedRetry, kind: .primary, palette: p, action: onRetry)
            PathPopupButton(text: StowCopy.declinedClose, kind: .secondary, palette: p, action: onClose)
        }
    }
}

public extension View {
    /// Presents the Stow dialogs while the model has a flow open. `onRetry` receives the tapped lesson's key.
    func stowDialogs(model: StowFlowModel, onRetry: @escaping (String) -> Void) -> some View {
        sheet(isPresented: Binding(
            get: { model.flow != nil },
            set: { shown in if !shown { model.dismiss() } }
        )) {
            StowDialogsHost(model: model, onRetry: onRetry)
                .presentationDetents([.medium])
        }
    }
}

struct StowDialogsHost: View {
    @ObservedObject var model: StowFlowModel
    let onRetry: (String) -> Void

    var body: some View {
        if let state = model.flow {
            StowDialogCardView(
                state: state,
                onConfirm: { Task { await model.confirm() } },
                onDecline: { model.decline() },
                onContinue: { model.dismiss() },
                onClose: { model.dismiss() },
                onRetry: { if let key = model.retryLesson() { onRetry(key) } }
            )
        }
    }
}

/// The "ready to retry?" reminder: the Stowage grouped by unit as the server returned it, with Not yet
/// and an X that stops reminders for these lessons.
public struct StowReminderView: View {
    private let groups: [StowageGroup]
    private let busy: Bool
    private let error: String?
    private let palette: AppPalette?
    private let onNotYet: () -> Void
    private let onMute: () -> Void
    private let onRetry: ((PathSkill) -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    public init(
        groups: [StowageGroup],
        busy: Bool = false,
        error: String? = nil,
        palette: AppPalette? = nil,
        onNotYet: @escaping () -> Void = {},
        onMute: @escaping () -> Void = {},
        onRetry: ((PathSkill) -> Void)? = nil
    ) {
        self.groups = groups
        self.busy = busy
        self.error = error
        self.palette = palette
        self.onNotYet = onNotYet
        self.onMute = onMute
        self.onRetry = onRetry
    }

    public var body: some View {
        let p = palette ?? (colorScheme == .dark ? AppPalette.dark : AppPalette.light)
        VStack(spacing: Spacing.standard.s3) {
            HStack(alignment: .top) {
                Text(StowCopy.reminderTitle)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color(argb: p.text))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                Button(action: onMute) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(argb: p.textMuted))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityLabel("Stop reminders for these lessons")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.standard.s3) {
                    ForEach(groups, id: \.unitKey) { group in
                        VStack(alignment: .leading, spacing: Spacing.standard.s1) {
                            Text(group.unitTitle)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(argb: p.textMuted))
                                .accessibilityAddTraits(.isHeader)
                            ForEach(group.lessons, id: \.skillKey) { lesson in
                                lessonRow(lesson, palette: p)
                            }
                        }
                    }
                }
            }
            if let error = error {
                Text(error)
                    .font(.system(size: 14))
                    .foregroundColor(Color(argb: p.textMuted))
            }
            PathPopupButton(text: StowCopy.reminderNotYet, kind: .primary, palette: p, action: onNotYet)
                .disabled(busy)
        }
        .padding(Spacing.standard.s3)
        .background(Color(argb: p.bg))
    }
}

extension StowReminderView {
    /// A lesson of the list: tapping it retries that lesson when the screen supplies `onRetry`.
    @ViewBuilder
    fileprivate func lessonRow(_ lesson: PathSkill, palette p: AppPalette) -> some View {
        let label = Text(lesson.title)
            .font(.system(size: 16))
            .foregroundColor(Color(argb: p.text))
            .padding(.horizontal, Spacing.standard.s2)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radii.standard.md).fill(Color(argb: p.surface)))
        if let onRetry = onRetry {
            Button(action: { onRetry(lesson) }) { label }
                .buttonStyle(.plain)
                .disabled(busy)
        } else {
            label
        }
    }
}

public extension View {
    /// Presents the reminder when the model says it is due. Back or an outside tap puts it away for now.
    func stowReminder(model: StowReminderModel, path: [PathUnit]) -> some View {
        sheet(isPresented: Binding(
            get: { model.isShown },
            set: { shown in if !shown { model.putAway() } }
        )) {
            StowReminderHost(model: model, path: path)
        }
    }
}

struct StowReminderHost: View {
    @ObservedObject var model: StowReminderModel
    let path: [PathUnit]
    var onRetry: ((PathSkill) -> Void)?

    var body: some View {
        StowReminderView(
            groups: model.groups(path: path),
            busy: model.busy,
            error: model.error,
            onNotYet: { Task { await model.notYet() } },
            onMute: { Task { await model.mute() } },
            onRetry: onRetry
        )
    }
}
