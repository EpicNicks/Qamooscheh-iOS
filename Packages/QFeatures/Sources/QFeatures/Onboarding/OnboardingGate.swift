import SwiftUI
import QModel
import QNetwork
import QDesign

/// Reads the bootstrap to learn whether the signed-in user has finished onboarding.
public protocol OnboardingBootstrapLoading: Sendable {
    func onboardingComplete() async throws -> Bool
}

/// GET /v1/bootstrap through the shared ApiClient.
public struct LiveBootstrapLoader: OnboardingBootstrapLoading {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    public func onboardingComplete() async throws -> Bool {
        let response: BootstrapResponse = try await client.send(.get, "/v1/bootstrap")
        return response.onboardingComplete
    }
}

/// What the onboarding gate runs against.
public struct OnboardingEnvironment: Sendable {
    public let bootstrap: OnboardingBootstrapLoading
    public let service: OnboardingService

    public init(bootstrap: OnboardingBootstrapLoading, service: OnboardingService) {
        self.bootstrap = bootstrap
        self.service = service
    }

    /// Shares the session store with the auth environment so tokens refresh in one place.
    public static func live(baseURL: URL, clientHeader: String, store: SessionStore) -> OnboardingEnvironment {
        let client = ApiClient(baseURL: baseURL, clientHeader: clientHeader, store: store)
        return OnboardingEnvironment(bootstrap: LiveBootstrapLoader(client: client), service: OnboardingApi(client: client))
    }
}

/// Wraps the signed-in app: shows onboarding while the bootstrap says it is not complete,
/// else the content. A failed bootstrap read offers a retry rather than skipping onboarding.
public struct OnboardingGate<Content: View>: View {
    private enum Phase { case loading, failed, onboarding, ready }

    private let environment: OnboardingEnvironment
    private let stepKey: String
    private let content: Content
    @State private var phase: Phase = .loading
    @Environment(\.colorScheme) private var colorScheme

    /// - Parameter stepKey: UserDefaults key for the saved step.
    public init(environment: OnboardingEnvironment, stepKey: String = "qamooscheh.onboarding.step", @ViewBuilder content: () -> Content) {
        self.environment = environment
        self.stepKey = stepKey
        self.content = content()
    }

    private var palette: AppPalette { colorScheme == .dark ? .dark : .light }

    public var body: some View {
        switch phase {
        case .loading:
            ProgressView()
                .accessibilityLabel("Loading")
                .task { await load() }
        case .failed:
            VStack(spacing: Spacing.standard.s3) {
                Text("Couldn't load your account.")
                    .foregroundColor(Color(argb: palette.text))
                AuthPrimaryButton(title: "Try again", palette: palette, enabled: true) {
                    phase = .loading
                }
                .frame(maxWidth: 240)
            }
            .padding(Spacing.standard.s3)
        case .onboarding:
            OnboardingFlowHost(
                service: environment.service,
                stepKey: stepKey,
                onComplete: { phase = .ready }
            )
        case .ready:
            content
        }
    }

    private func load() async {
        do {
            let complete = try await environment.bootstrap.onboardingComplete()
            phase = complete ? .ready : .onboarding
        } catch is CancellationError {
            // The view went away; a later appearance reloads.
        } catch {
            phase = .failed
        }
    }
}

/// Owns the view model for the life of the onboarding flow.
struct OnboardingFlowHost: View {
    @StateObject private var viewModel: OnboardingViewModel

    init(service: OnboardingService, stepKey: String, onComplete: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: OnboardingViewModel(
            service: service,
            stepStore: UserDefaultsOnboardingStepStore(key: stepKey),
            onComplete: { _ in onComplete() }
        ))
    }

    var body: some View {
        OnboardingFlowView(viewModel: viewModel)
    }
}
