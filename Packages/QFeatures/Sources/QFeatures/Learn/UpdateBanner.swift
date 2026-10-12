import SwiftUI
import QData
import QDesign

/// "Course update available" prompt on the Path (Android `CourseUpdateBanner`).
/// Dismissal lasts until the path is next opened, as on Android and the web.
public struct UpdateBannerView: View {
    private let offer: ContentUpdateOffer
    private let state: ContentUpdateState
    private let palette: AppPalette?
    private let onUpdate: () -> Void
    private let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    public init(
        offer: ContentUpdateOffer,
        state: ContentUpdateState = .idle,
        palette: AppPalette? = nil,
        onUpdate: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {}
    ) {
        self.offer = offer
        self.state = state
        self.palette = palette
        self.onUpdate = onUpdate
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
    }
}

/// Drives the banner: the offer, the in-flight state and per-visit dismissal.
@MainActor
public final class UpdateBannerModel: ObservableObject {
    @Published public private(set) var offer: ContentUpdateOffer?
    @Published public private(set) var state: ContentUpdateState = .idle
    @Published public private(set) var dismissed = false

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

    /// Downloads the offered version, then runs `commit` (the server roll-forward).
    /// Failure leaves the old version pinned and shows a message on the banner.
    public func accept(updater: ContentUpdater, courseCode: String, commit: @escaping @Sendable (Int) async throws -> Void) async {
        guard let offer = offer, !state.isBusy else { return }
        state = .downloading(DownloadProgress(done: 0, discovered: 0))
        do {
            try await updater.accept(
                courseCode: courseCode, offer: offer,
                onProgress: { progress in
                    Task { @MainActor [weak self] in self?.progressed(progress) }
                },
                commit: commit)
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
