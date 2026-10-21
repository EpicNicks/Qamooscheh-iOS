import SwiftUI
import QModel
import QDomain
import QDesign

/// The saved-words remix (web SavedPracticePage, Android SavedPracticeScreen): flashcards for the
/// most-due saved words, then `onExercises` plays their exercises on the lesson screen.
public struct SavedPracticeScreen: View {
    @ObservedObject private var model: SavedPracticeModel
    private let onBack: () -> Void
    private let onExercises: (SavedPracticeExercises) -> Void

    public init(model: SavedPracticeModel, onBack: @escaping () -> Void, onExercises: @escaping (SavedPracticeExercises) -> Void) {
        self.model = model
        self.onBack = onBack
        self.onExercises = onExercises
    }

    public var body: some View {
        Group {
            if let round = model.clozeRound {
                ClozeRoundView(model: round, onExit: { model.leaveCloze() })
            } else if case .choosing(let options, let selected, let none, let hardcore) = model.state {
                RemixContentsPickerView(
                    options: options, selected: selected, noneOfThat: none,
                    noneMessage: "Your saved words have none of those right now. Pick something else.",
                    backLabel: "Back to vocabulary",
                    hardcore: selected == .cloze ? hardcore : nil,
                    onSelect: { model.selectContents($0) }, onHardcoreChange: { model.setHardcore($0) },
                    onStart: { Task { await model.start() } }, onBack: onBack)
            } else {
                ScrollView {
                    SavedPracticeContent(model: model, onBack: onBack, onExercises: onExercises).padding(16).frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Saved words")
        .task { await model.load() }
    }
}

struct SavedPracticeContent: View {
    @ObservedObject var model: SavedPracticeModel
    let onBack: () -> Void
    let onExercises: (SavedPracticeExercises) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        VStack(alignment: .leading, spacing: 16) {
            switch model.state {
            case .loading:
                ProgressView("Gathering your saved words\u{2026}").frame(maxWidth: .infinity)
            case .failed(let message):
                Text(message).foregroundColor(Color(argb: p.danger))
                Button("Try again") { Task { await model.load() } }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                Button("Back to vocabulary", action: onBack).buttonStyle(.bordered).frame(maxWidth: .infinity)
            case .empty:
                Text("Nothing to practise yet").font(.title2.weight(.bold)).foregroundColor(Color(argb: p.text))
                    .accessibilityAddTraits(.isHeader)
                Text("Save words from this course \u{2014} with the \u{2605} on the vocabulary list, or after an answer in a lesson \u{2014} and they'll show up here.")
                    .foregroundColor(Color(argb: p.text))
                Button("Back to vocabulary", action: onBack).buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
            case .cards(let code, let cards, let results):
                ProgressView(value: Double(results.count), total: Double(max(cards.count, 1)))
                    .tint(Color(argb: p.primary))
                if let current = model.current {
                    FlashcardView(word: current, courseCode: code, kind: .selfRated, p: p) { knew in
                        Task { await model.answer(knew: knew) }
                    }
                    .id(results.count)
                } else {
                    ProgressView("Saving your progress\u{2026}").frame(maxWidth: .infinity)
                }
            case .choosing:
                // The screen shows the contents picker itself.
                EmptyView()
            case .cardsDone(let known, let total, let xp, let exercises):
                done(p, known: known, total: total, xp: xp, exercises: exercises)
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    @ViewBuilder
    private func done(_ p: AppPalette, known: Int, total: Int, xp: Int?, exercises: SavedPracticeExercises?) -> some View {
        Text("Flashcards done!").font(.title2.weight(.bold)).foregroundColor(Color(argb: p.text))
            .accessibilityAddTraits(.isHeader)
        if total > 0 {
            Text(savedPracticeSummary(known: known, total: total, xp: xp)).foregroundColor(Color(argb: p.text))
            if xp == nil {
                Text("Couldn't save the flashcards' XP.").foregroundColor(Color(argb: p.textMuted))
            }
        }
        if let exercises = exercises {
            Text(savedPracticeNext(count: exercises.count)).foregroundColor(Color(argb: p.textMuted))
            Button("Continue") { onExercises(exercises) }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
            Button("Back to vocabulary", action: onBack).buttonStyle(.bordered).frame(maxWidth: .infinity)
        } else {
            Button("Back to vocabulary", action: onBack).buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
        }
    }
}

/// "You knew 3 of 5 flashcards (+15 XP)."
func savedPracticeSummary(known: Int, total: Int, xp: Int?) -> String {
    let bonus = (xp ?? 0) > 0 ? " (+\(xp ?? 0) XP)" : ""
    return "You knew \(known) of \(total) flashcard\(total == 1 ? "" : "s")\(bonus)."
}

/// "Next: 4 exercises from lessons that use these words."
func savedPracticeNext(count: Int) -> String {
    "Next: \(count) exercise\(count == 1 ? "" : "s") from lessons that use these words."
}
