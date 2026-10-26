import SwiftUI
import QModel
import QDomain
import QDesign

/// What the header row shows (Android reads these from the profile and bootstrap).
public struct PathHeaderInfo: Equatable, Sendable {
    public var courseName: String
    public var streakDays: Int
    public var totalXp: Int?
    public var celebrating: Bool

    public init(courseName: String, streakDays: Int, totalXp: Int? = nil, celebrating: Bool = false) {
        self.courseName = courseName
        self.streakDays = streakDays
        self.totalXp = totalXp
        self.celebrating = celebrating
    }
}

private let pathScrollSpace = "pathScroll"

/// The current unit's road frame in the scroll view's space; nil from every other road.
private struct PathRoadFrameKey: PreferenceKey {
    static var defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        if let next = nextValue() { value = next }
    }
}

private func pathRoadRowId(_ unitKey: String) -> String {
    return "road:\(unitKey)"
}

/// The Learn tab's body (web PathPage, Android PathScreen): loading, downloading, failed or the road.
/// Plain values and closures; `PathScreen` wires it to the models.
public struct PathScreenView: View {
    private let state: PathState
    private let download: CourseDownloadPhase?
    private let themeIndex: ThemeIndexArtifact?
    private let header: PathHeaderInfo
    private let banner: AnyView?
    private let navigator: PathNavigator
    private let palette: AppPalette?
    private let onRetryDownload: () -> Void
    private let onPickCourse: () -> Void
    private let onTogglePopover: (String) -> Void
    private let onClosePopover: () -> Void
    private let onScroll: (CurrentRoadScroll?) -> Void
    private let onStow: ((PathSkill) -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    public init(
        state: PathState,
        download: CourseDownloadPhase? = nil,
        themeIndex: ThemeIndexArtifact? = nil,
        header: PathHeaderInfo,
        banner: AnyView? = nil,
        navigator: PathNavigator = NoopPathNavigator(),
        palette: AppPalette? = nil,
        onRetryDownload: @escaping () -> Void = {},
        onPickCourse: @escaping () -> Void = {},
        onTogglePopover: @escaping (String) -> Void = { _ in },
        onClosePopover: @escaping () -> Void = {},
        onScroll: @escaping (CurrentRoadScroll?) -> Void = { _ in },
        onStow: ((PathSkill) -> Void)? = nil
    ) {
        self.state = state
        self.download = download
        self.themeIndex = themeIndex
        self.header = header
        self.banner = banner
        self.navigator = navigator
        self.palette = palette
        self.onRetryDownload = onRetryDownload
        self.onPickCourse = onPickCourse
        self.onTogglePopover = onTogglePopover
        self.onClosePopover = onClosePopover
        self.onScroll = onScroll
        self.onStow = onStow
    }

    /// Which body is showing; the Stow reminder gates on it.
    public var phase: PathScreenPhase {
        return pathScreenPhase(status: state.status, download: download)
    }

    public var body: some View {
        let p = palette ?? (colorScheme == .dark ? AppPalette.dark : AppPalette.light)
        ZStack {
            Color(argb: p.bg).ignoresSafeArea()
            switch phase {
            case .ready:
                PathReadyView(
                    state: state,
                    themeIndex: themeIndex,
                    header: header,
                    banner: banner,
                    navigator: navigator,
                    palette: p,
                    onPickCourse: onPickCourse,
                    onTogglePopover: onTogglePopover,
                    onClosePopover: onClosePopover,
                    onScroll: onScroll,
                    onStow: onStow
                )
            default:
                PathStatusView(phase: phase, palette: p, onRetry: onRetryDownload)
            }
        }
    }
}

/// Loading, downloading (waiting, n of total, failed with Try again) and the read failure.
private struct PathStatusView: View {
    let phase: PathScreenPhase
    let palette: AppPalette
    let onRetry: () -> Void

    var body: some View {
        switch phase {
        case .loading:
            spinner(PathScreenCopy.loading)
        case let .downloading(download):
            if download == .failed {
                VStack(spacing: Spacing.standard.s3) {
                    errorText(PathScreenCopy.message(for: download))
                    PathPopupButton(text: PathScreenCopy.tryAgain, kind: .primary, palette: palette, action: onRetry)
                }
                .padding(Spacing.standard.s3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                spinner(PathScreenCopy.message(for: download))
            }
        case .failed:
            errorText(PathScreenCopy.readFailed)
                .padding(Spacing.standard.s3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .ready:
            EmptyView()
        }
    }

    private func spinner(_ label: String) -> some View {
        VStack(spacing: Spacing.standard.s3) {
            ProgressView()
            Text(label)
                .font(.system(size: 16))
                .foregroundColor(Color(argb: palette.textMuted))
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.standard.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func errorText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(Color(argb: palette.danger))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.standard.s3)
            .background(RoundedRectangle(cornerRadius: Radii.standard.md).fill(Color(argb: palette.surface)))
            .overlay(RoundedRectangle(cornerRadius: Radii.standard.md).strokeBorder(Color(argb: palette.danger), lineWidth: 1))
    }
}

/// A unit's title, pinned while its road scrolls past (web CourseSection's sticky chip): the column's full
/// width, the unit's completion mark (the gray Stow icon for a deferred unit), and a book that opens the
/// unit's vocabulary.
private struct PathUnitTitleView: View {
    let unit: PathUnit
    let palette: AppPalette
    let onReviewVocabulary: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radii.standard.md)
        let style = StowedUnitStyle.style(for: unit)
        HStack(spacing: Spacing.standard.s2) {
            Text(unit.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(argb: palette.textMuted))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Spacing.standard.s2)
                .accessibilityAddTraits(.isHeader)
            UnitCompletionBadgeView(complete: pathUnitComplete(unit) && style == nil, style: style, palette: palette)
            Button(action: onReviewVocabulary) {
                Image(systemName: "book")
                    .font(.system(size: 18))
                    .foregroundColor(Color(argb: palette.textMuted))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(PathScreenCopy.reviewUnitVocabulary(unit.title))
        }
        .padding(.leading, Spacing.standard.s3)
        .background(shape.fill(Color(argb: palette.surface)))
        .overlay(shape.strokeBorder(Color(argb: palette.border), lineWidth: 1))
        .frame(maxWidth: CGFloat(pathColumnMaxWidth))
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.standard.s2)
        .background(Color(argb: palette.bg))
    }
}

/// The group sheet, with the Deep Dive it can open nested inside it.
private struct PathGroupSheetHost: View {
    let skills: [PathSkill]
    let state: PathState
    let themeIndex: ThemeIndexArtifact?
    let navigator: PathNavigator
    let palette: AppPalette
    let onDismiss: () -> Void

    @State private var deepDiveKey: String?

    var body: some View {
        let nextSkip = state.nextSkipTarget
        let stowable = Set(state.stowableLessonKeys)
        SkillGroupSheetView(
            skills: skills,
            actions: { lessonPopoverActions($0, nextSkipTarget: nextSkip, themeIndex: themeIndex, stowableLessonKeys: stowable) },
            palette: palette,
            onPrimary: { navigator.performPrimary($0) },
            onDeepDive: { deepDiveKey = $0.skillKey },
            onSkip: { _, target in navigator.checkpoint(target) },
            onReviewVocabulary: { navigator.reviewVocabulary($0) },
            onDismiss: onDismiss
        )
        .pathBottomSheet(isPresented: Binding(
            get: { deepDiveKey != nil },
            set: { shown in if !shown { deepDiveKey = nil } }
        )) {
            if let key = deepDiveKey {
                DeepDiveSheetView(
                    lessonKey: key,
                    themeIndex: themeIndex,
                    palette: palette,
                    onRemix: { navigator.deepDiveRemix(lessonKey: key) },
                    onOpenTheme: { navigator.openTheme(themeId: $0, fromLessonKey: key) },
                    onDismiss: { deepDiveKey = nil }
                )
            }
        }
    }
}

/// The road itself, one section per unit: a pinned title chip, the placement node for the next unit, and
/// the unit's road. Opens scrolled to the current lesson, with a button back to it once it is off screen.
private struct PathReadyView: View {
    let state: PathState
    let themeIndex: ThemeIndexArtifact?
    let header: PathHeaderInfo
    let banner: AnyView?
    let navigator: PathNavigator
    let palette: AppPalette
    let onPickCourse: () -> Void
    let onTogglePopover: (String) -> Void
    let onClosePopover: () -> Void
    let onScroll: (CurrentRoadScroll?) -> Void
    let onStow: ((PathSkill) -> Void)?

    @State private var roadFrame: CGRect?
    @State private var roadOnScreen = false
    @State private var groupPosition: PathPosition?
    @State private var deepDiveKey: String?

    private let theme = PathTheme.standard

    var body: some View {
        GeometryReader { proxy in
            let compact = pathIsCompact(width: Double(proxy.size.width))
            let config = theme.layoutFor(compact: compact)
            let roads = state.units.map { UnitRoad(positions: $0.standardPositions, config: config, collapseForks: compact) }
            let target = currentRoadTarget(roads)
            let viewport = Double(proxy.size.height)
            let scrollKey = pathScrollKey(course: state.course, units: state.units)
            ScrollViewReader { reader in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        content(roads: roads, compact: compact, target: target, viewport: viewport)
                    }
                    .coordinateSpace(name: pathScrollSpace)
                    .onPreferenceChange(PathRoadFrameKey.self) { frame in
                        guard let frame = frame else { return }
                        roadFrame = frame
                        reportScroll(frame: frame, onScreen: roadOnScreen, target: target, roads: roads, viewport: viewport)
                    }
                    .task(id: scrollKey) {
                        // Open on the current lesson, once per course content, after the first layout.
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        scrollToCurrent(reader, target: target, roads: roads, viewport: viewport, animated: false)
                    }
                    if let direction = state.jumpDirection {
                        JumpToCurrentButton(direction: direction, palette: palette) {
                            scrollToCurrent(reader, target: target, roads: roads, viewport: viewport, animated: true)
                        }
                        .padding(Spacing.standard.s4)
                    }
                }
            }
        }
        .pathBottomSheet(isPresented: Binding(
            get: { groupPosition != nil },
            set: { shown in if !shown { groupPosition = nil } }
        )) {
            if let position = groupPosition {
                PathGroupSheetHost(
                    skills: position.skills,
                    state: state,
                    themeIndex: themeIndex,
                    navigator: navigator,
                    palette: palette,
                    onDismiss: { groupPosition = nil }
                )
            }
        }
        .pathBottomSheet(isPresented: Binding(
            get: { deepDiveKey != nil },
            set: { shown in if !shown { deepDiveKey = nil } }
        )) {
            if let key = deepDiveKey {
                DeepDiveSheetView(
                    lessonKey: key,
                    themeIndex: themeIndex,
                    palette: palette,
                    onRemix: { navigator.deepDiveRemix(lessonKey: key) },
                    onOpenTheme: { navigator.openTheme(themeId: $0, fromLessonKey: key) },
                    onDismiss: { deepDiveKey = nil }
                )
            }
        }
    }

    @ViewBuilder
    private func content(roads: [UnitRoad], compact: Bool, target: CurrentRoadTarget?, viewport: Double) -> some View {
        let column = CGFloat(pathColumnMaxWidth)
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            VStack(spacing: Spacing.standard.s3) {
                PathHeaderView(
                    courseName: header.courseName,
                    streakDays: header.streakDays,
                    goal: state.dailyGoal,
                    totalXp: header.totalXp,
                    celebrating: header.celebrating,
                    palette: palette,
                    onPickCourse: onPickCourse
                )
                if let banner = banner {
                    banner
                }
            }
            .frame(maxWidth: column)
            .frame(maxWidth: .infinity)
            .padding(.top, Spacing.standard.s2)
            .padding(.bottom, Spacing.standard.s3)

            ForEach(Array(state.units.enumerated()), id: \.element.unitKey) { index, unit in
                Section {
                    if let entry = state.nextUnitEntry, entry.unitKey == unit.unitKey {
                        PlacementTestNodeView(palette: palette, onTap: { navigator.checkpoint(entry) })
                            .frame(maxWidth: column)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.standard.s2)
                    }
                    road(roads[index], unit: unit, isCurrent: target?.unitIndex == index, target: target, roads: roads, viewport: viewport)
                } header: {
                    PathUnitTitleView(
                        unit: unit,
                        palette: palette,
                        onReviewVocabulary: { navigator.reviewUnitVocabulary(unitKey: unit.unitKey) }
                    )
                }
            }
        }
        .padding(.horizontal, Spacing.standard.s3)
        .padding(.bottom, 96)
    }

    private func road(_ road: UnitRoad, unit: PathUnit, isCurrent: Bool, target: CurrentRoadTarget?, roads: [UnitRoad], viewport: Double) -> some View {
        SkillRoadView(
            road: road,
            theme: theme,
            palette: palette,
            onSkillTap: { skill in onTogglePopover(pathPopoverId(unitKey: skill.unitKey, skillKey: skill.skillKey)) },
            onGroupTap: { position in groupPosition = position },
            openPopoverId: state.openPopoverId,
            popoverContent: { skill in popoverContent(skill) },
            onPopoverDismiss: onClosePopover
        )
        .frame(maxWidth: CGFloat(pathColumnMaxWidth))
        .frame(maxWidth: .infinity)
        .padding(.bottom, Spacing.standard.s5)
        .id(pathRoadRowId(unit.unitKey))
        .background(
            GeometryReader { geometry in
                Color.clear.preference(key: PathRoadFrameKey.self, value: isCurrent ? geometry.frame(in: .named(pathScrollSpace)) : nil)
            }
        )
        .onAppear {
            guard isCurrent else { return }
            roadOnScreen = true
            reportScroll(frame: roadFrame, onScreen: true, target: target, roads: roads, viewport: viewport)
        }
        .onDisappear {
            guard isCurrent else { return }
            roadOnScreen = false
            reportScroll(frame: roadFrame, onScreen: false, target: target, roads: roads, viewport: viewport)
        }
    }

    private func popoverContent(_ skill: PathSkill) -> AnyView {
        let actions = lessonPopoverActions(
            skill,
            nextSkipTarget: state.nextSkipTarget,
            themeIndex: themeIndex,
            stowableLessonKeys: Set(state.stowableLessonKeys)
        )
        var deepDive: (() -> Void)?
        if actions.hasDeepDive {
            deepDive = {
                onClosePopover()
                deepDiveKey = skill.skillKey
            }
        }
        var skip: (() -> Void)?
        if let skipTarget = actions.skipTarget {
            skip = {
                onClosePopover()
                navigator.checkpoint(skipTarget)
            }
        }
        var stow: (() -> Void)?
        if actions.stowOffered, let onStow = onStow {
            stow = {
                onClosePopover()
                onStow(skill)
            }
        }
        return AnyView(
            LessonStartPopoverView(
                primaryLabel: actions.primaryLabel,
                description: skill.title,
                palette: palette,
                onPrimary: {
                    onClosePopover()
                    navigator.performPrimary(skill)
                },
                onDeepDive: deepDive,
                onSkip: skip,
                onReviewVocabulary: {
                    onClosePopover()
                    navigator.reviewVocabulary(skill)
                },
                onStow: stow
            )
        )
    }

    private func scrollToCurrent(_ reader: ScrollViewProxy, target: CurrentRoadTarget?, roads: [UnitRoad], viewport: Double, animated: Bool) {
        guard let target = target, target.unitIndex < state.units.count, target.unitIndex < roads.count else { return }
        let fraction = pathScrollAnchorFraction(
            viewportHeight: viewport,
            roadHeight: Double(roads[target.unitIndex].layout.totalHeight),
            nodeY: target.nodeY
        )
        let id = pathRoadRowId(state.units[target.unitIndex].unitKey)
        let anchor = UnitPoint(x: 0.5, y: CGFloat(fraction))
        if animated {
            withAnimation(.easeInOut(duration: 0.4)) { reader.scrollTo(id, anchor: anchor) }
        } else {
            reader.scrollTo(id, anchor: anchor)
        }
    }

    private func reportScroll(frame: CGRect?, onScreen: Bool, target: CurrentRoadTarget?, roads: [UnitRoad], viewport: Double) {
        var next: CurrentRoadScroll?
        if let target = target, let frame = frame, target.unitIndex < roads.count {
            next = currentRoadScroll(
                roadMinY: Double(frame.minY),
                roadHeight: Double(roads[target.unitIndex].layout.totalHeight),
                nodeY: target.nodeY,
                viewportHeight: viewport,
                roadOnScreen: onScreen
            )
        }
        if next == state.scroll { return }
        // Not during a layout pass: the model publishes a change.
        DispatchQueue.main.async { onScroll(next) }
    }
}

/// The Update banner slot: shown while an offer is open and not dismissed this visit.
struct PathUpdateBannerSlot: View {
    @ObservedObject var model: UpdateBannerModel
    let onUpdate: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        if model.isVisible, let offer = model.offer {
            UpdateBannerView(
                offer: offer,
                state: model.state,
                dialog: model.dialog,
                onUpdate: onUpdate,
                onConfirm: onConfirm,
                onCancel: { model.cancelConfirmation() },
                onDismiss: { model.dismiss() }
            )
        }
    }
}

/// The Stow dialogs and the reminder over the path. The reminder never shows over the dialogs, only once the
/// path is drawn, and puts itself away (nothing sent) when dismissed.
private struct PathStowPresentation: ViewModifier {
    @ObservedObject var flow: StowFlowModel
    @ObservedObject var reminder: StowReminderModel
    let units: [PathUnit]
    let phase: PathScreenPhase
    let onRetryLesson: (String) -> Void
    let onRetryStowed: (PathSkill) -> Void

    func body(content: Content) -> some View {
        content
            .stowDialogs(model: flow, onRetry: onRetryLesson)
            .sheet(isPresented: Binding(
                get: {
                    stowReminderPresented(
                        isShown: reminder.isShown,
                        flowOpen: flow.flow != nil,
                        phase: phase,
                        hasGroups: !reminder.groups(path: units).isEmpty
                    )
                },
                set: { shown in if !shown { reminder.putAway() } }
            )) {
                StowReminderHost(
                    model: reminder,
                    path: units,
                    onRetry: { skill in
                        reminder.putAway()
                        onRetryStowed(skill)
                    }
                )
            }
    }
}

/// The Learn tab: `PathScreenView` driven by the path model, with the update banner and the Stow flow.
public struct PathScreen: View {
    @ObservedObject private var model: PathModel
    private let download: CourseDownloadPhase?
    private let themeIndex: ThemeIndexArtifact?
    private let header: PathHeaderInfo
    private let updateBanner: UpdateBannerModel?
    private let navigator: PathNavigator
    private let stowFlow: StowFlowModel?
    private let stowReminder: StowReminderModel?
    private let onRetryDownload: () -> Void
    private let onPickCourse: () -> Void
    private let onUpdate: () -> Void
    private let onConfirmUpdate: () -> Void

    public init(
        model: PathModel,
        download: CourseDownloadPhase? = nil,
        themeIndex: ThemeIndexArtifact? = nil,
        header: PathHeaderInfo,
        updateBanner: UpdateBannerModel? = nil,
        navigator: PathNavigator = NoopPathNavigator(),
        stowFlow: StowFlowModel? = nil,
        stowReminder: StowReminderModel? = nil,
        onRetryDownload: @escaping () -> Void = {},
        onPickCourse: @escaping () -> Void = {},
        onUpdate: @escaping () -> Void = {},
        onConfirmUpdate: @escaping () -> Void = {}
    ) {
        self.model = model
        self.download = download
        self.themeIndex = themeIndex
        self.header = header
        self.updateBanner = updateBanner
        self.navigator = navigator
        self.stowFlow = stowFlow
        self.stowReminder = stowReminder
        self.onRetryDownload = onRetryDownload
        self.onPickCourse = onPickCourse
        self.onUpdate = onUpdate
        self.onConfirmUpdate = onConfirmUpdate
    }

    @ViewBuilder
    public var body: some View {
        let state = model.state
        let screen = PathScreenView(
            state: state,
            download: download,
            themeIndex: themeIndex,
            header: header,
            banner: bannerSlot(),
            navigator: navigator,
            onRetryDownload: onRetryDownload,
            onPickCourse: onPickCourse,
            onTogglePopover: { model.togglePopover($0) },
            onClosePopover: { model.closePopover() },
            onScroll: { model.setScroll($0) },
            onStow: stowAction
        )
        if let flow = stowFlow, let reminder = stowReminder {
            screen.modifier(
                PathStowPresentation(
                    flow: flow,
                    reminder: reminder,
                    units: state.units,
                    phase: screen.phase,
                    onRetryLesson: { key in
                        if let skill = pathSkill(key: key, in: state.units) { navigator.startLesson(skill) }
                    },
                    onRetryStowed: { navigator.retryStowed($0) }
                )
            )
        } else {
            screen
        }
    }

    private var stowAction: ((PathSkill) -> Void)? {
        guard let flow = stowFlow else { return nil }
        return { skill in flow.request(lessonKey: skill.skillKey) }
    }

    private func bannerSlot() -> AnyView? {
        guard let updateBanner = updateBanner else { return nil }
        return AnyView(PathUpdateBannerSlot(model: updateBanner, onUpdate: onUpdate, onConfirm: onConfirmUpdate))
    }
}
