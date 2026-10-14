import SwiftUI
import QModel
import QData
import QDomain
import QDesign

/// The Settings screen (web SettingsPage, Android SettingsScreen). Study, Input, Audio and Goals
/// edit the course prefs and are sent by Save; the other sections apply on this device at once.
public struct SettingsView: View {
    @ObservedObject private var model: SettingsModel
    private let onOpenHelp: (() -> Void)?
    private let onOpenTutorial: (() -> Void)?
    private let tutorialDone: Bool

    public init(model: SettingsModel, tutorialDone: Bool = false, onOpenHelp: (() -> Void)? = nil, onOpenTutorial: (() -> Void)? = nil) {
        self.model = model
        self.tutorialDone = tutorialDone
        self.onOpenHelp = onOpenHelp
        self.onOpenTutorial = onOpenTutorial
    }

    public var body: some View {
        ScrollView {
            SettingsContent(model: model, tutorialDone: tutorialDone, onOpenHelp: onOpenHelp, onOpenTutorial: onOpenTutorial)
                .padding(16)
        }
        .navigationTitle("Settings")
        .task { await model.load() }
    }
}

/// The screen body without the scroll view, so snapshots can lay it out at full height.
struct SettingsContent: View {
    @ObservedObject var model: SettingsModel
    let tutorialDone: Bool
    let onOpenHelp: (() -> Void)?
    let onOpenTutorial: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        let info = Languages.languageInfo(model.courseCode)
        VStack(alignment: .leading, spacing: 16) {
            Text("Study, Input and Goals apply to the course you're currently studying. Save them below.")
                .font(.footnote)
                .foregroundColor(Color(argb: p.textMuted))
            if model.form != nil {
                CourseSections(model: model, info: info, p: p, onOpenHelp: onOpenHelp)
                saveArea(p)
            } else if let error = model.loadError {
                Text(error).font(.callout).foregroundColor(Color(argb: p.danger))
                Button("Try again") { Task { await model.load() } }
                    .buttonStyle(.bordered)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading settings\u{2026}").font(.callout)
                }
            }
            if let streak = model.streak {
                StreakSection(model: model, streak: streak, p: p)
            }
            Text("The rest are saved on this device as soon as you change them.")
                .font(.footnote)
                .foregroundColor(Color(argb: p.textMuted))
            DeviceSections(model: model, info: info, p: p)
            if let open = onOpenTutorial {
                SettingsCard("Tutorial", p) {
                    Button(tutorialDone ? "Replay the intro tutorial" : "Take the intro tutorial", action: open)
                        .buttonStyle(.bordered)
                }
            }
            if model.canSignOut {
                AccountSection(model: model, p: p)
            }
        }
    }

    @ViewBuilder
    private func saveArea(_ p: AppPalette) -> some View {
        if model.hasUnsyncedEdit {
            Label("Not synced yet", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundColor(Color(argb: p.warning))
        }
        if let notice = model.notice {
            switch notice {
            case .saved:
                Text("Saved.").font(.callout).foregroundColor(Color(argb: p.success))
            case .savedOffline:
                Text("Saved on this device. It will sync when you're back online.")
                    .font(.callout).foregroundColor(Color(argb: p.warning))
            case .rejected(let message), .failed(let message):
                Text(message).font(.callout).foregroundColor(Color(argb: p.danger))
            }
        }
        Button(action: { Task { await model.save() } }) {
            Text(model.saving ? "Saving\u{2026}" : "Save")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.saving)
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let p: AppPalette
    let content: Content

    init(_ title: String, _ p: AppPalette, @ViewBuilder content: () -> Content) {
        self.title = title
        self.p = p
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).foregroundColor(Color(argb: p.text))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(argb: p.surface))
        .overlay(RoundedRectangle(cornerRadius: Radii.standard.md).stroke(Color(argb: p.border), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radii.standard.md))
    }
}

private func fieldLabel(_ text: String, _ p: AppPalette) -> some View {
    Text(text).font(.subheadline.weight(.semibold)).foregroundColor(Color(argb: p.text))
}

private func mutedText(_ text: String, _ p: AppPalette) -> some View {
    Text(text).font(.footnote).foregroundColor(Color(argb: p.textMuted)).fixedSize(horizontal: false, vertical: true)
}

private func switchRow(_ title: String, _ isOn: Bool, _ p: AppPalette, description: String? = nil, set: @escaping (Bool) -> Void) -> some View {
    Toggle(isOn: Binding(get: { isOn }, set: set)) {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body).foregroundColor(Color(argb: p.text))
            if let description = description {
                Text(description).font(.footnote).foregroundColor(Color(argb: p.textMuted))
            }
        }
    }
}

private func segmented<T: Hashable>(_ options: [(T, String)], selection: T, set: @escaping (T) -> Void) -> some View {
    Picker("", selection: Binding(get: { selection }, set: set)) {
        ForEach(0..<options.count, id: \.self) { i in
            Text(options[i].1).tag(options[i].0)
        }
    }
    .pickerStyle(.segmented)
}

/// Account: who is signed in, and Sign out behind a confirmation (Android AccountSection).
private struct AccountSection: View {
    @ObservedObject var model: SettingsModel
    let p: AppPalette

    @State private var confirming = false

    var body: some View {
        SettingsCard("Account", p) {
            if let name = model.accountName, !name.isEmpty {
                mutedText("Signed in as \(name)", p)
            }
            if let error = model.signOutError {
                Text(error).font(.callout).foregroundColor(Color(argb: p.danger))
            }
            Button(action: { confirming = true }) {
                Text(model.signingOut ? "Signing out\u{2026}" : "Sign out")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .foregroundColor(Color(argb: p.danger))
            .disabled(model.signingOut)
            .confirmationDialog("Sign out of Qamooscheh?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { Task { await model.signOut() } }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

/// Study, Input, Audio and Goals: the course prefs that Save sends.
private struct CourseSections: View {
    @ObservedObject var model: SettingsModel
    let info: LanguageInfo?
    let p: AppPalette
    let onOpenHelp: (() -> Void)?

    @State private var customGoal: Bool
    @State private var advancedRetention: Bool
    @State private var goalText: String

    init(model: SettingsModel, info: LanguageInfo?, p: AppPalette, onOpenHelp: (() -> Void)?) {
        _model = ObservedObject(wrappedValue: model)
        self.info = info
        self.p = p
        self.onOpenHelp = onOpenHelp
        let form = model.form
        _customGoal = State(initialValue: form.map { matchDailyGoalPreset($0.dailyGoalXp) == nil } ?? false)
        _advancedRetention = State(initialValue: form.map { matchRetentionPreset($0.desiredRetention) == nil } ?? false)
        _goalText = State(initialValue: form.map { String($0.dailyGoalXp) } ?? "")
    }

    var body: some View {
        if let form = model.form {
            study(form)
            input(form)
            if !model.voices.isEmpty { audio(form) }
            goals(form)
        }
    }

    private func study(_ form: UpdatePrefsRequest) -> some View {
        SettingsCard("Study", p) {
            fieldLabel("Text mode", p)
            segmented([(ScriptMode.native, "Native"), (ScriptMode.both, "Both"), (ScriptMode.romanized, "Latin")], selection: form.scriptMode) { mode in
                model.edit { $0.scriptMode = mode }
            }
            if let info = info {
                mutedText("For example: " + scriptModeSample(mode: form.scriptMode, nativeName: info.nativeName, romanizedName: info.romanizedName), p)
            }
            mutedText("Applies to the text on screen right away, and to which exercises you get next.", p)
            fieldLabel("Register", p)
            segmented([(Register.spoken, "Spoken"), (Register.written, "Written"), (Register.both, "Both")], selection: form.register) { register in
                model.edit { $0.register = register }
            }
            mutedText("Doesn't change lesson content yet. No course varies its exercises or accepted answers by register.", p)
        }
    }

    private func input(_ form: UpdatePrefsRequest) -> some View {
        SettingsCard("Input", p) {
            fieldLabel("Keyboard", p)
            segmented([(KeyboardMode.contextual, "Joined letters"), (KeyboardMode.isolated, "Separated letters")], selection: form.keyboardMode) { mode in
                model.edit { $0.keyboardMode = mode }
            }
            if info?.language == "fa" {
                Text(keyboardSample(mode: form.keyboardMode))
                    .font(.title2)
                    .foregroundColor(Color(argb: p.text))
                    .environment(\.layoutDirection, .rightToLeft)
            }
            switchRow("Autoplay audio", form.autoplayAudio, p) { on in model.edit { $0.autoplayAudio = on } }
        }
    }

    private func audio(_ form: UpdatePrefsRequest) -> some View {
        let defaultId = model.voices[0].id
        let selected = form.preferredVoice ?? defaultId
        return SettingsCard("Audio", p) {
            fieldLabel("Voice", p)
            VStack(spacing: 8) {
                ForEach(0..<model.voices.count, id: \.self) { i in
                    voiceRow(model.voices[i], selected: model.voices[i].id == selected, defaultId: defaultId)
                }
            }
            if let notice = model.previewNotice {
                Text(notice).font(.footnote).foregroundColor(Color(argb: p.warning))
            }
            if model.voices.count > 1 {
                switchRow("Shuffle voices", model.local.shuffleVoices, p) { on in model.updateLocal { $0.shuffleVoices = on } }
            }
        }
    }

    private func voiceRow(_ voice: SettingsVoice, selected: Bool, defaultId: String) -> some View {
        HStack(spacing: 8) {
            Button(action: { model.edit { $0.preferredVoice = voice.id == defaultId ? nil : voice.id } }) {
                HStack {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .foregroundColor(Color(argb: selected ? p.current : p.textMuted))
                    Text(voice.label).font(.body).foregroundColor(Color(argb: p.text))
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            if voice.canPreview {
                Button(action: { model.previewVoice(voice) }) {
                    Image(systemName: "play.circle")
                        .font(.title3)
                        .foregroundColor(Color(argb: p.current))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(voice.label)")
            }
        }
    }

    private func goals(_ form: UpdatePrefsRequest) -> some View {
        let matchedGoal = matchDailyGoalPreset(form.dailyGoalXp)
        let matchedRetention = matchRetentionPreset(form.desiredRetention)
        return SettingsCard("Goals", p) {
            fieldLabel("Daily goal", p)
            VStack(spacing: 8) {
                ForEach(0..<dailyGoalPresets.count, id: \.self) { i in
                    let preset = dailyGoalPresets[i]
                    presetTile(preset.label, "\(preset.xp) XP", selected: !customGoal && matchedGoal?.xp == preset.xp) {
                        customGoal = false
                        model.edit { $0.dailyGoalXp = preset.xp }
                    }
                }
            }
            Button(customGoal ? "Hide custom" : "Custom XP amount") { customGoal.toggle() }
            if customGoal {
                TextField("Daily XP goal", text: Binding(get: { goalText }, set: { raw in
                    goalText = sanitizedGoalInput(raw)
                    if let xp = Int(goalText) { model.edit { $0.dailyGoalXp = xp } }
                }))
                .numberEntry()
                .onReceive(model.$form) { latest in
                    // Follow form resets (server pull) without fighting live typing.
                    if let xp = latest?.dailyGoalXp, !goalText.isEmpty, Int(goalText) != xp {
                        goalText = String(xp)
                    }
                }
            }
            switchRow("Celebrate when I hit my daily goal", model.local.goalCelebrationEnabled, p, description: "Saved on this device.") { on in
                model.updateLocal { $0.goalCelebrationEnabled = on }
            }
            switchRow("Animate my streak: smouldering while it waits on today's lesson, flames once it's done", model.local.smoulderingStreak, p, description: "Saved on this device.") { on in
                model.updateLocal { $0.smoulderingStreak = on }
            }
            fieldLabel("Review intensity", p)
            VStack(spacing: 8) {
                ForEach(0..<retentionPresets.count, id: \.self) { i in
                    let preset = retentionPresets[i]
                    presetTile(preset.label, preset.hint, selected: !advancedRetention && matchedRetention == preset) {
                        advancedRetention = false
                        model.edit { $0.desiredRetention = preset.value }
                    }
                }
            }
            Button(advancedRetention ? "Hide advanced" : "Advanced (exact value)") { advancedRetention.toggle() }
            if advancedRetention {
                mutedText("Target retention (\(Int((form.desiredRetention * 100).rounded()))%)", p)
                Slider(value: Binding(get: { form.desiredRetention }, set: { v in
                    model.edit { $0.desiredRetention = snapRetention(v) }
                }), in: 0.51...0.99, step: 0.01)
            }
            if let open = onOpenHelp {
                Button("What does this change?", action: open)
            }
        }
    }

    private func presetTile(_ label: String, _ note: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(label).font(.subheadline.weight(.semibold)).foregroundColor(Color(argb: p.text))
                Text(note).font(.footnote).foregroundColor(Color(argb: p.textMuted))
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .overlay(
                RoundedRectangle(cornerRadius: Radii.standard.md)
                    .stroke(Color(argb: selected ? p.current : p.border), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Device-only sections: keyboard, hints, text size, feedback, notifications.
private struct DeviceSections: View {
    @ObservedObject var model: SettingsModel
    let info: LanguageInfo?
    let p: AppPalette

    var body: some View {
        let local = model.local
        let language = info?.language
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard("Keyboard", p) {
                if language == "fa" {
                    fieldLabel("Persian input", p)
                    segmented([(PersianInputMethod.layout, "Layout"), (PersianInputMethod.phonetic, "Phonetic")], selection: local.persianInputMethod) { m in
                        model.updateLocal { $0.persianInputMethod = m }
                    }
                }
                if language == "ja" {
                    fieldLabel("Japanese input", p)
                    segmented([(JapaneseInputMethod.romaji, "Romaji"), (JapaneseInputMethod.kana, "Kana")], selection: local.japaneseInputMethod) { m in
                        model.updateLocal { $0.japaneseInputMethod = m }
                    }
                }
                switchRow("Use device keyboard", local.deviceInputEnabled, p, description: "Type answers with your phone's own keyboard instead of the in-app one.") { on in
                    model.updateLocal { $0.deviceInputEnabled = on }
                }
                switchRow("Read word-bank tiles aloud", local.speakWordBankTiles, p, description: "Hear each word as you pick it into your answer.") { on in
                    model.updateLocal { $0.speakWordBankTiles = on }
                }
                switchRow("Read the answer aloud after I answer", local.speakAnswers, p) { on in
                    model.updateLocal { $0.speakAnswers = on }
                }
            }
            hints(local, language)
            if let info = info { textSize(local, info) }
            SettingsCard("Sound and vibration", p) {
                switchRow("Haptic feedback", local.hapticsEnabled, p) { on in model.updateLocal { $0.hapticsEnabled = on } }
                switchRow("Sound effects", local.soundEffectsEnabled, p) { on in model.updateLocal { $0.soundEffectsEnabled = on } }
            }
            notifications()
        }
    }

    private func hints(_ local: LocalPrefs, _ language: String?) -> some View {
        let name = info?.displayName ?? "course language"
        return SettingsCard("Lesson hints", p) {
            if language == "fa" {
                fieldLabel("Text alignment", p)
                segmented([(NativeTextAlign.start, "Start"), (NativeTextAlign.center, "Center")], selection: local.nativeTextAlign) { a in
                    model.updateLocal { $0.nativeTextAlign = a }
                }
            }
            if language == "ja" {
                switchRow("Furigana over kanji", local.showFurigana, p) { on in model.updateLocal { $0.showFurigana = on } }
            }
            switchRow("Tap a word for its romanization", local.showRomanizationHints, p) { on in model.updateLocal { $0.showRomanizationHints = on } }
            switchRow("Tap a word for its translation", local.showTranslationHints, p) { on in model.updateLocal { $0.showTranslationHints = on } }
            switchRow("Tap an English word for the \(name)", local.showNativeHints, p) { on in model.updateLocal { $0.showNativeHints = on } }
            if language == "fa" {
                switchRow("Show vowel marks and the ezafe", local.showVowelMarks, p) { on in model.updateLocal { $0.showVowelMarks = on } }
                switchRow("Show each sentence romanized above it", local.showSentenceRomanization, p) { on in model.updateLocal { $0.showSentenceRomanization = on } }
            }
        }
    }

    private func textSize(_ local: LocalPrefs, _ info: LanguageInfo) -> some View {
        let isFa = info.language == "fa"
        let pref = isFa ? local.fontFa : local.fontJa
        let write: (inout LocalPrefs, ScriptFontPref) -> Void = { prefs, next in
            if isFa { prefs.fontFa = next } else { prefs.fontJa = next }
        }
        return SettingsCard(isFa ? "Appearance" : "Text size", p) {
            if isFa {
                fieldLabel("Persian flag", p)
                segmented(persianFlagChoices.map { ($0.family ?? "", $0.label) }, selection: local.persianFlag) { flag in
                    model.updateLocal { $0.persianFlag = flag }
                }
                fieldLabel("Persian font", p)
                Picker("Persian font", selection: Binding(get: { pref.family ?? "" }, set: { family in
                    var next = pref
                    next.family = family.isEmpty ? nil : family
                    model.updateLocal { write(&$0, next) }
                })) {
                    ForEach(0..<persianFontChoices.count, id: \.self) { i in
                        Text(persianFontChoices[i].label).tag(persianFontChoices[i].family ?? "")
                    }
                }
                .pickerStyle(.menu)
            }
            fieldLabel("\(info.displayName) text size (\(pref.sizePct)%)", p)
            Text(isFa ? "\u{0633}\u{0644}\u{0627}\u{0645}\u{060C} \u{062E}\u{0627}\u{0646}\u{0647}\u{060C} \u{0645}\u{0639}\u{0644}\u{0645}" : info.nativeName)
                .font(.system(size: 22 * CGFloat(pref.sizePct) / 100))
                .foregroundColor(Color(argb: p.text))
                .environment(\.layoutDirection, isFa ? .rightToLeft : .leftToRight)
            Slider(value: Binding(get: { Double(pref.sizePct) }, set: { v in
                var next = pref
                next.sizePct = snapFontPercent(v)
                model.updateLocal { write(&$0, next) }
            }), in: 75...150, step: 5)
        }
    }

    private func notifications() -> some View {
        let r = model.reminders
        return SettingsCard("Notifications", p) {
            switchRow("Daily reminder", r.enabled, p, description: "A nudge at your chosen time on the days you pick.") { on in
                Task { await model.setRemindersEnabled(on) }
            }
            if r.enabled {
                DatePicker("Time", selection: Binding(get: { reminderDate(r) }, set: { date in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                    model.updateReminders {
                        $0.hour = parts.hour ?? 19
                        $0.minute = parts.minute ?? 0
                    }
                }), displayedComponents: .hourAndMinute)
                HStack(spacing: 6) {
                    ForEach(0..<reminderDayLabels.count, id: \.self) { i in
                        let entry = reminderDayLabels[i]
                        let on = r.days.contains(entry.day)
                        Button(action: {
                            model.updateReminders {
                                if on { $0.days.remove(entry.day) } else { $0.days.insert(entry.day) }
                            }
                        }) {
                            Text(entry.label)
                                .font(.caption.weight(.semibold))
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity)
                                .foregroundColor(Color(argb: on ? p.primaryContrast : p.text))
                                .background(Color(argb: on ? p.current : p.bg))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                switchRow("Skip once you've practiced today", r.smartSuppression, p) { on in model.updateReminders { $0.smartSuppression = on } }
                switchRow("Streak reminder", r.streakNudge, p, description: "A late-evening nudge if you haven't practiced yet today.") { on in
                    model.updateReminders { $0.streakNudge = on }
                }
            }
        }
    }

    private func reminderDate(_ r: ReminderSettings) -> Date {
        return Calendar.current.date(bySettingHour: r.hour, minute: r.minute, second: 0, of: Date()) ?? Date()
    }
}

/// Web StreakSection: when the streak day rolls over, and pausing it. Each action saves on its own.
private struct StreakSection: View {
    @ObservedObject var model: SettingsModel
    let streak: StreakResponse
    let p: AppPalette

    @State private var picked: Date?
    @State private var length = 7

    var body: some View {
        let today = streakToday(streak, now: Date())
        SettingsCard("Streak", p) {
            fieldLabel("Day resets at", p)
            Text("\(formatDayStart(streak, locale: .current)) (\(formatZone(streak.timeZone)))")
                .font(.body).foregroundColor(Color(argb: p.text))
            mutedText("Practice before then to count today. Your time zone follows this device, so the reset moves with you when you travel.", p)
            if let pause = streak.pause {
                scheduled(pause)
            } else {
                form(today)
            }
            if let error = model.pauseError {
                Text(error).font(.callout).foregroundColor(Color(argb: p.danger))
            }
        }
    }

    private func scheduled(_ pause: StreakPauseResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(pause.started ? "Streak paused" : "Pause scheduled", p)
            Text(formatStreakDayRange(pause.startDay, pause.endDay, locale: .current))
                .font(.body).foregroundColor(Color(argb: p.text))
            mutedText("Paused days don't break your streak or add to it. Practicing on a paused day still counts." + (pause.started ? " Ending the pause early still covers today." : ""), p)
            Button(model.pauseBusy ? "Saving\u{2026}" : (pause.started ? "End pause" : "Cancel pause")) {
                Task { await model.cancelStreakPause() }
            }
            .buttonStyle(.bordered)
            .disabled(model.pauseBusy)
        }
    }

    @ViewBuilder
    private func form(_ today: String) -> some View {
        let maxLength = maxPauseLength(streak)
        if maxLength < 1 {
            fieldLabel("Pause your streak", p)
            mutedText("You've used all your pause days for this year. They come back 365 days after each pause.", p)
        } else {
            let first = streakDayDate(today) ?? Date()
            let lastDay = addDays(today, maxPauseLeadDays)
            let last = streakDayDate(lastDay) ?? first
            let start = min(max(picked ?? first, first), last)
            let days = min(max(length, 1), maxLength)
            let startDay = streakDayString(start)
            let endDay = addDays(startDay, days - 1)
            fieldLabel("Pause starts", p)
            DatePicker("Pause starts", selection: Binding(get: { start }, set: { picked = $0 }), in: first...last, displayedComponents: .date)
                .labelsHidden()
                .environment(\.timeZone, TimeZone(identifier: "UTC") ?? .current)
            fieldLabel("For \(formatStreakDays(days))", p)
            if maxLength > 1 {
                Slider(value: Binding(get: { Double(days) }, set: { length = Int($0.rounded()) }), in: 1...Double(maxLength), step: 1)
            }
            mutedText("Going on vacation or taking a break? Paused days won't break your streak. Through \(formatStreakDay(endDay, locale: .current)). \(formatStreakDays(streak.pauseDaysAvailable)) of pause left this year.", p)
            Button(model.pauseBusy ? "Saving\u{2026}" : "Pause streak") {
                Task { await model.pauseStreak(startDay: startDay, days: days) }
            }
            .buttonStyle(.bordered)
            .disabled(model.pauseBusy)
        }
    }
}

/// Fixed-content Settings for snapshot tests. `large` renders at an accessibility Dynamic Type size.
public struct SettingsShowcase: View {
    private let course: String
    private let large: Bool
    @StateObject private var model: SettingsModel
    @Environment(\.colorScheme) private var colorScheme

    public init(course: String, large: Bool = false) {
        self.course = course
        self.large = large
        var local = LocalPrefs()
        local.fontFa = ScriptFontPref(family: "Vazirmatn", sizePct: 120)
        var reminders = ReminderSettings()
        reminders.enabled = true
        reminders.days = [1, 2, 3, 4, 5]
        let streak = StreakResponse(
            currentStreakDays: 12, longestStreakDays: 30, practicedToday: false, pausedToday: false,
            pause: nil, pauseDaysAvailable: 10, timeZone: "America/New_York", dayStartHour: 3,
            today: "2026-10-12", nextDayStartsAt: Date(timeIntervalSince1970: 1_760_000_000))
        let form = UpdatePrefsRequest(
            scriptMode: .both, register: .spoken, autoplayAudio: true, keyboardMode: .contextual,
            desiredRetention: 0.92, dailyGoalXp: 750, preferredVoice: nil)
        let voices = [
            SettingsVoice(id: "v1", label: "Voice one", sampleText: "Salam", sampleLanguage: "fa-IR"),
            SettingsVoice(id: "v2", label: "Voice two", sampleText: "Salam", sampleLanguage: "fa-IR"),
        ]
        _model = StateObject(wrappedValue: SettingsModel.preview(
            form: form, local: local, reminders: reminders, streak: streak, courseCode: course, voices: voices,
            accountName: "learner@example.com", canSignOut: true))
    }

    public var body: some View {
        SettingsContent(model: model, tutorialDone: false, onOpenHelp: {}, onOpenTutorial: {})
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(argb: (colorScheme == .dark ? AppPalette.dark : AppPalette.light).bg))
            .environment(\.dynamicTypeSize, large ? .accessibility2 : .large)
    }
}

private extension View {
    /// Number pad on iOS; the packages also build on macOS, which has neither modifier.
    @ViewBuilder
    func numberEntry() -> some View {
        #if os(iOS)
        self.keyboardType(.numberPad).textFieldStyle(.roundedBorder)
        #else
        self
        #endif
    }
}
