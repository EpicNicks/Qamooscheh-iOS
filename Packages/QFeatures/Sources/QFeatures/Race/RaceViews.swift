import SwiftUI
import QModel
import QDomain
import QDesign

/// The Repack race (docs/repack-race.md): choose a mode, then a run of fill-in-the-blank cards against the clock, scored by
/// how forgotten each word was. The boards open from the lobby and the results. `onExit` leaves.
public struct RaceScreen: View {
    @ObservedObject private var model: RaceModel
    private let boards: RaceBoardsModel
    private let onExit: () -> Void
    private let onEffect: ((FeedbackEvent) -> Void)?
    @State private var showingBoards = false
    @State private var confirmingLeave = false
    @Environment(\.colorScheme) private var colorScheme

    public init(model: RaceModel, boards: RaceBoardsModel, onExit: @escaping () -> Void, onEffect: ((FeedbackEvent) -> Void)? = nil) {
        self.model = model
        self.boards = boards
        self.onExit = onExit
        self.onEffect = onEffect
    }

    public var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        Group {
            if showingBoards {
                RaceBoardsView(model: boards, onBack: { showingBoards = false })
            } else {
                switch model.stage {
                case .lobby(let mode, let hardcore, let message):
                    RaceLobbyView(
                        mode: mode, hardcore: hardcore, message: message,
                        onMode: { model.selectMode($0) }, onHardcore: { model.setHardcore($0) },
                        onStart: { Task { await model.start() } }, onBoards: { showingBoards = true }, onBack: onExit)
                case .starting:
                    ProgressView("Dealing your cards\u{2026}").frame(maxWidth: .infinity, maxHeight: .infinity)
                case .run(let run):
                    runView(p, run)
                case .done(let mode, _, let response):
                    RaceResultsView(
                        mode: mode, response: response, onAgain: { model.again() }, onBoards: { showingBoards = true },
                        onExit: onExit, onEffect: effect)
                }
            }
        }
        .background(Color(argb: p.bg).ignoresSafeArea())
    }

    /// The device's sounds and haptics as the learner's prefs allow, unless the host supplies its own.
    private var effect: (FeedbackEvent) -> Void {
        return onEffect ?? { FeedbackEffects.shared.play($0, prefs: model.prefs) }
    }

    @ViewBuilder
    private func runView(_ p: AppPalette, _ run: RaceRun) -> some View {
        if run.finishing {
            if let failure = run.sendFailed {
                raceEnd(p, title: "Couldn't save your run", body: failure) {
                    Button("Try again") { Task { await model.retrySend() } }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                    Button("Leave without saving", action: onExit).buttonStyle(.bordered).frame(maxWidth: .infinity)
                }
            } else {
                ProgressView("Saving your run\u{2026}").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if let card = run.current {
            VStack(spacing: 0) {
                RaceHud(run: run, now: { model.now() }, onClose: { confirmingLeave = true })
                ClozeCardView(
                    card: card, courseCode: run.courseCode, hardcore: run.hardcore, prefs: model.prefs, serverPrefs: model.serverPrefs,
                    look: model.textLook, onPrefsChange: { model.savePrefs($0) }, onEffect: effect,
                    onFinished: { result in Task { await model.finished(result) } })
                    .id("\(card.tag)#\(run.results.count)")
            }
            .confirmationDialog(
                model.leavingBanksTheRun ? "Finish this run?" : "Leave this race?",
                isPresented: $confirmingLeave, titleVisibility: .visible
            ) {
                if model.leavingBanksTheRun {
                    Button("Finish") { Task { await model.stop() } }
                } else {
                    Button("Leave", role: .destructive, action: onExit)
                }
                Button("Keep going", role: .cancel) {}
            } message: {
                Text(model.leavingBanksTheRun
                    ? "Your answers so far are saved, with their XP and your personal best."
                    : "Your answers so far won't be saved, and they won't earn any XP.")
            }
        }
    }

    private func raceEnd<Actions: View>(_ p: AppPalette, title: String, body: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 16) {
            Text(title).font(.title2.weight(.bold)).foregroundColor(Color(argb: p.text)).accessibilityAddTraits(.isHeader)
            Text(body).foregroundColor(Color(argb: p.text)).multilineTextAlignment(.center)
            actions()
        }
        .padding(Spacing.standard.s4)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The lobby: the mode, the hardcore switch and what a race needs (Android RaceLobby).
struct RaceLobbyView: View {
    let mode: RaceMode
    let hardcore: Bool
    let message: String?
    let onMode: (RaceMode) -> Void
    let onHardcore: (Bool) -> Void
    let onStart: () -> Void
    let onBoards: () -> Void
    let onBack: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Race").font(.title2.weight(.bold)).foregroundColor(Color(argb: p.text)).accessibilityAddTraits(.isHeader)
                Text("Fill in the blanks against the clock. Words you're about to forget are worth more, up to twice as much.")
                    .foregroundColor(Color(argb: p.textMuted))
                Picker("Mode", selection: Binding<RaceMode>(get: { mode }, set: { onMode($0) })) {
                    Text("Perfect Delivery").tag(RaceMode.perfectDelivery)
                    Text("Endless Practice").tag(RaceMode.endlessPractice)
                }
                .pickerStyle(.segmented)
                Text(raceModeNote(mode)).font(.subheadline).foregroundColor(Color(argb: p.textMuted))
                Button(action: { onHardcore(!hardcore) }) {
                    HStack(spacing: Spacing.standard.s3) {
                        Image(systemName: hardcore ? "checkmark.square.fill" : "square")
                            .font(.system(size: 22))
                            .foregroundColor(Color(argb: hardcore ? p.primary : p.border))
                        Text("Hardcore: no typos forgiven. It has its own board.")
                            .font(.subheadline)
                            .foregroundColor(Color(argb: p.textMuted))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityValue(hardcore ? "On" : "Off")
                Text("Cards come from the saved words you've already reviewed. Finish more units and save their words to unlock more cards. A race needs a connection.")
                    .font(.subheadline)
                    .foregroundColor(Color(argb: p.textMuted))
                if let message = message {
                    Text(message).foregroundColor(Color(argb: p.danger)).accessibilityAddTraits(.updatesFrequently)
                }
                Button("Start", action: onStart).buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                Button("Boards", action: onBoards).buttonStyle(.bordered).frame(maxWidth: .infinity)
                Button("Back", action: onBack).buttonStyle(.bordered).frame(maxWidth: .infinity)
            }
            .padding(Spacing.standard.s4)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }
}

/// What a mode is, in the learner's terms.
func raceModeNote(_ mode: RaceMode) -> String {
    switch mode {
    case .perfectDelivery:
        return "Ranked. A card not right on the first try is a strike, and the third strike ends the run. Most solved wins; a tie goes to the faster run."
    case .endlessPractice:
        return "Unranked. Keep going until you stop or run out of cards; only your personal best is kept."
    }
}

/// The strike meter, the score and the clock, over the card.
struct RaceHud: View {
    let run: RaceRun
    let now: () -> TimeInterval
    let onClose: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        HStack(spacing: Spacing.standard.s3) {
            if run.mode == .perfectDelivery {
                HStack(spacing: Spacing.standard.s1) {
                    ForEach(0..<RaceScoring.maxStrikes, id: \.self) { index in
                        Circle()
                            .fill(Color(argb: index < run.strikes ? p.danger : p.border))
                            .frame(width: 14, height: 14)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(run.strikes) of \(RaceScoring.maxStrikes) strikes")
            }
            Text("\(run.results.count + 1) / \(run.deck.count)")
                .font(.subheadline)
                .foregroundColor(Color(argb: p.textMuted))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(RaceScoring.scoreText(run.score)).font(.body.weight(.bold)).foregroundColor(Color(argb: p.text))
            TimelineView(.periodic(from: Date(), by: 0.1)) { _ in
                Text(RaceScoring.clock(ms: Int(((now() - run.startedAt) * 1000).rounded()), tenths: true))
                    .font(.body.weight(.bold).monospacedDigit())
                    .foregroundColor(Color(argb: p.text))
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color(argb: p.danger))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close race")
        }
        .padding(.horizontal, Spacing.standard.s3)
        .padding(.vertical, Spacing.standard.s1)
    }
}

/// The results: score, solved and strikes, rank or why there is none, personal best and XP.
struct RaceResultsView: View {
    let mode: RaceMode
    let response: FinishRaceResponse
    let onAgain: () -> Void
    let onBoards: () -> Void
    let onExit: () -> Void
    let onEffect: (FeedbackEvent) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        ScrollView {
            VStack(spacing: 12) {
                Text(response.strikes == 0 && response.solved > 0 ? "Perfect Delivery!" : "Race over")
                    .font(.title2.weight(.bold)).foregroundColor(Color(argb: p.text)).accessibilityAddTraits(.isHeader)
                Text("\(RaceScoring.scoreText(response.score)) points")
                    .font(.title3.weight(.bold)).foregroundColor(Color(argb: p.text))
                Text("\(response.solved) solved \u{00B7} \(response.strikes) strike\(response.strikes == 1 ? "" : "s") \u{00B7} \(RaceScoring.clock(ms: response.timeMs))")
                    .foregroundColor(Color(argb: p.textMuted))
                Text(RaceScoring.endReasonText(response.endReason)).foregroundColor(Color(argb: p.textMuted))
                standing(p)
                if let best = response.personalBest {
                    Text("Personal best: \(RaceScoring.scoreText(best.score)) in \(RaceScoring.clock(ms: best.timeMs))")
                        .foregroundColor(Color(argb: p.textMuted))
                }
                Text(response.xp > 0 ? "+\(response.xp) XP" : "No XP this run.")
                    .foregroundColor(Color(argb: p.textMuted)).accessibilityAddTraits(.updatesFrequently)
                Text("XP is the same as a fill-in-the-blank round: 5, 3 or 1 by attempt, and less for a word you've already practised a lot today, so a long run pays little.")
                    .font(.footnote).foregroundColor(Color(argb: p.textMuted))
                Button("Race again", action: onAgain).buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                Button("Boards", action: onBoards).buttonStyle(.bordered).frame(maxWidth: .infinity)
                Button("Done", action: onExit).buttonStyle(.bordered).frame(maxWidth: .infinity)
            }
            .multilineTextAlignment(.center)
            .padding(Spacing.standard.s4)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .onAppear { onEffect(.lessonComplete) }
    }

    @ViewBuilder
    private func standing(_ p: AppPalette) -> some View {
        if response.held {
            Text(RaceScoring.heldMessage(response.heldReason)).foregroundColor(Color(argb: p.textMuted))
        } else if mode == .endlessPractice {
            Text("Endless Practice isn't ranked.").foregroundColor(Color(argb: p.textMuted))
        } else if let rank = response.rank {
            Text("You're #\(rank) on the global board.").font(.body.weight(.bold)).foregroundColor(Color(argb: p.text))
        }
    }
}

/// Perfect Delivery's boards: the scope, the hardcore board, and the rows.
public struct RaceBoardsView: View {
    @ObservedObject private var model: RaceBoardsModel
    private let onBack: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    public init(model: RaceBoardsModel, onBack: @escaping () -> Void) {
        self.model = model
        self.onBack = onBack
    }

    public var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Boards").font(.title2.weight(.bold)).foregroundColor(Color(argb: p.text)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Back", action: onBack).buttonStyle(.bordered)
                }
                Picker("Board", selection: Binding<RaceScope>(get: { model.scope }, set: { next in Task { await model.selectScope(next) } })) {
                    Text("Global").tag(RaceScope.global)
                    Text("Country").tag(RaceScope.country)
                    Text("Week").tag(RaceScope.weekly)
                    Text("Friends").tag(RaceScope.friends)
                }
                .pickerStyle(.segmented)
                Button(action: { Task { await model.setHardcore(!model.hardcore) } }) {
                    HStack(spacing: Spacing.standard.s3) {
                        Image(systemName: model.hardcore ? "checkmark.square.fill" : "square")
                            .font(.system(size: 22))
                            .foregroundColor(Color(argb: model.hardcore ? p.primary : p.border))
                        Text("Hardcore board").font(.subheadline).foregroundColor(Color(argb: p.textMuted))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityValue(model.hardcore ? "On" : "Off")
                Text("Perfect Delivery, on touch devices. The week runs Monday to Monday, UTC.")
                    .font(.footnote).foregroundColor(Color(argb: p.textMuted))
                if model.loading {
                    ProgressView("Loading the board\u{2026}").frame(maxWidth: .infinity)
                } else if let error = model.error {
                    Text(error).foregroundColor(Color(argb: p.danger))
                    Button("Try again") { Task { await model.load() } }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                } else if model.entries.isEmpty {
                    Text(RaceScoring.emptyBoardText(model.scope)).foregroundColor(Color(argb: p.text))
                } else {
                    ForEach(model.entries, id: \.userId) { entry in
                        RaceBoardRow(entry: entry)
                    }
                }
            }
            .padding(Spacing.standard.s3)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .task { await model.load() }
    }
}

struct RaceBoardRow: View {
    let entry: RaceBoardEntry
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        HStack(spacing: Spacing.standard.s3) {
            Text("#\(entry.rank)").foregroundColor(Color(argb: p.textMuted))
            VStack(alignment: .leading, spacing: 2) {
                Text((entry.displayName ?? "Learner") + (entry.isYou ? " (you)" : ""))
                    .fontWeight(entry.isYou ? .bold : .regular)
                    .foregroundColor(Color(argb: p.text))
                    .lineLimit(1)
                if let country = entry.country {
                    Text(country).font(.footnote).foregroundColor(Color(argb: p.textMuted))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                Text(RaceScoring.scoreText(entry.score)).font(.body.weight(.bold)).foregroundColor(Color(argb: p.text))
                Text(RaceScoring.clock(ms: entry.timeMs)).font(.footnote).foregroundColor(Color(argb: p.textMuted))
            }
        }
        .padding(Spacing.standard.s2)
        .background(entry.isYou ? Color(argb: p.border) : Color.clear)
        .accessibilityElement(children: .combine)
    }
}
