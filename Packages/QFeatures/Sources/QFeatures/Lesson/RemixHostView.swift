import SwiftUI
import QDesign
import QDomain

/// A topics Repack: the contents picker, then the lesson or the fill-in-the-blank round it leads to.
public struct RemixHostView: View {
    @StateObject private var model: RemixHostModel
    private let onExit: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    public init(model: @autoclosure @escaping () -> RemixHostModel, onExit: @escaping () -> Void) {
        _model = StateObject(wrappedValue: model())
        self.onExit = onExit
    }

    public var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        switch model.stage {
        case .choosing(let selected, let none, let hardcore):
            RemixContentsPickerView(
                options: model.options, selected: selected, noneOfThat: none,
                hardcore: selected == .cloze ? hardcore : nil,
                onSelect: { model.select($0) }, onHardcoreChange: { model.setHardcore($0) },
                onStart: { Task { await model.start() } }, onBack: onExit)
        case .working:
            ZStack {
                Color(argb: p.bg).ignoresSafeArea()
                ProgressView().accessibilityLabel("Loading")
            }
        case .failed(let message):
            ZStack {
                Color(argb: p.bg).ignoresSafeArea()
                VStack(spacing: Spacing.standard.s3) {
                    Text(LessonScreenLogic.failedTitle)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(Color(argb: p.text))
                    Text(message)
                        .foregroundColor(Color(argb: p.textMuted))
                        .multilineTextAlignment(.center)
                    Button("Try again") { model.retry() }.buttonStyle(.bordered)
                    Button(LessonScreenLogic.backToPath, action: onExit).buttonStyle(.bordered)
                }
                .padding(Spacing.standard.s4)
            }
        case .lesson(let session):
            LessonScreen(session: session, onExit: onExit)
        case .cloze(let round):
            ClozeRoundView(model: round, onExit: onExit)
        }
    }
}
