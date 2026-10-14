import SwiftUI
import QModel
import QDomain
import QDesign

/// A row in the Profile tab's link card.
public struct ProfileLink: Identifiable {
    public let id: String
    public let title: String
    public let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.id = title
        self.title = title
        self.action = action
    }
}

/// The Profile tab (web ProfilePage plus Android's streak, XP and week of activity).
public struct ProfileView: View {
    @ObservedObject private var model: ProfileModel
    private let links: [ProfileLink]

    public init(model: ProfileModel, links: [ProfileLink]) {
        self.model = model
        self.links = links
    }

    public var body: some View {
        ScrollView {
            ProfileContent(model: model, links: links).padding(16)
        }
        .navigationTitle(profileTitle(model.form))
        .task { await model.load() }
    }
}

func profileTitle(_ form: ProfileForm?) -> String {
    guard let name = form?.displayName, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return "Profile" }
    return name
}

/// The screen body without the scroll view, so snapshots can lay it out at full height.
struct ProfileContent: View {
    @ObservedObject var model: ProfileModel
    let links: [ProfileLink]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        VStack(alignment: .leading, spacing: 16) {
            if let line = studyingLine(courseCode: model.context.courseCode, enrolledCount: model.context.enrolledCount) {
                Text(line).font(.footnote).foregroundColor(Color(argb: p.textMuted))
            }
            StatsCard(model: model, p: p)
            ActivityCard(model: model, p: p)
            ProfileFormCard(model: model, p: p)
            linkCard(p)
            if let error = model.signOutError {
                Text(error).font(.callout).foregroundColor(Color(argb: p.danger))
            }
            Button(role: .destructive, action: { Task { await model.signOut() } }) {
                Text(model.signingOut ? "Signing out\u{2026}" : "Sign out")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.bordered)
            .disabled(model.signingOut)
        }
    }

    private func linkCard(_ p: AppPalette) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
                if index > 0 { Divider().background(Color(argb: p.border)) }
                Button(action: link.action) {
                    HStack {
                        Text(link.title).font(.body).foregroundColor(Color(argb: p.text))
                        Spacer()
                        Text("\u{203A}").font(.title3).foregroundColor(Color(argb: p.textMuted))
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(argb: p.surface))
        .overlay(RoundedRectangle(cornerRadius: Radii.standard.md).stroke(Color(argb: p.border), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radii.standard.md))
    }
}

/// Streak (current and longest), total XP in this course, and today against the daily goal.
private struct StatsCard: View {
    @ObservedObject var model: ProfileModel
    let p: AppPalette

    var body: some View {
        SettingsCard("Progress", p) {
            if let streak = model.streak {
                streakBlock(streak)
            }
            let today = model.today(now: Date())
            let todayXp = xpToday(model.context.activity, today: today)
            HStack(alignment: .top, spacing: 16) {
                stat("Total XP", "\(model.totalXpValue)")
                if let goal = model.context.dailyGoalXp {
                    stat("Today", "\(todayXp) / \(goal) XP")
                } else {
                    stat("Today", "\(todayXp) XP")
                }
            }
            if model.context.courseCode != nil {
                Text("XP counts the course you're studying now.")
                    .font(.footnote).foregroundColor(Color(argb: p.textMuted))
            }
        }
    }

    @ViewBuilder
    private func streakBlock(_ streak: StreakResponse) -> some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 4) {
                Text("\(streak.currentStreakDays)-day streak")
                    .font(.title2.weight(.bold))
                    .foregroundColor(Color(argb: streak.currentStreakDays > 0 && (streak.practicedToday || streak.pausedToday) ? p.streakFire : p.text))
                    .accessibilityLabel(describeStreak(streak, now: context.date))
                Text("Longest: \(formatStreakDays(streak.longestStreakDays))")
                    .font(.footnote).foregroundColor(Color(argb: p.textMuted))
                if streak.pausedToday && !streak.practicedToday {
                    Text("Your streak is paused today.")
                        .font(.footnote).foregroundColor(Color(argb: p.textMuted))
                } else if streak.currentStreakDays > 0 && !streak.practicedToday {
                    Text("\(practiceToKeep(streak, now: context.date)) to keep your streak going.")
                        .font(.footnote).foregroundColor(Color(argb: p.textMuted))
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.footnote).foregroundColor(Color(argb: p.textMuted))
            Text(value).font(.title3.weight(.bold)).foregroundColor(Color(argb: p.text))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The last seven days' XP as bars, today on the right; days that met the goal are green.
private struct ActivityCard: View {
    @ObservedObject var model: ProfileModel
    let p: AppPalette

    var body: some View {
        let today = model.today(now: Date())
        let week = recentActivity(model.context.activity, today: today)
        let goal = model.context.dailyGoalXp
        let peak = max(week.map { $0.xp }.max() ?? 0, goal ?? 0, 1)
        SettingsCard("This week", p) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(week, id: \.day) { day in
                    bar(day, today: today, goal: goal, peak: peak)
                }
            }
            .frame(height: 140)
        }
    }

    private func bar(_ day: DayXp, today: String, goal: Int?, peak: Int) -> some View {
        let met = goal.map { day.xp >= $0 } ?? false
        let color = met ? p.success : (day.xp > 0 ? p.current : p.border)
        let weekday = weekdayShort(day.day, locale: .current)
        let isToday = day.day == today
        return VStack(spacing: 4) {
            GeometryReader { geo in
                VStack {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: Radii.standard.sm)
                        .fill(Color(argb: color))
                        .frame(height: geo.size.height * CGFloat(barFraction(xp: day.xp, peak: peak)))
                }
            }
            Text(String(weekday.prefix(1)))
                .font(.caption2.weight(isToday ? .bold : .regular))
                .foregroundColor(Color(argb: isToday ? p.text : p.textMuted))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(weekday): \(day.xp) XP")
    }
}

/// Web ProfilePage: what friends and leaderboards see.
private struct ProfileFormCard: View {
    @ObservedObject var model: ProfileModel
    let p: AppPalette

    var body: some View {
        SettingsCard("Your profile", p) {
            if let form = model.form {
                Text("This is what friends and leaderboards see. Nothing is shown publicly until you set a display name.")
                    .font(.footnote).foregroundColor(Color(argb: p.textMuted))
                if let error = model.saveError {
                    Text(error).font(.callout).foregroundColor(Color(argb: p.danger))
                }
                field("Display name", text: form.displayName) { v in model.edit { $0.displayName = v } }
                field("Full name (optional, private)", text: form.fullName) { v in model.edit { $0.fullName = v } }
                field("Country (optional, 2 letters, e.g. US)", text: form.country) { v in model.edit { $0.country = v } }
                Button(action: { Task { await model.save() } }) {
                    Text(model.saving ? "Saving\u{2026}" : "Save")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.saving)
                if model.saved {
                    Text("Saved.").font(.callout).foregroundColor(Color(argb: p.success))
                }
            } else if let error = model.loadError {
                Text(error).font(.callout).foregroundColor(Color(argb: p.danger))
                Button("Try again") { Task { await model.loadProfile() } }
                    .buttonStyle(.bordered)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading profile\u{2026}").font(.callout)
                }
            }
        }
    }

    private func field(_ label: String, text: String, onChange: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline).foregroundColor(Color(argb: p.text))
            TextField("", text: Binding(get: { text }, set: onChange))
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 44)
        }
    }
}

/// Fixed-content Profile for snapshot tests. `large` renders at an accessibility Dynamic Type size.
public struct ProfileShowcase: View {
    private let large: Bool
    @StateObject private var model: ProfileModel
    @Environment(\.colorScheme) private var colorScheme

    public init(large: Bool = false) {
        self.large = large
        let streak = StreakResponse(
            currentStreakDays: 12, longestStreakDays: 30, practicedToday: false, pausedToday: false,
            pause: nil, pauseDaysAvailable: 10, timeZone: "America/New_York", dayStartHour: 3,
            today: "2026-10-12", nextDayStartsAt: Date(timeIntervalSince1970: 1_760_000_000))
        let activity = [
            ActivityDay(localDay: "2026-10-12", reviews: 10, xp: 120),
            ActivityDay(localDay: "2026-10-11", reviews: 30, xp: 500),
            ActivityDay(localDay: "2026-10-10", reviews: 22, xp: 310),
            ActivityDay(localDay: "2026-10-08", reviews: 40, xp: 610),
            ActivityDay(localDay: "2026-10-07", reviews: 12, xp: 150),
        ]
        let context = ProfileContext(courseCode: "fa", enrolledCount: 3, activity: activity, dailyGoalXp: 500)
        _model = StateObject(wrappedValue: ProfileModel.preview(
            form: ProfileForm(displayName: "Nick", fullName: "Nicholas", country: "CA"), streak: streak, context: context))
    }

    public var body: some View {
        ProfileContent(model: model, links: ["Settings", "Friends", "Glossary", "Help", "About"].map { ProfileLink($0) {} })
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(argb: (colorScheme == .dark ? AppPalette.dark : AppPalette.light).bg))
            .environment(\.dynamicTypeSize, large ? .accessibility2 : .large)
    }
}
