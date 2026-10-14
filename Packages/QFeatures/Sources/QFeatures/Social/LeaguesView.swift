import SwiftUI
import QModel
import QDesign

/// The Leagues screen (web LeaguesPage, Android LeaguesScreen), a top-level tab: the tier, this
/// period's standings with the learner's own row outlined, the promotion and demotion zones, and
/// a countdown to the period's end.
public struct LeaguesView: View {
    @ObservedObject private var model: LeaguesModel

    public init(model: LeaguesModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            LeaguesContent(model: model, now: nil).padding(16)
        }
        .navigationTitle("Leagues")
        // Points move whenever anyone practices, so refetch on each appearance.
        .task { await model.refresh() }
    }
}

/// The body without the scroll view. `now` pins the clock for snapshots; nil ticks live.
struct LeaguesContent: View {
    @ObservedObject var model: LeaguesModel
    let now: Date?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        VStack(alignment: .leading, spacing: 8) {
            switch model.state {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading league\u{2026}").font(.callout)
                }
            case .noLeague:
                noLeague(p)
            case .failed(let message):
                Text(message).font(.callout).foregroundColor(Color(argb: p.danger))
                Button("Try again") { Task { await model.refresh() } }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
            case .ready(let league):
                standings(league, p)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func standings(_ league: LeagueUi, _ p: AppPalette) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "trophy.fill").font(.title).foregroundColor(Color(argb: p.placement))
                .accessibilityHidden(true)
            Text("Tier \(league.tier)").font(.title.weight(.bold)).foregroundColor(Color(argb: p.text))
                .accessibilityAddTraits(.isHeader)
        }
        VStack(alignment: .leading, spacing: 2) {
            if let fixed = now {
                countdown(league.endsAt, fixed, p)
            } else {
                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    countdown(league.endsAt, context.date, p)
                }
            }
            Text("Ends \(league.endsAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.footnote).foregroundColor(Color(argb: p.textMuted))
        }
        .padding(.bottom, 12)
        ForEach(Array(league.rows.enumerated()), id: \.element.userId) { index, row in
            let previous: LeagueOutcome? = index > 0 ? league.rows[index - 1].outcome : nil
            VStack(spacing: 8) {
                // Duolingo's dividers: one under the last promoted rank, one over the first demoted.
                if previous == .promoted && row.outcome != .promoted {
                    ZoneDivider(label: "Promotion zone", mark: "\u{25B2}", color: Color(argb: p.success))
                }
                if let before = previous, before != .demoted, row.outcome == .demoted {
                    ZoneDivider(label: "Demotion zone", mark: "\u{25BC}", color: Color(argb: p.danger))
                }
                StandingRowView(row: row, p: p)
            }
        }
    }

    private func countdown(_ endsAt: Date, _ at: Date, _ p: AppPalette) -> some View {
        Text(formatRemaining(seconds: Int(endsAt.timeIntervalSince(at))))
            .font(.headline).foregroundColor(Color(argb: p.text))
    }

    private func noLeague(_ p: AppPalette) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "trophy").font(.system(size: 56)).foregroundColor(Color(argb: p.locked))
                .accessibilityHidden(true)
            Text("No active league right now.").font(.title3.weight(.semibold))
                .foregroundColor(Color(argb: p.text)).multilineTextAlignment(.center)
            Text("Earn some XP and you'll be placed in a league when the next period starts.")
                .font(.callout).foregroundColor(Color(argb: p.textMuted)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }
}

private struct ZoneDivider: View {
    let label: String
    let mark: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            color.frame(height: 2)
            Text("\(mark) \(label)").font(.caption.weight(.bold)).foregroundColor(color)
            color.frame(height: 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

/// Web `.row` / `.me`: a rank column, the name, then the XP.
private struct StandingRowView: View {
    let row: StandingRow
    let p: AppPalette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radii.standard.sm)
        let name = (row.displayName ?? leagueUnnamed) + (row.isMe ? " (you)" : "")
        HStack(spacing: 12) {
            Text("\(row.rank)").font(.body.weight(.bold)).foregroundColor(rankColor)
                .frame(minWidth: 32, alignment: .leading)
            Text(name).font(.body.weight(row.isMe ? .bold : .regular))
                .foregroundColor(Color(argb: p.text))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(row.points) XP").font(.body.weight(.bold)).foregroundColor(Color(argb: p.primary)).lineLimit(1)
        }
        .padding(12)
        .background(Color(argb: p.surface))
        .clipShape(shape)
        .overlay(shape.stroke(row.isMe ? Color(argb: p.primary) : Color(argb: p.border), lineWidth: row.isMe ? 2 : 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rank \(row.rank), \(name), \(row.points) XP")
    }

    private var rankColor: Color {
        switch row.outcome {
        case .promoted: return Color(argb: p.success)
        case .demoted: return Color(argb: p.danger)
        case .held: return Color(argb: p.textMuted)
        }
    }
}

/// Fixed-content Leagues for snapshot tests. `large` renders at an accessibility Dynamic Type size.
public struct LeaguesShowcase: View {
    private let large: Bool
    private let now: Date
    @StateObject private var model: LeaguesModel
    @Environment(\.colorScheme) private var colorScheme

    public init(large: Bool = false) {
        self.large = large
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        self.now = now
        let names: [String?] = ["Maryam", "Dariush", nil, "Ali Rezaei", "Sara", "Kaveh", "Niloufar",
                                "Babak", "Leila", "Omid", "Parisa", "Reza", "Shirin"]
        var rows: [LeagueStandingResponse] = []
        for (index, name) in names.enumerated() {
            rows.append(LeagueStandingResponse(userId: "u\(index)", displayName: name, points: 480 - index * 31))
        }
        let response = CurrentLeagueResponse(tier: 2, periodEndsAt: now.addingTimeInterval(2 * 86_400 + 5 * 3_600), standings: rows)
        _model = StateObject(wrappedValue: LeaguesModel.preview(.ready(makeLeagueUi(response, viewerId: "u3"))))
    }

    public var body: some View {
        LeaguesContent(model: model, now: now)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(argb: (colorScheme == .dark ? AppPalette.dark : AppPalette.light).bg))
            .environment(\.dynamicTypeSize, large ? .accessibility2 : .large)
    }
}
