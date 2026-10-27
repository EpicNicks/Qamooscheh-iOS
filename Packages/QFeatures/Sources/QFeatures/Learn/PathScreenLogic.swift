import Foundation
import QData
import QModel
import QDomain

// SwiftUI-free rules for the Path screen (Android PathScreen.kt + PathViewModel.kt's PathContent half).

/// Where the pinned course's download stands (Android CourseDownloadState, minus Complete: no phase means
/// the content is on the device).
public enum CourseDownloadPhase: Equatable, Sendable {
    case waiting
    case downloading(done: Int, total: Int)
    case failed

    /// A `CourseDownloader` progress callback as a phase.
    public init(_ progress: DownloadProgress) {
        self = .downloading(done: progress.done, total: progress.discovered)
    }
}

/// Which of the screen's four bodies shows.
public enum PathScreenPhase: Equatable, Sendable {
    case loading
    case downloading(CourseDownloadPhase)
    case failed
    case ready
}

/// Android PathScreen's `when`: no course is still "loading"; an unfinished download comes before a read
/// failure or the road; then the read result.
public func pathScreenPhase(status: PathLoadStatus, download: CourseDownloadPhase?) -> PathScreenPhase {
    if status == .noCourse { return .loading }
    if let download = download { return .downloading(download) }
    switch status {
    case .noCourse, .loading: return .loading
    case .failed: return .failed
    case .ready: return .ready
    }
}

public enum PathScreenCopy {
    public static let loading = "Loading your course\u{2026}"
    public static let readFailed = "Couldn't read this course from the device."
    public static let downloadFailed = "Couldn't download this course."
    public static let tryAgain = "Try again"
    public static let waiting = "Waiting for a connection to download your course\u{2026}"
    public static let jumpToCurrent = "Jump to current lesson"

    /// "Downloading your course... 3 of 40", or without the count until the total is known.
    public static func downloading(done: Int, total: Int) -> String {
        total > 0 ? "Downloading your course\u{2026} \(done) of \(total)" : "Downloading your course\u{2026}"
    }

    /// The line under the spinner (or the error, for a failed download).
    public static func message(for download: CourseDownloadPhase) -> String {
        switch download {
        case .failed: return downloadFailed
        case .waiting: return waiting
        case let .downloading(done, total): return downloading(done: done, total: total)
        }
    }

    public static func reviewUnitVocabulary(_ title: String) -> String {
        "Review vocabulary: \(title)"
    }
}

/// What a lesson's primary button does.
public enum PathPrimaryAction: Equatable, Sendable {
    case retryStowed
    case startLesson
    case practice
}

/// A stowed lesson is behind the cursor but not passed: practising it would count for nothing.
public func pathPrimaryAction(_ skill: PathSkill) -> PathPrimaryAction {
    if skill.stowed { return .retryStowed }
    if skill.status == .current { return .startLesson }
    return .practice
}

/// The widest the road's column grows; wider screens keep a phone-like column.
public let pathColumnMaxWidth: Double = 560

/// Compact layout (collapsed forks, tighter rows) below the theme's breakpoint.
public func pathIsCompact(width: Double) -> Bool {
    width < Double(PathTheme.compactBreakpoint)
}

/// A lesson of the loaded course by key, standard positions first.
public func pathSkill(key: String, in units: [PathUnit]) -> PathSkill? {
    for unit in units {
        for position in unit.standardPositions {
            if let skill = position.skills.first(where: { $0.skillKey == key }) { return skill }
        }
        if let skill = unit.otherSkills.first(where: { $0.skillKey == key }) { return skill }
    }
    return nil
}

/// Whether every position of the unit is behind the cursor. A deferred unit still reads as complete here;
/// the badge swaps the check for the Stow icon.
public func pathUnitComplete(_ unit: PathUnit) -> Bool {
    !unit.standardPositions.isEmpty && unit.standardPositions.allSatisfy { $0.status == .unlocked }
}

/// Where the screen scrolls to: the unit whose road holds the current node, and that node's y in the road.
public struct CurrentRoadTarget: Equatable, Sendable {
    public var unitIndex: Int
    public var nodeY: Double

    public init(unitIndex: Int, nodeY: Double) {
        self.unitIndex = unitIndex
        self.nodeY = nodeY
    }
}

public func currentRoadTarget(_ roads: [UnitRoad]) -> CurrentRoadTarget? {
    for (index, road) in roads.enumerated() {
        if let y = road.currentNodeY { return CurrentRoadTarget(unitIndex: index, nodeY: y) }
    }
    return nil
}

/// The screen opens on the current lesson once per course content: a new key scrolls again (Android
/// LaunchedEffect keys: the first unit and the unit count).
public func pathScrollKey(course: CourseRef?, units: [PathUnit]) -> String {
    "\(course?.code ?? "")/\(course?.version ?? 0)/\(units.first?.unitKey ?? "")/\(units.count)"
}

/// The anchor (0...1, top to bottom) that `scrollTo` needs so the node sits mid-viewport. A road's point at
/// fraction `a` of its height lands on the viewport's point at fraction `a`; solving
/// `roadTop + a*roadHeight = a*viewport` for `roadTop = viewport/2 - nodeY` gives the fraction below,
/// clamped where the node cannot be centred.
public func pathScrollAnchorFraction(viewportHeight: Double, roadHeight: Double, nodeY: Double) -> Double {
    let spread = viewportHeight - roadHeight
    if abs(spread) < 1 { return 0.5 }
    let fraction = (viewportHeight / 2 - nodeY) / spread
    return min(max(fraction, 0), 1)
}

/// Where the current road sits in the scroll view, from its frame in the viewport's space. A road that is
/// not on screen points the way it is, as Android does for an item that is not laid out.
public func currentRoadScroll(roadMinY: Double, roadHeight: Double, nodeY: Double, viewportHeight: Double, roadOnScreen: Bool) -> CurrentRoadScroll {
    if roadOnScreen {
        return .visible(nodeCentre: roadMinY + nodeY, viewportStart: 0, viewportEnd: viewportHeight)
    }
    let middle = roadMinY + roadHeight / 2
    return middle < viewportHeight / 2 ? .offscreenAbove : .offscreenBelow
}

/// The reminder shows only when it is due and enabled, never over the Stow dialogs, and only once the path
/// it lists is drawn.
public func stowReminderPresented(isShown: Bool, flowOpen: Bool, phase: PathScreenPhase, hasGroups: Bool) -> Bool {
    isShown && !flowOpen && phase == .ready && hasGroups
}
