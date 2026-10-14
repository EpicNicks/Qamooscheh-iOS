import SwiftUI
import QData
import QModel
import QDesign

/// "Course update available" prompt on the Path (Android `CourseUpdateBanner`).
/// Dismissal lasts until the path is next opened, as on Android and the web.
public struct UpdateBannerView: View {
    private let offer: ContentUpdateOffer
    private let state: ContentUpdateState
    private let dialog: RollForwardDialogState?
    private let palette: AppPalette?
    private let onUpdate: () -> Void
    private let onConfirm: () -> Void
    private let onCancel: () -> Void
    private let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    public init(
        offer: ContentUpdateOffer,
        state: ContentUpdateState = .idle,
        dialog: RollForwardDialogState? = nil,
        palette: AppPalette? = nil,
        onUpdate: @escaping () -> Void = {},
        onConfirm: @escaping () -> Void = {},
        onCancel: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {}
    ) {
        self.offer = offer
        self.state = state
        self.dialog = dialog
        self.palette = palette
        self.onUpdate = onUpdate
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.onDismiss = onDismiss
    }

    public var body: some View {
        let p = palette ?? (colorScheme == .dark ? AppPalette.dark : AppPalette.light)
        let shape = RoundedRectangle(cornerRadius: Radii.standard.md)
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: Spacing.standard.s2) {
                Text(offer.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(argb: p.text))
                    .fixedSize(horizontal: false, vertical: true)
                if let hint = offer.hint {
                    Text(hint)
                        .font(.system(size: 13))
                        .foregroundColor(Color(argb: p.textMuted))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if case .failed(let message) = state {
                    Text(message)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(argb: p.danger))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let fraction = state.fraction {
                    ProgressView(value: fraction)
                        .accentColor(Color(argb: p.primary))
                } else if state.isBusy {
                    ProgressView()
                }
                if offer.canUpdate {
                    Button(action: onUpdate) {
                        Text(state.isBusy ? "Updating\u{2026}" : "Update")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color(argb: p.primaryContrast))
                            .padding(.horizontal, Spacing.standard.s4)
                            .padding(.vertical, Spacing.standard.s2)
                            .background(
                                RoundedRectangle(cornerRadius: Radii.standard.md)
                                    .fill(Color(argb: p.primary))
                                    .opacity(state.isBusy ? 0.5 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(state.isBusy)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, Spacing.standard.s5)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(argb: p.textMuted))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss update notice")
        }
        .padding(Spacing.standard.s3)
        .background(shape.fill(Color(argb: p.surface)))
        .overlay(shape.stroke(Color(argb: p.primary), lineWidth: 2))
        .accessibilityElement(children: .contain)
        .alert(
            dialogTitle,
            isPresented: Binding(get: { dialog != nil }, set: { if !$0 { onCancel() } }),
            actions: {
                if case .ready = dialog {
                    Button("Update", action: onConfirm)
                }
                Button("Cancel", role: .cancel, action: onCancel)
            },
            message: { Text(dialogMessage) })
    }

    private var dialogTitle: String {
        if case .ready(let confirmation) = dialog { return confirmation.title }
        return "Update to version \(offer.version)?"
    }

    private var dialogMessage: String {
        switch dialog {
        case .none: return ""
        case .some(.loading): return "Checking what's new\u{2026}"
        case .some(.failed(let message)): return message
        case .some(.ready(let c)):
            var lines: [String] = []
            if let notes = c.notes { lines.append(notes) }
            if c.unchanged {
                lines.append(RollForwardConfirmation.preservedMessage)
            } else {
                lines.append("Current position: \(c.currentLabel)")
                lines.append("After updating: \(c.afterLabel)")
            }
            if let warning = c.clampedWarning { lines.append(warning) }
            return lines.joined(separator: "\n")
        }
    }
}

/// The confirm step in front of every roll-forward.
public enum RollForwardDialogState: Equatable, Sendable {
    case loading
    case ready(RollForwardConfirmation)
    case failed(String)
}

/// Drives the banner: the offer, the in-flight state and per-visit dismissal.
@MainActor
public final class UpdateBannerModel: ObservableObject {
    @Published public private(set) var offer: ContentUpdateOffer?
    @Published public private(set) var state: ContentUpdateState = .idle
    @Published public private(set) var dismissed = false
    @Published public private(set) var dialog: RollForwardDialogState?

    public init(offer: ContentUpdateOffer? = nil) {
        self.offer = offer
    }

    /// Call when a fresh bootstrap arrives.
    public func setOffer(_ offer: ContentUpdateOffer?) {
        self.offer = offer
    }

    public var isVisible: Bool { offer != nil && !dismissed }

    public func dismiss() {
        dismissed = true
    }

    /// Update tapped: fetches the roll-forward preview and opens the confirm dialog.
    /// Nothing is downloaded or applied until `confirm`. An ineligible offer does nothing.
    public func requestUpdate(
        courseCode: String,
        loadPreview: @Sendable (String, Int) async throws -> RollForwardPreviewResponse
    ) async {
        guard let offer = offer, offer.canUpdate, !state.isBusy, dialog == nil else { return }
        dialog = .loading
        do {
            let preview = try await loadPreview(courseCode, offer.version)
            guard dialog == .loading else { return }
            dialog = .ready(RollForwardConfirmation(preview))
        } catch {
            guard dialog == .loading else { return }
            dialog = .failed("Couldn't check this update.")
        }
    }

    public func cancelConfirmation() {
        dialog = nil
    }

    /// Confirm tapped. Synchronous up to the point the dialog closes, so the alert dismissing
    /// (which fires `cancelConfirmation`) cannot race the apply. A no-op unless the dialog is
    /// showing a loaded preview. Returns the apply task (nil when nothing was started).
    @discardableResult
    public func confirm(updater: ContentUpdater, courseCode: String, commit: @escaping @Sendable (Int) async throws -> Void) -> Task<Void, Never>? {
        confirm { offer, onProgress in
            try await updater.accept(courseCode: courseCode, offer: offer, onProgress: onProgress, commit: commit)
        }
    }

    /// Same as above with the download-and-commit step injected.
    @discardableResult
    public func confirm(
        perform: @escaping @Sendable (ContentUpdateOffer, @escaping @Sendable (DownloadProgress) -> Void) async throws -> Void
    ) -> Task<Void, Never>? {
        guard case .ready = dialog, let offer = offer, !state.isBusy else { return nil }
        dialog = nil
        state = .downloading(DownloadProgress(done: 0, discovered: 0))
        return Task { @MainActor [weak self] in
            await self?.run(offer: offer, perform: perform)
        }
    }

    /// Failure leaves the old version pinned and shows a message on the banner.
    private func run(
        offer: ContentUpdateOffer,
        perform: @Sendable (ContentUpdateOffer, @escaping @Sendable (DownloadProgress) -> Void) async throws -> Void
    ) async {
        do {
            try await perform(offer, { progress in
                Task { @MainActor [weak self] in self?.progressed(progress) }
            })
            state = .idle
            self.offer = nil
        } catch {
            state = .failed(ContentUpdater.message(for: error))
        }
    }

    private func progressed(_ progress: DownloadProgress) {
        if state.isBusy { state = .downloading(progress) }
    }
}

/// Gallery for snapshot tests: eligible, notes, ineligible, downloading and failed.
public struct UpdateBannerShowcase: View {
    private let rtl: Bool

    @Environment(\.colorScheme) private var colorScheme

    public init(rtl: Bool = false) {
        self.rtl = rtl
    }

    public var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        VStack(spacing: 16) {
            UpdateBannerView(offer: ContentUpdateOffer(version: 4, manifestSha256: "a", eligible: true))
            UpdateBannerView(offer: ContentUpdateOffer(version: 5, manifestSha256: "a", eligible: true, notes: "New lessons on food and travel."))
            UpdateBannerView(offer: ContentUpdateOffer(version: 6, manifestSha256: "a", eligible: false))
            UpdateBannerView(
                offer: ContentUpdateOffer(version: 4, manifestSha256: "a", eligible: true),
                state: .downloading(DownloadProgress(done: 12, discovered: 40)))
            UpdateBannerView(
                offer: ContentUpdateOffer(version: 4, manifestSha256: "a", eligible: true),
                state: .failed("Couldn't update the course."))
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(argb: p.bg))
        .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
    }
}
