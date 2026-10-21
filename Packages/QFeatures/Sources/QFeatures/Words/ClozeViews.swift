import SwiftUI
import QModel
import QDomain
import QDesign
import QData

// Fill-in-the-blank flashcards (web ClozeRound / ClozeCard, Android ClozeScreen). The card reuses the typed-answer
// field and the in-app keyboards a typed lesson exercise has; the sentence is one Text so Persian letters still join.

/// The sentence with the word's English in its place. Once answered the gap shows the word, green when right and red
/// when shown. The blank never offers its own hint: it is the answer. The "both" display's reading-over-word layout is
/// not used here: the line is plain text, like Android's.
struct ClozeSentenceView: View {
    @ObservedObject var model: ClozeCardModel
    let look: LessonTextLook
    let persianFamily: String?
    @Environment(\.colorScheme) private var colorScheme
    @State private var tip: WordTip?

    /// The planned runs of the text before and after the gap, in order: what a tapped link's index points into.
    private var plans: (before: AnnotatedPlan, after: AnnotatedPlan) {
        let card = model.card
        return (
            planAnnotatedText(card.before, scriptMode: .native, tags: card.contextTags, look: look),
            planAnnotatedText(card.after, scriptMode: .native, tags: card.contextTags, look: look))
    }

    private func attributedSentence(_ plans: (before: AnnotatedPlan, after: AnnotatedPlan), p: AppPalette) -> AttributedString {
        let ink = Color(argb: p.text)
        var attributed = AttributedString()
        func append(_ plan: AnnotatedPlan, offset: Int) {
            for (position, run) in plan.runs.enumerated() {
                var piece = AttributedString(run.text)
                if run.isTappable, let url = URL(string: "qamooscheh-tip://run/\(offset + position)") {
                    piece.link = url
                    piece.underlineStyle = .single
                    piece.foregroundColor = ink
                }
                attributed.append(piece)
            }
        }
        append(plans.before, offset: 0)
        var gap = AttributedString(" " + (model.answered ? model.gapText : model.card.gapLabel) + " ")
        gap.underlineStyle = .single
        gap.foregroundColor = Color(argb: !model.answered ? p.textMuted : (model.correct ? p.success : p.danger))
        attributed.append(gap)
        append(plans.after, offset: plans.before.runs.count)
        return attributed
    }

    var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        let card = model.card
        let planned = plans
        let runs = planned.before.runs + planned.after.runs
        let rtl = displayDirection(card.before + card.blankText + card.after, display: look.settings.display) == .rtl
        let font = DirectionalText.font(size: 22 * planned.before.fontScale, rtl: rtl, family: persianFamily).weight(.semibold)
        let ink = Color(argb: p.text)
        let centered = planned.before.centered
        VStack(alignment: .leading, spacing: 8) {
            Text(attributedSentence(planned, p: p))
                .font(font)
                .foregroundStyle(ink)
                .multilineTextAlignment(centered ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                .directionalText(rtl: rtl)
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == "qamooscheh-tip", let index = Int(url.lastPathComponent), runs.indices.contains(index) else { return .discarded }
                    let run = runs[index]
                    if !run.isTappable { return .discarded }
                    let tapped = WordTip(word: run.source, lines: run.tip)
                    tip = tip?.word == tapped.word ? nil : tapped
                    return .handled
                })
            if let shown = tip {
                VStack(alignment: .leading, spacing: 2) {
                    Text(shown.word).font(.system(size: 15, weight: .bold))
                    ForEach(Array(shown.lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 14))
                    }
                }
                .foregroundStyle(ink)
                .padding(8)
                .background(RoundedCornerBox(fill: p.surface, edge: p.border, radius: Radii.standard.sm, lineWidth: 1))
                .onTapGesture { tip = nil }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// One fill-in-the-blank card. Key it by card so the next one starts fresh; `onFinished` fires once, as the learner
/// moves past the card.
struct ClozeCardView: View {
    @StateObject private var model: ClozeCardModel
    let look: LessonTextLook
    let onFinished: (ClozeResult) -> Void
    @Environment(\.colorScheme) private var colorScheme

    init(
        card: ClozeCard, courseCode: String, hardcore: Bool, prefs: LocalPrefs, serverPrefs: LessonServerPrefs, look: LessonTextLook,
        onPrefsChange: @escaping (LocalPrefs) -> Void = { _ in }, onEffect: @escaping (FeedbackEvent) -> Void = { _ in },
        onFinished: @escaping (ClozeResult) -> Void
    ) {
        _model = StateObject(wrappedValue: ClozeCardModel(
            card: card, courseCode: courseCode, hardcore: hardcore, prefs: prefs, keyboardMode: serverPrefs.keyboardMode.rawValue,
            onPrefsChange: onPrefsChange, onEffect: onEffect))
        self.look = look
        self.onFinished = onFinished
    }

    /// For previews and snapshots: a card already in a given state.
    init(model: ClozeCardModel, look: LessonTextLook, onFinished: @escaping (ClozeResult) -> Void = { _ in }) {
        _model = StateObject(wrappedValue: model)
        self.look = look
        self.onFinished = onFinished
    }

    var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.standard.s3) {
                    Text(model.status)
                        .font(.subheadline.weight(model.answered ? .bold : .regular))
                        .foregroundColor(Color(argb: model.answered && model.correct ? p.success : p.textMuted))
                    ClozeSentenceView(model: model, look: look, persianFamily: persianFamily)
                    Text(model.card.english)
                        .font(.body)
                        .foregroundColor(Color(argb: p.textMuted))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    field
                }
                .padding(.horizontal, Spacing.standard.s3)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            bottom(p)
        }
    }

    private var persianFamily: String? {
        return Languages.isPersian(model.courseCode) ? model.prefs.fontFa.family : model.prefs.fontJa.family
    }

    @ViewBuilder
    private var field: some View {
        if let keyboard = model.keyboard, model.inAppKeyboard {
            PendingObserver(keyboard: keyboard) { pending in typeIn(pending: pending) }
        } else {
            typeIn(pending: nil)
        }
    }

    // Keyed so a new attempt, and the answered state, get a fresh field.
    private func typeIn(pending: String?) -> some View {
        let reviewed: Reviewed? = model.answered ? Reviewed(text: model.answeredText, correct: model.correct) : nil
        let useInApp: (() -> Void)? = (model.keyboard != nil && !model.inAppKeyboard && !model.answered)
            ? { model.updatePrefs { $0.deviceInputEnabled = false } }
            : nil
        return TypeInExercise(
            exercise: model.exercise, courseCode: model.courseCode, instanceKey: "\(model.card.tag)/\(model.attempt)/\(model.answered)",
            reviewed: reviewed,
            text: Binding<String>(get: { model.typed }, set: { model.setTyped($0) }),
            onDone: { model.check(onFinished: onFinished) },
            inAppKeyboard: model.inAppKeyboard, pending: pending, caret: model.caret,
            onUseInAppKeyboard: useInApp, onCaretTap: { model.tapCaret(to: $0) },
            vowelMarks: model.prefs.showVowelMarks, persianFamily: persianFamily)
            .id("\(model.card.tag)/\(model.attempt)/\(model.answered)")
    }

    @ViewBuilder
    private func bottom(_ p: AppPalette) -> some View {
        if let keyboard = model.keyboard, model.inAppKeyboard {
            PendingObserver(keyboard: keyboard) { pending in
                VStack(spacing: 0) {
                    TypeInKeyboardPanel(
                        courseCode: model.courseCode, prefs: model.prefs, state: keyboard,
                        text: { String(String.UnicodeScalarView(model.typed.unicodeScalars.prefix(model.caret))) },
                        onEdit: { model.applyEdit($0) },
                        onPrefsChange: { next in model.updatePrefs { $0 = next } })
                    actions(p, pending: pending)
                }
            }
        } else {
            actions(p, pending: nil)
        }
    }

    private func actions(_ p: AppPalette, pending: String?) -> some View {
        let enabled = model.canCheck(keyboardPending: pending)
        return VStack(spacing: 0) {
            Button(action: { model.check(onFinished: onFinished) }) {
                Text(model.answered ? "Continue" : "Check")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color(argb: enabled ? p.primaryContrast : p.textMuted))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        RoundedRectangle(cornerRadius: Radii.standard.md, style: .continuous)
                            .fill(Color(argb: enabled ? p.primary : p.border))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .padding(.horizontal, Spacing.standard.s3)
            .padding(.top, Spacing.standard.s3)
            .padding(.bottom, Spacing.standard.s2)
            if model.canGiveUp {
                Button("Show the answer") { model.giveUp() }
                    .font(.subheadline)
                    .foregroundColor(Color(argb: p.textMuted))
                    .frame(minHeight: 44)
            }
        }
    }
}

/// A round of fill-in-the-blank cards. `onExit` leaves it, back to wherever it was started from.
public struct ClozeRoundView: View {
    @ObservedObject private var model: ClozeRoundModel
    private let onExit: () -> Void
    private let onEffect: (FeedbackEvent) -> Void
    @State private var confirmingLeave = false
    @Environment(\.colorScheme) private var colorScheme

    public init(model: ClozeRoundModel, onExit: @escaping () -> Void, onEffect: @escaping (FeedbackEvent) -> Void = { _ in }) {
        self.model = model
        self.onExit = onExit
        self.onEffect = onEffect
    }

    public var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        Group {
            switch model.phase {
            case .loading:
                ProgressView("Finding sentences for your saved words\u{2026}").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                end(p, title: "Couldn't start this round", body: message) {
                    if model.repack {
                        Button("Back", action: onExit).buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                    } else {
                        Button("Try again") { Task { await model.load() } }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                        Button("Back", action: onExit).buttonStyle(.bordered).frame(maxWidth: .infinity)
                    }
                }
            case .empty:
                end(
                    p, title: "Nothing to fill in yet",
                    body: "Fill-in-the-blank cards use sentences from Parsles you've done, with a word you've saved taken out. Save a few words you've met and come back."
                ) {
                    Button("Back", action: onExit).buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                }
            case .playing:
                if let card = model.current {
                    playing(p, card: card)
                } else {
                    results(p)
                }
            }
        }
        .background(Color(argb: p.bg).ignoresSafeArea())
        .task { if model.phase == .loading { await model.load() } }
    }

    private func playing(_ p: AppPalette, card: ClozeCard) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.standard.s3) {
                SessionProgressBar(completed: model.results.count, total: model.deck.count)
                Button(action: { confirmingLeave = true }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(argb: p.danger))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close round")
            }
            .padding(.horizontal, Spacing.standard.s3)
            .padding(.vertical, Spacing.standard.s1)
            ClozeCardView(
                card: card, courseCode: model.courseCode, hardcore: model.hardcore, prefs: model.prefs, serverPrefs: model.serverPrefs,
                look: model.textLook, onPrefsChange: { model.savePrefs($0) }, onEffect: onEffect,
                onFinished: { result in Task { await model.finished(result) } })
                .id("\(card.tag)#\(model.results.count)")
        }
        .confirmationDialog("Leave this round?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive, action: onExit)
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Your answers so far won't be saved, and they won't earn any XP.")
        }
    }

    private func results(_ p: AppPalette) -> some View {
        let summary = summarizeCloze(model.results)
        let correct = model.results.filter { $0.correct }.count
        let lines = clozeResultLines(summary, correct: correct, xp: model.xp ?? .saving)
        return end(p, title: summary.flawless ? "Perfect Delivery!" : "Round complete!", body: "") {
            Text("\(correct) / \(model.results.count) correct").font(.body.weight(.bold)).foregroundColor(Color(argb: p.text))
            Text(lines.breakdown).foregroundColor(Color(argb: p.textMuted)).multilineTextAlignment(.center)
            Text(lines.xp).foregroundColor(Color(argb: model.xp == .failed ? p.danger : p.textMuted)).multilineTextAlignment(.center)
            if model.xp == .failed {
                Button("Try saving again") { Task { await model.retrySubmit() } }.buttonStyle(.bordered).frame(maxWidth: .infinity)
            }
            if model.repack {
                Button("Done", action: onExit)
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity).disabled(model.isSettlingXp)
            } else {
                Button("Another round") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity).disabled(model.isSettlingXp)
                Button("Back to flashcards", action: onExit)
                    .buttonStyle(.bordered).frame(maxWidth: .infinity).disabled(model.isSettlingXp)
            }
        }
    }

    private func end<Actions: View>(_ p: AppPalette, title: String, body: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 16) {
            Text(title).font(.title2.weight(.bold)).foregroundColor(Color(argb: p.text)).accessibilityAddTraits(.isHeader)
            if !body.isEmpty {
                Text(body).foregroundColor(Color(argb: p.text)).multilineTextAlignment(.center)
            }
            actions()
        }
        .padding(Spacing.standard.s4)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
