import Foundation
import Combine
import QModel
import QNetwork

/// First-signup onboarding (web OnboardingFlow, Android OnboardingViewModel):
/// name, languages, then the intro tutorial. There is no back navigation, as on
/// both clients: each answer is saved as it is given.
///
/// State machine: `isSubmitting` is set synchronously before the first await, so a
/// second call while one is in flight is a no-op. Once `isFinished` nothing else runs.
/// The catalog load reports through its own `catalogError`, so it can never clobber
/// a submit error or an in-flight submit.
@MainActor
public final class OnboardingViewModel: ObservableObject {
    @Published public private(set) var step: OnboardingStep
    @Published public var displayName: String = "" {
        didSet {
            if displayName.count > OnboardingRules.maxNameLength {
                displayName = String(displayName.prefix(OnboardingRules.maxNameLength))
            }
            error = nil
        }
    }
    @Published public private(set) var catalog: [CourseCatalogEntry]?
    @Published public private(set) var catalogError: String?
    @Published public private(set) var isSubmitting = false
    @Published public private(set) var error: String?
    /// True once the tutorial was finished or skipped; terminal.
    @Published public private(set) var isFinished = false

    private let service: OnboardingService
    private let stepStore: OnboardingStepStore
    private let onBootstrap: @MainActor (BootstrapResponse) -> Void
    private let onComplete: @MainActor (Bool) -> Void
    private var isLoadingCatalog = false

    /// - Parameters:
    ///   - onBootstrap: called once, with the final bootstrap after all courses are enrolled
    ///     (never with an intermediate one, which would count as onboarded too early).
    ///   - onComplete: called once when the tutorial ends, with the server's flag (true if the call failed).
    public init(
        service: OnboardingService,
        stepStore: OnboardingStepStore = InMemoryOnboardingStepStore(),
        onBootstrap: @escaping @MainActor (BootstrapResponse) -> Void = { _ in },
        onComplete: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.service = service
        self.stepStore = stepStore
        self.onBootstrap = onBootstrap
        self.onComplete = onComplete
        self.step = stepStore.step ?? .name
    }

    /// Android: a blank (after trimming) name is a silent no-op.
    public var canSubmitName: Bool {
        step == .name && !isFinished && !isSubmitting
            && !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func loadCatalog() async {
        if isLoadingCatalog { return }
        isLoadingCatalog = true
        catalogError = nil
        defer { isLoadingCatalog = false }
        do {
            catalog = try await service.catalog()
        } catch is CancellationError {
            // Left unloaded; the caller can ask again.
        } catch {
            catalogError = AuthRules.message(for: error, fallback: OnboardingRules.catalogFallback)
        }
    }

    public func submitName() async {
        guard canSubmitName else { return }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        await run(fallback: OnboardingRules.nameFallback) {
            _ = try await self.service.setDisplayName(name)
            self.goTo(.languages)
        }
    }

    /// Enrolls in every picked course in the order given, then makes the first one active.
    /// Repeated codes are enrolled once.
    public func startLearning(courseCodes: [String]) async {
        guard step == .languages, !isFinished, !isSubmitting else { return }
        var codes: [String] = []
        for code in courseCodes where !codes.contains(code) { codes.append(code) }
        guard let first = codes.first else { return }
        await run(fallback: OnboardingRules.enrollFallback) {
            let bootstrap = try await self.service.enrollAll(courseCodes: codes, active: first)
            self.onBootstrap(bootstrap)
            self.goTo(.tutorial)
        }
    }

    /// Finished or skipped: either way it has been shown once. A failed call still finishes
    /// (Android marks it done locally so the learner is never stuck on the tutorial).
    public func finishTutorial() async {
        guard step == .tutorial, !isFinished, !isSubmitting else { return }
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }
        let done: Bool
        do {
            done = try await service.completeOnboarding()
        } catch is CancellationError {
            return
        } catch {
            done = true
        }
        isFinished = true
        stepStore.step = nil
        onComplete(done)
    }

    private func goTo(_ next: OnboardingStep) {
        stepStore.step = next
        step = next
    }

    private func run(fallback: String, _ action: () async throws -> Void) async {
        if isSubmitting || isFinished { return }
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }
        do {
            try await action()
        } catch is CancellationError {
            // Stay on the step with no message.
        } catch {
            self.error = AuthRules.message(for: error, fallback: fallback)
        }
    }
}
