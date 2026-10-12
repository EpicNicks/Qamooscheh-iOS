import SwiftUI
import QFeatures

/// Builds the onboarding screens against a canned service, for snapshot tests.
@MainActor
enum OnboardingScreenFixtures {
    static func name(typed: String = "") async -> AnyView {
        let model = OnboardingViewModel(service: PreviewOnboardingService(), stepStore: InMemoryOnboardingStepStore(step: .name))
        model.displayName = typed
        return AnyView(OnboardingFlowView(viewModel: model))
    }

    static func languages() async -> AnyView {
        let model = OnboardingViewModel(service: PreviewOnboardingService(), stepStore: InMemoryOnboardingStepStore(step: .languages))
        await model.loadCatalog()
        return AnyView(OnboardingFlowView(viewModel: model))
    }

    enum TutorialShot { case wordBankCallout, typeIn, done }

    static func tutorial(_ shot: TutorialShot) -> AnyView {
        let state = OnboardingTutorialState()
        switch shot {
        case .wordBankCallout:
            state.nextCallout()
            state.toggleTile(0)
        case .typeIn:
            state.toggleTile(0)
            state.submit()
            state.advance()
            state.hideCallouts()
            state.type("Onward")
        case .done:
            state.toggleTile(0)
            state.submit()
            state.advance()
            state.type("Onward")
            state.submit()
            state.advance()
        }
        return AnyView(OnboardingTutorialView(state: state, onDone: {}))
    }
}
