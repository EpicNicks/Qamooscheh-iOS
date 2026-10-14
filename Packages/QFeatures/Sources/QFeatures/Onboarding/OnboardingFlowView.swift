import SwiftUI
import QModel
import QDesign

/// The onboarding flow bound to OnboardingViewModel (Android OnboardingScreen): a setup card
/// for the name and languages steps, the whole screen for the tutorial. There is no back
/// navigation on either client, so there is no back button: each answer is saved as given.
public struct OnboardingFlowView: View {
    @ObservedObject private var viewModel: OnboardingViewModel
    @StateObject private var tutorial = OnboardingTutorialState()
    @Environment(\.colorScheme) private var colorScheme

    public init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
    }

    private var palette: AppPalette { colorScheme == .dark ? .dark : .light }

    public var body: some View {
        if viewModel.step == .tutorial {
            OnboardingTutorialView(state: tutorial, isFinishing: viewModel.isSubmitting) {
                Task { await viewModel.finishTutorial() }
            }
        } else {
            AuthLayout {
                VStack(alignment: .leading, spacing: Spacing.standard.s3) {
                    OnboardingProgress(step: viewModel.step, palette: palette)
                    switch viewModel.step {
                    case .name:
                        OnboardingNameStep(viewModel: viewModel, palette: palette)
                    case .languages:
                        OnboardingLanguagesStep(viewModel: viewModel, palette: palette)
                    case .tutorial:
                        EmptyView()
                    }
                }
            }
        }
    }
}

/// "Step n of 3" plus a bar; read as one accessibility element.
struct OnboardingProgress: View {
    let step: OnboardingStep
    let palette: AppPalette

    private var index: Int { (OnboardingStep.allCases.firstIndex(of: step) ?? 0) + 1 }
    private var total: Int { OnboardingStep.allCases.count }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.standard.s1) {
            Text("Step \(index) of \(total)")
                .font(.footnote.weight(.semibold))
                .foregroundColor(Color(argb: palette.textMuted))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(argb: palette.border))
                    Capsule()
                        .fill(Color(argb: palette.primary))
                        .frame(width: proxy.size.width * CGFloat(index) / CGFloat(total))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(index) of \(total)")
    }
}

struct OnboardingHeading: View {
    let title: String
    let subtitle: String
    let palette: AppPalette

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.standard.s1) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundColor(Color(argb: palette.text))
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(Color(argb: palette.textMuted))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OnboardingNameStep: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let palette: AppPalette
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.standard.s3) {
            OnboardingHeading(
                title: "What should we call you?",
                subtitle: "This is the name friends and leaderboards see. You can change it later.",
                palette: palette
            )
            if let message = viewModel.error {
                AuthErrorBanner(message: message, palette: palette)
            }
            AuthFieldBox(label: "Display name", palette: palette) {
                TextField("", text: $viewModel.displayName)
                    .onboardingNameTraits()
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit { submit() }
                    .disabled(viewModel.isSubmitting)
                    .accessibilityLabel("Display name")
            }
            AuthPrimaryButton(
                title: viewModel.isSubmitting ? "Saving\u{2026}" : "Continue",
                palette: palette,
                enabled: viewModel.canSubmitName,
                action: submit
            )
        }
    }

    private func submit() {
        focused = false
        Task { await viewModel.submitName() }
    }
}

struct OnboardingLanguagesStep: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let palette: AppPalette

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.standard.s3) {
            OnboardingHeading(
                title: "What would you like to learn?",
                subtitle: "Pick one or more \u{2014} you can study several at once and switch between them any time. The first one you pick is where you'll start.",
                palette: palette
            )
            if let message = viewModel.error ?? viewModel.catalogError {
                AuthErrorBanner(message: message, palette: palette)
            }
            if let catalog = viewModel.catalog {
                CourseCatalogPicker(
                    courses: catalog,
                    submitting: viewModel.isSubmitting,
                    confirmLabel: "Start learning",
                    palette: palette
                ) { codes in
                    Task { await viewModel.startLearning(courseCodes: codes) }
                }
            } else if viewModel.catalogError != nil {
                AuthPrimaryButton(title: "Try again", palette: palette, enabled: true) {
                    Task { await viewModel.loadCatalog() }
                }
            } else {
                HStack(spacing: Spacing.standard.s2) {
                    ProgressView()
                    Text("Loading languages\u{2026}")
                        .font(.subheadline)
                        .foregroundColor(Color(argb: palette.textMuted))
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .task { if viewModel.catalog == nil { await viewModel.loadCatalog() } }
    }
}

/// Multi-select course list in pick order (Android CourseCatalogList, MULTI mode). The first
/// pick is where the learner starts. Culture facts show for the last row tapped.
struct CourseCatalogPicker: View {
    let courses: [CourseCatalogEntry]
    let submitting: Bool
    let confirmLabel: String
    let palette: AppPalette
    let onConfirm: ([String]) -> Void

    /// Below this many courses a search box is clutter.
    static let searchThreshold = 6

    @State private var query = ""
    @State private var picked: [String] = []
    @State private var fact: String?

    static func matches(_ course: CourseCatalogEntry, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return true }
        return [course.nativeName, course.latinName, course.code].contains {
            $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private var filtered: [CourseCatalogEntry] {
        courses.filter { Self.matches($0, query: query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.standard.s2) {
            if courses.count > Self.searchThreshold {
                AuthFieldBox(label: "Search languages", palette: palette) {
                    TextField("", text: $query)
                        .accessibilityLabel("Search languages")
                }
            }
            if filtered.isEmpty {
                Text("No languages match \u{201C}\(query.trimmingCharacters(in: .whitespacesAndNewlines))\u{201D}.")
                    .font(.subheadline)
                    .foregroundColor(Color(argb: palette.textMuted))
            }
            ForEach(filtered, id: \.code) { course in
                row(course)
            }
            if let fact = fact {
                Text("Did you know? \(fact)")
                    .font(.subheadline)
                    .foregroundColor(Color(argb: palette.text))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.standard.s3)
                    .background(RoundedRectangle(cornerRadius: Radii.standard.sm).fill(Color(argb: palette.surface)))
            }
            AuthPrimaryButton(
                title: submitting ? "Setting up\u{2026}" : confirmLabel,
                palette: palette,
                enabled: !picked.isEmpty && !submitting
            ) { onConfirm(picked) }
        }
    }

    private func row(_ course: CourseCatalogEntry) -> some View {
        let isPicked = picked.contains(course.code)
        let shape = RoundedRectangle(cornerRadius: Radii.standard.md)
        return Button {
            fact = course.cultureFacts.randomElement()
            if let position = picked.firstIndex(of: course.code) {
                picked.remove(at: position)
            } else {
                picked.append(course.code)
            }
        } label: {
            HStack(spacing: Spacing.standard.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.latinName)
                        .font(.headline)
                        .foregroundColor(Color(argb: palette.text))
                    Text(course.nativeName)
                        .font(.body)
                        .foregroundColor(Color(argb: palette.textMuted))
                }
                Spacer()
                if isPicked {
                    // Order matters: the first pick is where the learner starts.
                    Text(picked.first == course.code ? "Start here" : "\u{2713}")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(Color(argb: palette.primary))
                }
            }
            .padding(Spacing.standard.s3)
            .background(shape.fill(Color(argb: isPicked ? palette.successBg : palette.bg)))
            .overlay(shape.stroke(Color(argb: isPicked ? palette.primary : palette.border), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(submitting)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(course.latinName), \(course.nativeName)")
        .accessibilityValue(isPicked ? (picked.first == course.code ? "Selected, start here" : "Selected") : "Not selected")
        .accessibilityAddTraits(isPicked ? [.isButton, .isSelected] : [.isButton])
    }
}

/// iOS-only trait for the name field; a no-op where UIKit is absent so `swift test` on macOS compiles.
extension View {
    @ViewBuilder
    func onboardingNameTraits() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.words)
        #else
        self
        #endif
    }
}

/// A canned service for previews and snapshot tests. Never touches the network.
public struct PreviewOnboardingService: OnboardingService {
    public var courses: [CourseCatalogEntry]

    public init(courses: [CourseCatalogEntry] = PreviewOnboardingService.sampleCourses) {
        self.courses = courses
    }

    public static let sampleCourses = [
        CourseCatalogEntry(code: "fa", nativeName: "\u{0641}\u{0627}\u{0631}\u{0633}\u{06CC}", latinName: "Persian", cultureFacts: ["Persian poetry is still quoted in everyday speech."]),
        CourseCatalogEntry(code: "ja", nativeName: "\u{65E5}\u{672C}\u{8A9E}", latinName: "Japanese", cultureFacts: ["Japanese has three scripts used together."]),
        CourseCatalogEntry(code: "es", nativeName: "Espa\u{00F1}ol", latinName: "Spanish", cultureFacts: ["Spanish is spoken on four continents."]),
    ]

    public func catalog() async throws -> [CourseCatalogEntry] { courses }

    public func setDisplayName(_ displayName: String) async throws -> ProfileResponse {
        ProfileResponse(displayName: displayName)
    }

    public func enrollAll(courseCodes: [String], active: String) async throws -> BootstrapResponse {
        BootstrapResponse(graders: [], enrolledCourseCodes: courseCodes, onboardingComplete: false)
    }

    public func completeOnboarding() async throws -> Bool { true }

    public func enroll(courseCode: String) async throws -> BootstrapResponse {
        BootstrapResponse(graders: [], enrolledCourseCodes: [courseCode], onboardingComplete: true)
    }

    public func switchActive(courseCode: String) async throws -> BootstrapResponse {
        BootstrapResponse(
            course: CourseRef(code: courseCode, version: 1, manifestSha256: "h"),
            graders: [], enrolledCourseCodes: [courseCode], onboardingComplete: true)
    }
}
