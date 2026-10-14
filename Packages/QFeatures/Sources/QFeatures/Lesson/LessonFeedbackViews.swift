import SwiftUI
import QDesign
import QDomain
import QModel

private func lessonPalette(_ scheme: ColorScheme) -> AppPalette {
    return scheme == .dark ? AppPalette.dark : AppPalette.light
}

/// The lesson's top progress bar (Android ProgressBar): 16 pt track, primary fill.
public struct SessionProgressBar: View {
    private let completed: Int
    private let total: Int
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(completed: Int, total: Int) {
        self.completed = completed
        self.total = total
    }

    public var body: some View {
        let p = lessonPalette(colorScheme)
        let fraction = sessionProgressFraction(completed: completed, total: total)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(argb: p.border))
                Capsule()
                    .fill(Color(argb: p.primary))
                    .frame(width: max(0, proxy.size.width * CGFloat(fraction)))
            }
        }
        .frame(height: 16)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lesson progress")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}

/// The "+10 XP" pop on a correct answer: rises and settles. `animated` false draws the settled state.
public struct XpBurst: View {
    private let amount: Int
    private let animated: Bool
    @State private var risen = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(amount: Int, animated: Bool = true) {
        self.amount = amount
        self.animated = animated
    }

    public var body: some View {
        let settled = risen || !animated || reduceMotion
        if amount > 0 {
            Text("+\(amount) XP")
                .font(.system(size: 16, weight: .heavy))
                .foregroundColor(Color(argb: lessonPalette(colorScheme).primary))
                .offset(y: settled ? -8 : 0)
                .opacity(settled ? 1 : 0.2)
                .onAppear {
                    if animated && !reduceMotion {
                        withAnimation(.easeOut(duration: 0.6)) { risen = true }
                    }
                }
                .accessibilityHidden(true)
        }
    }
}

/// What the feedback panel shows about the last answer.
public struct FeedbackReview {
    public var feedback: AnswerFeedback
    public var instance: ExerciseInstance
    public var submittedText: String
    /// Cosmetic XP for the pop (0 = none).
    public var xp: Int

    public init(feedback: AnswerFeedback, instance: ExerciseInstance, submittedText: String, xp: Int) {
        self.feedback = feedback
        self.instance = instance
        self.submittedText = submittedText
        self.xp = xp
    }
}

/// The verdict panel under an exercise (Android FeedbackPanel): "Correct!" with XP, or "Not quite."
/// with the answer behind a tap, or a neutral "checked when you sync" when the device couldn't grade.
public struct AnswerFeedbackView: View {
    private let review: FeedbackReview
    private let onContinue: () -> Void
    private let onPlayAnswer: (() -> Void)?
    private let makeReportModel: (() -> ReportIssueModel)?
    private let startRevealed: Bool
    private let animated: Bool

    @State private var revealed = false
    @State private var reporting = false
    @State private var showOthers = false
    @Environment(\.colorScheme) private var colorScheme

    public init(
        review: FeedbackReview,
        onContinue: @escaping () -> Void,
        onPlayAnswer: (() -> Void)? = nil,
        makeReportModel: (() -> ReportIssueModel)? = nil,
        startRevealed: Bool = false,
        animated: Bool = true
    ) {
        self.review = review
        self.onContinue = onContinue
        self.onPlayAnswer = onPlayAnswer
        self.makeReportModel = makeReportModel
        self.startRevealed = startRevealed
        self.animated = animated
    }

    public var body: some View {
        let p = lessonPalette(colorScheme)
        let kind = feedbackKind(review.feedback.verdict)
        let fill: UInt32 = kind == .pending ? p.surface : (kind == .correct ? p.successBg : p.dangerBg)
        let accent: UInt32 = kind == .pending ? p.textMuted : (kind == .correct ? p.success : p.danger)
        let lines = revealedAnswerLines(review.instance.exercise, submittedText: review.submittedText)
        let others = Array(lines.dropFirst())
        VStack(alignment: .leading, spacing: Spacing.standard.s2) {
            switch kind {
            case .pending:
                Text("Answer saved \u{2014} it'll be checked when you sync.")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(argb: p.text))
            case .correct:
                HStack(spacing: Spacing.standard.s2) {
                    Text("Correct!").font(.system(size: 20, weight: .heavy)).foregroundColor(Color(argb: accent))
                    XpBurst(amount: review.xp, animated: animated)
                    Spacer()
                    playButton(accent)
                }
            case .incorrect:
                HStack {
                    Text("Not quite.").font(.system(size: 20, weight: .heavy)).foregroundColor(Color(argb: accent))
                    Spacer()
                    if makeReportModel != nil && !review.instance.exercise.tags.isEmpty {
                        Button("Report") { reporting = true }
                            .foregroundColor(Color(argb: p.textMuted))
                    }
                    playButton(accent)
                }
            }
            if let note = review.feedback.note {
                Text(note).font(.system(size: 15)).foregroundColor(Color(argb: p.text))
            }
            if kind == .incorrect {
                if revealed || startRevealed {
                    if let first = lines.first {
                        AnnotatedText(first, scriptMode: review.instance.exercise.scriptMode, tags: review.instance.exercise.tags, fontSize: 20)
                    }
                    if !others.isEmpty {
                        Button("\u{25B8} " + alsoAcceptedTitle(count: others.count)) { showOthers = true }
                            .foregroundColor(Color(argb: p.textMuted))
                    }
                    if showsYourAnswer(review.instance.renderType) {
                        Text(yourAnswerLine(review.submittedText)).foregroundColor(Color(argb: p.text))
                    }
                } else {
                    Button("Reveal answer?") { revealed = true }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(argb: accent))
                }
            }
            Button(action: onContinue) {
                Text("Continue")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(argb: p.primaryContrast))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: Radii.standard.md).fill(Color(argb: kind == .incorrect ? p.danger : p.primary)))
            }
        }
        .padding(.horizontal, Spacing.standard.s3)
        .padding(.vertical, Spacing.standard.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(argb: fill))
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $showOthers) {
            AlsoAcceptedSheet(lines: others, exercise: review.instance.exercise)
        }
        .sheet(isPresented: $reporting) {
            if let make = makeReportModel {
                ReportIssueSheet(model: make(), onClose: { reporting = false })
            }
        }
    }

    @ViewBuilder
    private func playButton(_ accent: UInt32) -> some View {
        if let play = onPlayAnswer {
            Button(action: play) {
                Image(systemName: "speaker.wave.2.fill").foregroundColor(Color(argb: accent))
            }
            .accessibilityLabel("Play the answer")
        }
    }
}

private struct AlsoAcceptedSheet: View {
    let lines: [String]
    let exercise: ExerciseArtifact
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let p = lessonPalette(colorScheme)
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.standard.s2) {
                    ForEach(lines, id: \.self) { line in
                        AnnotatedText(line, scriptMode: exercise.scriptMode, tags: exercise.tags, fontSize: 18)
                            .padding(Spacing.standard.s3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: Radii.standard.md).fill(Color(argb: p.surface)))
                            .overlay(RoundedRectangle(cornerRadius: Radii.standard.md).stroke(Color(argb: p.border)))
                    }
                }
                .padding(Spacing.standard.s3)
            }
            .navigationTitle(alsoAcceptedTitle(count: lines.count))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
        }
    }
}

/// Flag an exercise as wrong or confusing (Android ReportDialog), as a sheet.
public struct ReportIssueSheet: View {
    @ObservedObject private var model: ReportIssueModel
    private let onClose: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    public init(model: ReportIssueModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
    }

    public var body: some View {
        let p = lessonPalette(colorScheme)
        VStack(alignment: .leading, spacing: Spacing.standard.s2) {
            Text("Report an issue with this exercise")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Color(argb: p.text))
            ForEach(exerciseReportReasons, id: \.value) { option in
                let checked = model.reasons.contains(option.value)
                Button(action: { model.toggle(option.value) }) {
                    HStack(spacing: Spacing.standard.s3) {
                        Image(systemName: checked ? "checkmark.square.fill" : "square")
                            .foregroundColor(Color(argb: checked ? p.primary : p.textMuted))
                        Text(option.label).foregroundColor(Color(argb: p.text))
                        Spacer()
                    }
                }
                .accessibilityAddTraits(checked ? .isSelected : [])
            }
            if model.reasons.contains(.other) {
                TextField("Tell us more\u{2026}", text: $model.details, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)
            }
            if let message = model.statusMessage {
                Text(message).foregroundColor(Color(argb: p.text))
            }
            HStack {
                Button("Close", action: onClose)
                Spacer()
                Button(action: { Task { await model.send() } }) {
                    Text(model.status == .sending ? "Sending\u{2026}" : "Submit report")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(argb: p.primaryContrast))
                        .padding(.horizontal, Spacing.standard.s3)
                        .frame(minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: Radii.standard.md).fill(Color(argb: model.canSend ? p.primary : p.locked)))
                }
                .disabled(!model.canSend)
            }
        }
        .padding(Spacing.standard.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(argb: p.bg))
        .presentationDetents([.medium, .large])
    }
}

private struct PercentLabel: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View {
        Text("\(Int(value.rounded()))%")
    }
}

/// "4 / 5 correct" and the score bar with its pass mark, counting up (Android LessonScore).
public struct LessonScoreBar: View {
    private let correct: Int
    private let total: Int
    private let score: Double
    private let passMark: Double?
    private let animated: Bool
    @State private var shown: Double = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(correct: Int, total: Int, score: Double, passMark: Double?, animated: Bool = true) {
        self.correct = correct
        self.total = total
        self.score = score
        self.passMark = passMark
        self.animated = animated
    }

    public var body: some View {
        let p = lessonPalette(colorScheme)
        let target = Double(scorePercent(score))
        let current = (animated && !reduceMotion) ? shown : target
        VStack(alignment: .leading, spacing: Spacing.standard.s2) {
            Text("\(correct) / \(total) correct")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(argb: p.text))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color(argb: p.border))
                    Rectangle().fill(Color(argb: p.primary)).frame(width: proxy.size.width * CGFloat(current / 100))
                    if let mark = passMark {
                        Rectangle().fill(Color(argb: p.text)).frame(width: 3).offset(x: proxy.size.width * CGFloat(mark))
                    }
                    PercentLabel(value: current)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(argb: p.text))
                        .frame(maxWidth: .infinity)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .frame(height: 28)
        }
        .frame(maxWidth: 420)
        .onAppear {
            if animated && !reduceMotion { withAnimation(.easeOut(duration: 0.9)) { shown = target } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(correct) of \(total) correct, \(Int(target)) percent")
    }
}

/// What the results screen shows beyond the copy.
public struct LessonResultsStats: Equatable, Sendable {
    public var correct: Int
    public var total: Int
    public var score: Double
    public var xp: Int
    public var streakDays: Int?
    public var goalXpToday: Int?
    public var goalXp: Int?

    public init(correct: Int, total: Int, score: Double, xp: Int, streakDays: Int? = nil, goalXpToday: Int? = nil, goalXp: Int? = nil) {
        self.correct = correct
        self.total = total
        self.score = score
        self.xp = xp
        self.streakDays = streakDays
        self.goalXpToday = goalXpToday
        self.goalXp = goalXp
    }
}

/// The end of a lesson (Android Results/EndScreen): title, notes, score bar, XP, streak and goal.
public struct LessonResultsView: View {
    private let end: LessonEndKind
    private let stats: LessonResultsStats
    private let savedPractice: Bool
    private let animated: Bool
    private let onBack: () -> Void
    private let onTryAgain: (() -> Void)?
    private let onShare: (() -> Void)?
    private let onPracticeAgain: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    public init(
        end: LessonEndKind,
        stats: LessonResultsStats,
        savedPractice: Bool = false,
        animated: Bool = true,
        onBack: @escaping () -> Void,
        onTryAgain: (() -> Void)? = nil,
        onShare: (() -> Void)? = nil,
        onPracticeAgain: (() -> Void)? = nil
    ) {
        self.end = end
        self.stats = stats
        self.savedPractice = savedPractice
        self.animated = animated
        self.onBack = onBack
        self.onTryAgain = onTryAgain
        self.onShare = onShare
        self.onPracticeAgain = onPracticeAgain
    }

    public var body: some View {
        let p = lessonPalette(colorScheme)
        let copy = lessonResultsCopy(end: end, savedPractice: savedPractice)
        ScrollView {
            VStack(spacing: Spacing.standard.s3) {
                Text(copy.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color(argb: p.text))
                    .multilineTextAlignment(.center)
                if !copy.body.isEmpty {
                    Text(copy.body)
                        .font(.system(size: 17))
                        .foregroundColor(Color(argb: p.textMuted))
                        .multilineTextAlignment(.center)
                }
                if copy.showsScore {
                    LessonScoreBar(correct: stats.correct, total: stats.total, score: stats.score, passMark: copy.passMark, animated: animated)
                    if copy.passed && stats.xp > 0 {
                        Text("+\(stats.xp) XP")
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundColor(Color(argb: p.primary))
                    }
                    if copy.passed, let days = stats.streakDays, days > 0 {
                        Text("\u{1F525} " + streakLine(days: days))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(Color(argb: p.streakFire))
                    }
                    if copy.passed, let today = stats.goalXpToday, let goal = stats.goalXp {
                        DailyGoalRingView(xp: today, goal: goal, palette: p)
                    }
                } else {
                    ProgressView()
                }
                VStack(spacing: Spacing.standard.s2) {
                    if copy.showsScore {
                        if !copy.passed && onTryAgain != nil, let again = onTryAgain {
                            actionButton("Try again", primary: true, p: p, action: again)
                        }
                        actionButton(savedPractice ? "Back to vocabulary" : "Back to path", primary: copy.passed || onTryAgain == nil, p: p, action: onBack)
                        if copy.passed, end != .practice, !savedPractice, let share = onShare {
                            actionButton("Share", primary: false, p: p, action: share)
                        }
                        if copy.passed, !savedPractice, let practice = onPracticeAgain {
                            actionButton("Practice again", primary: false, p: p, action: practice)
                        }
                    }
                }
                .frame(maxWidth: 420)
            }
            .padding(Spacing.standard.s4)
            .frame(maxWidth: .infinity)
        }
        .background(Color(argb: p.bg))
    }

    private func actionButton(_ title: String, primary: Bool, p: AppPalette, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(argb: primary ? p.primaryContrast : p.text))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: Radii.standard.md).fill(Color(argb: primary ? p.primary : p.surface)))
                .overlay(RoundedRectangle(cornerRadius: Radii.standard.md).stroke(Color(argb: primary ? p.primary : p.border)))
        }
    }
}

/// "Daily goal reached!" full screen (Android GoalCelebrationScreen).
public struct GoalCelebrationView: View {
    private let xpToday: Int
    private let goalXp: Int
    private let animated: Bool
    private let onContinue: () -> Void
    @State private var sweep: Double = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(xpToday: Int, goalXp: Int, animated: Bool = true, onContinue: @escaping () -> Void) {
        self.xpToday = xpToday
        self.goalXp = goalXp
        self.animated = animated
        self.onContinue = onContinue
    }

    public var body: some View {
        let p = lessonPalette(colorScheme)
        let progress = (animated && !reduceMotion) ? sweep : 1
        VStack(spacing: Spacing.standard.s4) {
            ZStack {
                Circle().stroke(Color(argb: p.border), lineWidth: 18)
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(Color(argb: p.primary), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(xpToday)")
                    .font(.system(size: 44, weight: .heavy))
                    .foregroundColor(Color(argb: p.text))
            }
            .frame(width: 180, height: 180)
            Text("Daily goal reached!")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Color(argb: p.text))
            Text(goalCelebrationLine(xpToday: xpToday, goalXp: goalXp))
                .font(.system(size: 17))
                .foregroundColor(Color(argb: p.textMuted))
            Button(action: onContinue) {
                Text("Continue")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(argb: p.primaryContrast))
                    .frame(maxWidth: 420, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: Radii.standard.md).fill(Color(argb: p.primary)))
            }
        }
        .padding(Spacing.standard.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(argb: p.bg))
        .onAppear {
            if animated && !reduceMotion { withAnimation(.easeOut(duration: 0.9)) { sweep = 1 } }
        }
    }
}
