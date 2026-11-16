import Foundation
import Combine
import QModel
import QDomain

/// The Library's story and listening pages: one category's lessons by unit (web CategoryPage). Unlocked by unit,
/// not by the Parsle a lesson follows on the road (story-locked-until-previous-passed: "the story library stays
/// unlocked by unit").
public enum SideLibraryKind: String, Equatable, Hashable, Sendable {
    case story
    case listening

    public var title: String {
        switch self {
        case .story: return "Stories"
        case .listening: return "Listening"
        }
    }

    public var emptyText: String {
        switch self {
        case .story: return "No stories yet for this course."
        case .listening: return "No listening lessons yet for this course."
        }
    }

    var category: QDomain.SkillCategory {
        switch self {
        case .story: return .story
        case .listening: return .listening
        }
    }

    /// The icon on a lesson's row; the same as the road's (PathTheme.standard).
    public var icon: String {
        switch self {
        case .story: return "\u{1F4D6}"
        case .listening: return "\u{1F3A7}"
        }
    }
}

public enum SideLibraryState: Equatable, Sendable {
    case loading
    case unavailable(String)
    case ready([SideLibraryUnit])
}

/// State for a side-lesson library page. Reads the downloaded course and the learner's completions through the same
/// `PathRepository` the Learn tab uses, and the cursor from the shell's bootstrap.
@MainActor
public final class SideLibraryModel: ObservableObject {
    @Published public private(set) var state: SideLibraryState = .loading

    public let kind: SideLibraryKind
    private let repository: PathRepository?
    private let bootstrap: @MainActor () -> BootstrapResponse?
    private var generation = 0

    public init(kind: SideLibraryKind, repository: PathRepository?, bootstrap: @escaping @MainActor () -> BootstrapResponse?) {
        self.kind = kind
        self.repository = repository
        self.bootstrap = bootstrap
    }

    /// Safe on every appearance: a loaded page stays up while reloading, and only the newest call lands.
    public func refresh() async {
        guard let repository = repository, let current = bootstrap(), let course = current.course else {
            state = .unavailable("Pick a course to see its lessons.")
            return
        }
        generation += 1
        let mine = generation
        if case .ready = state {} else { state = .loading }
        do {
            let content = try await repository.pathContent(course: course)
            // Completions are best-effort, as on the road: a failure shows every lesson as not yet done.
            let completed = (try? await repository.completedLessonKeys(courseCode: course.code)) ?? []
            if mine != generation { return }
            let position = current.position.map { PositionKey(unitKey: $0.unitKey, skillKey: $0.skillKey) }
            let path = computePathProgress(content.units, position: position, completedSkillKeys: completed)
            state = .ready(sideLibrary(path, category: kind.category))
        } catch {
            if mine != generation { return }
            if case .ready = state { return }
            state = .unavailable((error as? LocalizedError)?.errorDescription ?? "Couldn't load your course.")
        }
    }

    public static func preview(kind: SideLibraryKind, _ state: SideLibraryState) -> SideLibraryModel {
        let model = SideLibraryModel(kind: kind, repository: nil, bootstrap: { nil })
        model.state = state
        return model
    }
}

/// How a library row reads, by whether its unit has been reached and whether the lesson is done.
public func sideLibraryRowNote(_ skill: PathSkill, unitUnlocked: Bool) -> String? {
    if skill.completed { return "Done" }
    return unitUnlocked ? nil : "Locked"
}
