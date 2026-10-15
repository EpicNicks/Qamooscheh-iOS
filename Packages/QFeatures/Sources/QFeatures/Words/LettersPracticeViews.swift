import SwiftUI
import QModel
import QDomain
import QDesign

/// Letters practice (spec 9.8, Android LettersPracticeScreen): about ten multiple-choice questions on
/// the Persian letters, each graded the moment an option is tapped, misses coming back a few
/// questions later. Local only, so leaving loses nothing.
public struct LettersPracticeScreen: View {
    @ObservedObject private var model: LettersPracticeModel
    private let onBack: () -> Void

    public init(model: LettersPracticeModel, onBack: @escaping () -> Void) {
        self.model = model
        self.onBack = onBack
    }

    public var body: some View {
        LettersPracticeContent(model: model, onBack: onBack)
            .navigationTitle("Letters practice")
    }
}

/// "on its own", "at the start of a word", ...
func lettersPositionText(_ form: LetterForm) -> String {
    switch form {
    case .isolated: return "on its own"
    case .initial: return "at the start of a word"
    case .medial: return "in the middle of a word"
    case .final: return "at the end of a word"
    }
}

func lettersInstruction(_ question: LetterQuestion) -> String {
    switch question.kind {
    case .letterToSound: return "What sound does this letter make?"
    case .soundToLetter, .formToLetter: return "Which letter is this?"
    case .letterToForm: return "How is this letter written \(lettersPositionText(question.form))?"
    }
}

/// Persian text at `size` in the Persian face, right to left.
private func persianText(_ text: String, size: CGFloat, weight: Font.Weight = .regular, color: Color) -> some View {
    Text(text)
        .font(ScriptFonts().font(.persian, size: size, weight: weight))
        .foregroundColor(color)
        .environment(\.layoutDirection, .rightToLeft)
}

struct LettersPracticeContent: View {
    @ObservedObject var model: LettersPracticeModel
    let onBack: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        let state = model.state
        ZStack {
            Color(argb: p.bg).ignoresSafeArea()
            if state.finished || state.question == nil {
                LettersResults(session: state.session, p: p, onAgain: { model.again() }, onDone: onBack)
            } else if let question = state.question {
                LettersQuestionView(
                    question: question, progress: state.review?.session ?? state.session, review: state.review, p: p,
                    onChoose: { model.choose($0) }, onContinue: { model.continueOn() })
            }
        }
    }
}

struct LettersQuestionView: View {
    let question: LetterQuestion
    let progress: LettersSession
    let review: LetterAnswer?
    let p: AppPalette
    let onChoose: (Int) -> Void
    let onContinue: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var glyphSize: CGFloat = 88
    @ScaledMetric(relativeTo: .title) private var optionSize: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(progress.completedCount), total: Double(max(progress.totalCount, 1)))
                .tint(Color(argb: p.primary))
                .padding(16)
                .accessibilityLabel("\(progress.completedCount) of \(progress.totalCount) done")
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if question.attempt > 0 {
                        Text("Let's try this one again.").font(.subheadline.weight(.bold)).foregroundColor(Color(argb: p.warning))
                    }
                    Text(lettersInstruction(question)).font(.title2.weight(.semibold)).foregroundColor(Color(argb: p.text))
                    prompt
                    options
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            if let review = review { feedback(review) }
        }
    }

    private var prompt: some View {
        let shape = RoundedRectangle(cornerRadius: Radii.standard.lg)
        let sound = soundOf(question.letter.sound)
        return VStack(spacing: 6) {
            if let glyph = question.promptGlyph {
                persianText(glyph, size: glyphSize, color: Color(argb: p.text))
                if question.kind == .formToLetter {
                    Text("Written \(lettersPositionText(question.form))")
                        .font(.footnote.weight(.bold)).foregroundColor(Color(argb: p.current))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .overlay(Capsule().stroke(Color(argb: p.current), lineWidth: 1))
                }
            } else {
                Text(question.letter.nameRomanized).font(.system(size: 40, weight: .heavy)).foregroundColor(Color(argb: p.text))
                Text("Sounds like \(sound.label), \(sound.hint)").font(.subheadline)
                    .multilineTextAlignment(.center).foregroundColor(Color(argb: p.textMuted))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 168)
        .background(Color(argb: p.surface))
        .clipShape(shape)
        .overlay(shape.stroke(Color(argb: p.border), lineWidth: 2))
    }

    /// Four options in a two-by-two grid. On review the right one turns green and a wrong pick red.
    private var options: some View {
        VStack(spacing: 12) {
            ForEach(Array(question.options.indices.chunked(into: 2).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { index in tile(index) }
                }
            }
        }
    }

    private func tile(_ index: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radii.standard.md)
        var fill = p.surface
        var edge = p.border
        var faded = false
        if let review = review {
            if index == question.answerIndex {
                fill = p.successBg
                edge = p.success
            } else if index == review.choice {
                fill = p.dangerBg
                edge = p.danger
            } else {
                faded = true
            }
        }
        let text = question.options[index]
        return Button { onChoose(index) } label: {
            Group {
                if question.optionsArePersian {
                    persianText(text, size: optionSize, color: Color(argb: p.text))
                } else {
                    Text(text).font(.title3.weight(.bold)).multilineTextAlignment(.center).foregroundColor(Color(argb: p.text))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: question.optionsArePersian ? 96 : 64)
            .background(Color(argb: fill))
            .clipShape(shape)
            .overlay(shape.stroke(Color(argb: edge), lineWidth: 2))
            .opacity(faded ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(review != nil)
    }

    /// "Correct!" or "Not quite." with what the letter is, then Continue.
    private func feedback(_ review: LetterAnswer) -> some View {
        let accent = Color(argb: review.correct ? p.success : p.danger)
        let sound = soundOf(question.letter.sound)
        return VStack(alignment: .leading, spacing: 8) {
            Text(review.correct ? "Correct!" : "Not quite.").font(.title2.weight(.heavy)).foregroundColor(accent)
            HStack(spacing: 8) {
                persianText(question.letter.letter, size: 28, weight: .bold, color: accent)
                Text("\(question.letter.nameRomanized) \u{00B7} \(sound.label), \(sound.hint)")
                    .font(.body.weight(.semibold)).foregroundColor(Color(argb: p.text))
            }
            if review.requeued {
                Text("You'll see this one again in a moment.").font(.subheadline).foregroundColor(Color(argb: p.text))
            }
            Button(action: onContinue) {
                Text("Continue").font(.body.weight(.bold)).foregroundColor(Color(argb: p.primaryContrast))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: Radii.standard.md).fill(review.correct ? Color(argb: p.primary) : Color(argb: p.danger)))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(argb: review.correct ? p.successBg : p.dangerBg))
        .accessibilityElement(children: .contain)
    }
}

/// The end screen: first-try score, and the way back in or out.
struct LettersResults: View {
    let session: LettersSession
    let p: AppPalette
    let onAgain: () -> Void
    let onDone: () -> Void

    var body: some View {
        let pct = Int((session.score * 100).rounded())
        ScrollView {
            VStack(spacing: 16) {
                persianText("\u{0627}\u{0644}\u{0641}\u{0628}\u{0627}", size: 56, color: Color(argb: p.current))
                Text(pct == 100 ? "Perfect round!" : "Practice complete!")
                    .font(.title.weight(.bold)).foregroundColor(Color(argb: p.text))
                    .accessibilityAddTraits(.isHeader)
                Text("Practice only \u{2014} nothing is saved or added to your reviews.")
                    .multilineTextAlignment(.center).foregroundColor(Color(argb: p.textMuted))
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(session.firstTryCorrect) / \(session.totalCount) right first time")
                        .font(.body.weight(.bold)).foregroundColor(Color(argb: p.text))
                    ProgressView(value: Double(pct), total: 100).tint(Color(argb: p.primary))
                    Text("\(pct)%").font(.body.weight(.bold)).foregroundColor(Color(argb: p.text))
                }
                .frame(maxWidth: 420)
                VStack(spacing: 8) {
                    Button("Practice again", action: onAgain).buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                    Button("Done", action: onDone).buttonStyle(.bordered).frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 420)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }
}

private extension Range where Bound == Int {
    func chunked(into size: Int) -> [[Int]] {
        stride(from: lowerBound, to: upperBound, by: size).map { Array($0..<Swift.min($0 + size, upperBound)) }
    }
}

/// Fixed-content letters practice and saved-words practice for snapshot tests. `large` renders at an accessibility Dynamic Type size.
public struct PracticeShowcase: View {
    private let large: Bool
    @StateObject private var wrongModel: LettersPracticeModel
    @StateObject private var doneModel: LettersPracticeModel
    @StateObject private var saved: SavedPracticeModel
    @StateObject private var savedDone: SavedPracticeModel
    @Environment(\.colorScheme) private var colorScheme

    public init(large: Bool = false) {
        self.large = large
        let letters = Array(abjadLetters.prefix(8))
        var rng = SystemRandomNumberGenerator()
        // A sound question for the second letter, answered wrongly.
        let question = letterQuestion(.letterToSound, letters[1], using: &rng, letters: abjadLetters)
        let wrong = (question.answerIndex + 1) % letterOptionCount
        let session = LettersSession(queue: [question, letterQuestion(.soundToLetter, letters[2], using: &rng, letters: abjadLetters)])
        _wrongModel = StateObject(wrappedValue: LettersPracticeModel.preview(LettersPracticeState(session: session, review: session.answer(wrong))))
        let finished = LettersSession(queue: [], totalCount: 10, firstTryCorrect: 7)
        _doneModel = StateObject(wrappedValue: LettersPracticeModel.preview(LettersPracticeState(session: finished)))

        let salam = "\u{0633}\u{0644}\u{0627}\u{0645}"
        let entry = LexemeIndexEntry(gloss: "hello", romanization: "salam", romanizationIsAuthored: true)
        let store = VocabularyStore.preview(content: VocabContent(courseCode: "fa", units: [], lexemes: [salam: entry]), cards: [:], starred: [salam])
        let word = FlashcardWord(tag: salam, surface: salam, entry: entry)
        _saved = StateObject(wrappedValue: SavedPracticeModel.preview(store: store, state: .cards(courseCode: "fa", cards: [word, word], results: [])))
        let exercises = SavedPracticeExercises(courseVersion: 3, exercises: "u1/s1/0,u1/s1/1", count: 2)
        _savedDone = StateObject(wrappedValue: SavedPracticeModel.preview(store: store, state: .cardsDone(known: 1, total: 2, xp: 10, exercises: exercises)))
    }

    public var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        VStack(alignment: .leading, spacing: 24) {
            if let question = wrongModel.state.question {
                LettersQuestionView(question: question, progress: wrongModel.state.review?.session ?? wrongModel.state.session, review: wrongModel.state.review, p: p, onChoose: { _ in }, onContinue: {})
                    .frame(height: large ? 1500 : 760)
            }
            Divider()
            LettersResults(session: doneModel.state.session, p: p, onAgain: {}, onDone: {})
            Divider()
            SavedPracticeContent(model: saved, onBack: {}, onExercises: { _ in })
            SavedPracticeContent(model: savedDone, onBack: {}, onExercises: { _ in })
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(argb: p.bg))
        .environment(\.dynamicTypeSize, large ? .accessibility2 : .large)
    }
}
