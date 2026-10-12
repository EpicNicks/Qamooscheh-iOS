import SwiftUI
import QDesign

/// The intro tutorial (Android IntroTutorial, web OnboardingTutorialStep): a mock lesson in
/// plain English that teaches the controls, not the language. `onDone` fires on finishing or
/// on a confirmed skip; either way the tutorial counts as seen.
public struct OnboardingTutorialView: View {
    @ObservedObject private var state: OnboardingTutorialState
    private let isFinishing: Bool
    private let onDone: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var typingFocused: Bool

    public init(state: OnboardingTutorialState, isFinishing: Bool = false, onDone: @escaping () -> Void) {
        self.state = state
        self.isFinishing = isFinishing
        self.onDone = onDone
    }

    private var palette: AppPalette { colorScheme == .dark ? .dark : .light }

    public var body: some View {
        ZStack {
            Color(argb: palette.bg).ignoresSafeArea()
            if state.phase == .done {
                doneView
            } else {
                exercise
            }
        }
        .alert(
            state.confirmingSkip?.title ?? "Are you sure?",
            isPresented: Binding(
                get: { state.confirmingSkip != nil },
                set: { if !$0 { state.confirmingSkip = nil } }
            )
        ) {
            Button("Keep going", role: .cancel) { state.confirmingSkip = nil }
            Button("Skip", role: .destructive) {
                state.confirmingSkip = nil
                onDone()
            }
        } message: {
            Text("You can go straight to your first real lesson instead. You can replay this tutorial later from Settings.")
        }
        // A right answer stays on screen a moment before the next exercise (web: 700ms).
        .task(id: state.feedback) {
            if state.feedback == .correct {
                try? await Task.sleep(nanoseconds: 700_000_000)
                if !Task.isCancelled { state.advance() }
            }
        }
    }

    private var isWordBank: Bool { state.phase == .wordBank }

    private func highlighted(_ target: TutorialTarget) -> Bool {
        state.callout?.target == target
    }

    private var exercise: some View {
        VStack(alignment: .leading, spacing: Spacing.standard.s4) {
            HStack {
                Text(isWordBank ? "Step 1 of 2" : "Step 2 of 2")
                    .foregroundColor(Color(argb: palette.textMuted))
                    .accessibilityLabel(isWordBank ? "Tutorial step 1 of 2" : "Tutorial step 2 of 2")
                Spacer()
                Button {
                    state.confirmingSkip = .link
                } label: {
                    Text("Skip tutorial").foregroundColor(Color(argb: palette.current))
                }
                .accessibilityLabel("Skip tutorial")
            }
            Text(isWordBank ? "Tap the word for \u{201C}Hello\u{201D}" : "Type the word for \u{201C}Onward\u{201D}")
                .font(.title2.weight(.semibold))
                .foregroundColor(Color(argb: palette.text))
                .accessibilityAddTraits(.isHeader)
                .calloutRing(highlighted(.prompt), palette: palette)
            if isWordBank {
                wordBank.calloutRing(highlighted(.answer), palette: palette)
            } else {
                typeIn.calloutRing(highlighted(.answer), palette: palette)
            }
            if let feedback = state.feedback {
                Text(feedback.text)
                    .font(.body.weight(.semibold))
                    .foregroundColor(Color(argb: feedback == .correct ? palette.success : palette.danger))
                    .accessibilityLabel(feedback.text)
            }
            Spacer(minLength: 0)
            if let callout = state.callout {
                calloutCard(callout)
            }
            AuthPrimaryButton(title: "Submit", palette: palette, enabled: true) {
                typingFocused = false
                state.submit()
            }
            .calloutRing(highlighted(.submit), palette: palette)
        }
        .padding(Spacing.standard.s3)
    }

    private var wordBank: some View {
        VStack(spacing: Spacing.standard.s4) {
            HStack(spacing: Spacing.standard.s2) {
                ForEach(state.chosen, id: \.self) { index in tile(index) }
                Spacer(minLength: 0)
            }
            .padding(Spacing.standard.s2)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: Radii.standard.md).stroke(Color(argb: palette.border), lineWidth: 2)
            )
            .accessibilityLabel("Your answer")
            HStack(spacing: Spacing.standard.s2) {
                ForEach(Array(OnboardingTutorialState.wordBankTiles.indices.filter { !state.chosen.contains($0) }), id: \.self) { index in
                    tile(index)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Word bank")
        }
    }

    private func tile(_ index: Int) -> some View {
        let word = OnboardingTutorialState.wordBankTiles[index]
        return Button {
            state.toggleTile(index)
        } label: {
            Text(word)
                .font(.system(size: 18))
                .foregroundColor(Color(argb: palette.text))
                .padding(.horizontal, Spacing.standard.s3)
                .padding(.vertical, Spacing.standard.s2)
                .background(RoundedRectangle(cornerRadius: Radii.standard.sm).fill(Color(argb: palette.surface)))
                .overlay(RoundedRectangle(cornerRadius: Radii.standard.sm).stroke(Color(argb: palette.border), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(word)
        .accessibilityHint(state.chosen.contains(index) ? "Removes this word from your answer" : "Adds this word to your answer")
    }

    private var typeIn: some View {
        AuthFieldBox(label: "Your answer", palette: palette) {
            TextField("", text: Binding(get: { state.typed }, set: { state.type($0) }))
                .focused($typingFocused)
                .submitLabel(.done)
                .onSubmit {
                    typingFocused = false
                    state.submit()
                }
                .accessibilityLabel("Your answer")
        }
    }

    private func calloutCard(_ callout: TutorialCallout) -> some View {
        VStack(alignment: .leading, spacing: Spacing.standard.s2) {
            Text(callout.title)
                .font(.headline)
                .foregroundColor(Color(argb: palette.text))
            Text(callout.description)
                .font(.subheadline)
                .foregroundColor(Color(argb: palette.textMuted))
            HStack(spacing: Spacing.standard.s3) {
                // Only silences the callouts, so it never asks first.
                Button("Skip tutorial") { state.hideCallouts() }
                    .foregroundColor(Color(argb: palette.textMuted))
                Spacer()
                Button(state.isLastCallout ? "Got it" : "Next") { state.nextCallout() }
                    .font(.body.weight(.bold))
                    .foregroundColor(Color(argb: palette.current))
            }
        }
        .padding(Spacing.standard.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radii.standard.md).fill(Color(argb: palette.surface)))
        .overlay(RoundedRectangle(cornerRadius: Radii.standard.md).stroke(Color(argb: palette.current), lineWidth: 2))
        .accessibilityElement(children: .contain)
    }

    private var doneView: some View {
        VStack(spacing: Spacing.standard.s3) {
            Text("Nice work!")
                .font(.title.weight(.bold))
                .foregroundColor(Color(argb: palette.text))
                .accessibilityAddTraits(.isHeader)
            Text("That's the shape of every lesson \u{2014} read the prompt, answer it, then check your work.")
                .multilineTextAlignment(.center)
                .foregroundColor(Color(argb: palette.textMuted))
            AuthPrimaryButton(title: isFinishing ? "Finishing\u{2026}" : "Continue", palette: palette, enabled: !isFinishing, action: onDone)
                .frame(maxWidth: 420)
        }
        .padding(Spacing.standard.s4)
    }
}

private extension View {
    /// Outlines the control a callout is pointing at.
    func calloutRing(_ on: Bool, palette: AppPalette) -> some View {
        padding(on ? 4 : 0)
            .overlay(
                RoundedRectangle(cornerRadius: Radii.standard.md)
                    .stroke(Color(argb: palette.current), lineWidth: on ? 2 : 0)
            )
    }
}
