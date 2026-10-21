import SwiftUI
import QModel
import QDomain
import QDesign

/// Saved words as flashcards (web FlashcardsPage, Android FlashcardsScreen).
public struct FlashcardsScreen: View {
    @ObservedObject private var model: FlashcardsModel
    private let onBack: () -> Void

    public init(model: FlashcardsModel, onBack: @escaping () -> Void) {
        self.model = model
        self.onBack = onBack
    }

    public var body: some View {
        if let round = model.clozeRound {
            ClozeRoundView(model: round, onExit: { model.leaveCloze() })
                .navigationTitle("Fill in the blank")
        } else {
            ScrollView {
                FlashcardsContent(model: model, onBack: onBack).padding(16).frame(maxWidth: .infinity)
            }
            .navigationTitle("Flashcards")
            .task { await model.refresh() }
        }
    }
}

struct FlashcardsContent: View {
    @ObservedObject var model: FlashcardsModel
    let onBack: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        VStack(alignment: .leading, spacing: 16) {
            if model.store.status != .ready {
                VocabStatusView(status: model.store.status, p: p) { Task { await model.refresh() } }
            } else if model.deck == nil || (model.words.isEmpty && !model.isSettlingXp) {
                start(p)
            } else if let current = model.current, let deck = model.deck {
                ProgressView(value: Double(model.results.count), total: Double(deck.count))
                    .tint(Color(argb: p.primary))
                FlashcardView(word: current, courseCode: model.courseCode, kind: model.kind, p: p) { correct in
                    Task { await model.answer(correct: correct) }
                }
                .id(model.results.count)
            } else {
                done(p)
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    @ViewBuilder
    private func start(_ p: AppPalette) -> some View {
        Text("Flashcards").font(.title2.weight(.bold)).foregroundColor(Color(argb: p.text))
            .accessibilityAddTraits(.isHeader)
        if model.words.isEmpty {
            Text("You haven't saved any words from this course yet. Save words with the \u{2605} on the vocabulary list, or after an answer in a lesson.")
                .foregroundColor(Color(argb: p.text))
        } else {
            Picker("Card type", selection: Binding(get: { model.kind }, set: { model.setKind($0) })) {
                Text("Type the meaning").tag(FlashcardKind.translation)
                Text("Flip cards").tag(FlashcardKind.selfRated)
                if model.canPlayCloze { Text("Fill in").tag(FlashcardKind.cloze) }
            }
            .pickerStyle(.segmented)
            Text(startNote)
                .font(.subheadline).foregroundColor(Color(argb: p.textMuted))
            if model.kind == .cloze {
                Toggle("Hardcore: no typos forgiven", isOn: $model.hardcore)
                    .foregroundColor(Color(argb: p.text))
            }
            if model.kind == .cloze {
                primaryButton("Start", p) { model.start() }
            } else {
                let count = min(model.words.count, FlashcardsModel.roundSize)
                primaryButton("Start \(count) card\(count == 1 ? "" : "s")", p) { model.start() }
            }
        }
        Button("Back to vocabulary") { model.stop(); onBack() }.buttonStyle(.bordered)
    }

    /// What the chosen card type earns, under the picker.
    private var startNote: String {
        switch model.kind {
        case .translation:
            return "Each meaning you get right earns 5 XP. Flashcards don't change your review schedule."
        case .selfRated:
            return "Flipping cards is practice only. It earns XP inside a saved-words remix. Flashcards don't change your review schedule."
        case .cloze:
            return "A sentence from a Parsle you've done, with a saved word taken out: type it. A right answer pays 5 XP on the first try, 3 on the second and 1 on the third. Each answer counts as a review of the word, so this one does change your review schedule."
        }
    }

    @ViewBuilder
    private func done(_ p: AppPalette) -> some View {
        let correct = model.results.filter { $0.correct }.count
        Text("Round complete!").font(.title2.weight(.bold)).foregroundColor(Color(argb: p.text))
            .accessibilityAddTraits(.isHeader)
        Text("\(correct) / \(model.results.count) correct").font(.body.weight(.bold)).foregroundColor(Color(argb: p.text))
        if model.kind == .translation {
            switch model.xp {
            case .saving:
                Text("Saving your XP\u{2026}").foregroundColor(Color(argb: p.textMuted))
            case .saved(let xp):
                let text = xp > 0 ? "+\(xp) XP" : (correct > 0 ? "You've earned today's flashcard XP already." : "No XP this round.")
                Text(text).foregroundColor(Color(argb: p.textMuted))
            case .failed(let message):
                Text(message).foregroundColor(Color(argb: p.danger))
                Button("Try saving again") { Task { await model.retrySubmit() } }.buttonStyle(.bordered)
                Button("Discard this round's XP", role: .destructive) { model.discardRound() }.buttonStyle(.bordered)
            case .idle:
                EmptyView()
            }
        }
        primaryButton("Another round", p) { model.start() }
            .disabled(model.isSettlingXp)
        Button("Back to vocabulary") { model.stop(); onBack() }.buttonStyle(.bordered)
            .disabled(model.isSettlingXp)
    }

    private func primaryButton(_ title: String, _ p: AppPalette, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.body.weight(.bold)).foregroundColor(Color(argb: p.primaryContrast))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: Radii.standard.md).fill(Color(argb: p.primary)))
        }
        .buttonStyle(.plain)
    }
}

/// One saved word as a flashcard (web Flashcard). Self-rated: flip it to see the meaning, then say
/// whether you knew it. Translation: type the meaning, graded on the device, then continue.
/// `onAnswered` fires once, as the learner moves past the card.
struct FlashcardView: View {
    let word: FlashcardWord
    let courseCode: String?
    let kind: FlashcardKind
    let p: AppPalette
    let onAnswered: (Bool) -> Void
    @State private var flipped = false
    @State private var typed = ""
    @State private var graded: Bool?
    @State private var answered = false
    @ScaledMetric(relativeTo: .largeTitle) private var surfaceSize: CGFloat = 36

    init(word: FlashcardWord, courseCode: String?, kind: FlashcardKind, p: AppPalette, flipped: Bool = false, typed: String = "", graded: Bool? = nil, onAnswered: @escaping (Bool) -> Void) {
        self.word = word
        self.courseCode = courseCode
        self.kind = kind
        self.p = p
        self.onAnswered = onAnswered
        _flipped = State(initialValue: flipped)
        _typed = State(initialValue: typed)
        _graded = State(initialValue: graded)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radii.standard.lg)
        VStack(spacing: 16) {
            vocabCourseText(word.surface, courseCode: courseCode, size: surfaceSize, weight: .bold, color: Color(argb: p.text))
            if flipped {
                Text(word.entry.gloss).font(.title3).multilineTextAlignment(.center).foregroundColor(Color(argb: p.text))
                if let roman = word.entry.romanization {
                    Text(roman).font(.body.italic()).foregroundColor(Color(argb: p.textMuted))
                }
            }
            if kind == .selfRated {
                if flipped {
                    HStack(spacing: 8) {
                        Button("Didn't know") { finish(false) }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                        Button("Knew it") { finish(true) }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                    }
                } else {
                    Button("Show meaning") { flipped = true }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                }
            } else {
                TextField("Type the meaning in English", text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .searchLikeInput()
                    .disabled(graded != nil)
                    .submitLabel(.done)
                    .onSubmit { check() }
                if let right = graded {
                    Text(right ? "Correct!" : "Not quite.").font(.body.weight(.bold))
                        .foregroundColor(Color(argb: right ? p.success : p.danger))
                }
                Button(graded == nil ? "Check" : "Continue") { check() }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                    .disabled(graded == nil && typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(argb: p.surface))
        .clipShape(shape)
        .overlay(shape.stroke(Color(argb: p.border), lineWidth: 2))
    }

    private func check() {
        if let result = graded {
            finish(result)
            return
        }
        if typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        graded = gradeTranslation(typed, gloss: word.entry.gloss)
        flipped = true
    }

    /// Fires once, so a double tap can't record the card twice.
    private func finish(_ correct: Bool) {
        if answered { return }
        answered = true
        onAnswered(correct)
    }
}

/// Fixed-content vocabulary list and flashcards for snapshot tests. `large` renders at an accessibility Dynamic Type size.
public struct VocabularyShowcase: View {
    private let large: Bool
    @StateObject private var list: SkillVocabularyModel
    private let card: FlashcardWord
    private let word2: FlashcardWord
    @Environment(\.colorScheme) private var colorScheme

    public init(large: Bool = false) {
        self.large = large
        let salam = "\u{0633}\u{0644}\u{0627}\u{0645}"
        let khoda = "\u{062E}\u{062F}\u{0627}\u{062D}\u{0627}\u{0641}\u{0638}"
        let nan = "\u{0646}\u{0627}\u{0646}<n>"
        let lexemes: [String: LexemeIndexEntry] = [
            salam: LexemeIndexEntry(gloss: "hello", romanization: "salam", romanizationIsAuthored: true),
            khoda: LexemeIndexEntry(gloss: "goodbye", romanization: "khodahafez", romanizationIsAuthored: true),
            nan: LexemeIndexEntry(gloss: "bread", romanization: "nan", romanizationIsAuthored: true),
        ]
        let units = [UnitVocab(unitKey: "u1", title: "Greetings", lessons: [
            LessonVocab(unitKey: "u1", skillKey: "s1", title: "Hello and goodbye", tags: [salam, khoda, nan]),
        ])]
        let now = Date()
        let cards = [
            salam: CardState(lexemeTag: salam, stability: 20, difficulty: 5, lastReviewedAt: now, dueAt: now.addingTimeInterval(86400), reviewCount: 4, lapseCount: 0),
            khoda: CardState(lexemeTag: khoda, stability: 3, difficulty: 5, lastReviewedAt: now, dueAt: now.addingTimeInterval(-3600), reviewCount: 1, lapseCount: 0),
        ]
        let store = VocabularyStore.preview(content: VocabContent(courseCode: "fa", units: units, lexemes: lexemes), cards: cards, starred: [salam])
        _list = StateObject(wrappedValue: SkillVocabularyModel(store: store, unitKey: "u1", skillKey: "s1", now: { now }))
        card = FlashcardWord(tag: salam, surface: salam, entry: lexemes[salam]!)
        word2 = FlashcardWord(tag: khoda, surface: khoda, entry: lexemes[khoda]!)
    }

    public var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        VStack(alignment: .leading, spacing: 24) {
            SkillVocabularyContent(model: list)
            Divider()
            FlashcardView(word: word2, courseCode: "fa", kind: .translation, p: p, flipped: true, typed: "goodbye", graded: true) { _ in }
            FlashcardView(word: card, courseCode: "fa", kind: .selfRated, p: p) { _ in }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(argb: p.bg))
        .environment(\.dynamicTypeSize, large ? .accessibility2 : .large)
    }
}
