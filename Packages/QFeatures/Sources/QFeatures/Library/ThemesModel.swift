import Foundation
import Combine
import QModel
import QDomain
import QNetwork

/// What the Library screens need to know about one Deep Dive lesson.
public struct ThemeLessonHeader: Equatable, Sendable {
    public var title: String
    public var category: QModel.SkillCategory

    public init(title: String, category: QModel.SkillCategory) {
        self.title = title
        self.category = category
    }
}

/// themes.json plus every lesson's header, keyed by lesson id.
public struct ThemeLibraryData: Equatable, Sendable {
    public var index: ThemeIndexArtifact
    public var headers: [String: ThemeLessonHeader]

    public init(index: ThemeIndexArtifact, headers: [String: ThemeLessonHeader]) {
        self.index = index
        self.headers = headers
    }
}

/// Supplies the course's themes. nil means no course (or no themes) is available yet.
public protocol ThemeLibrarySource: Sendable {
    func load() async throws -> ThemeLibraryData?
}

/// A topic and how many standard lessons it has (Android TopicSummary). `depth` is 1 for a top-level topic.
public struct TopicSummary: Equatable, Sendable {
    public var id: String
    public var lessonCount: Int
    /// "Food > Drinks" for a subtopic; the topic's own id for a root.
    public var breadcrumb: String
    public var depth: Int

    public init(id: String, lessonCount: Int, breadcrumb: String, depth: Int) {
        self.id = id
        self.lessonCount = lessonCount
        self.breadcrumb = breadcrumb
        self.depth = depth
    }
}

public func summarizeTopic(_ theme: ThemeEntry, depth: Int, data: ThemeLibraryData) -> TopicSummary {
    let count = theme.lessons.filter { data.headers[$0.id]?.category == .standard }.count
    let crumb = ancestorsOf(data.index, id: theme.id).map { $0.id }.joined(separator: " \u{203A} ")
    return TopicSummary(id: theme.id, lessonCount: count, breadcrumb: crumb, depth: depth)
}

public struct LibraryTopics: Equatable, Sendable {
    /// Top-level topics, for the grid.
    public var topics: [TopicSummary]
    /// Every topic, depth first, for the remix picker.
    public var allTopics: [TopicSummary]

    public init(topics: [TopicSummary], allTopics: [TopicSummary]) {
        self.topics = topics
        self.allTopics = allTopics
    }
}

public func makeLibraryTopics(_ data: ThemeLibraryData) -> LibraryTopics {
    let themes = data.index.themes
    let roots = childrenOf(themes, parentId: nil).map { summarizeTopic($0, depth: 1, data: data) }
    let all = dfsAllThemes(themes).map { summarizeTopic($0.theme, depth: $0.depth, data: data) }
    return LibraryTopics(topics: roots, allTopics: all)
}

public enum LibraryState: Equatable, Sendable {
    case loading
    case unavailable(String)
    case ready(LibraryTopics)
}

/// A 401 is about the session, not the data, so it is reported even from a superseded load.
func isUnauthorizedError(_ error: Error) -> Bool {
    return (error as? ApiError)?.status == 401 || error is SessionExpiredError
}

/// State for the Library topics screen (web ThemesPage, Android LibraryViewModel).
@MainActor
public final class LibraryModel: ObservableObject {
    @Published public private(set) var state: LibraryState = .loading

    private let source: ThemeLibrarySource?
    private let onUnauthorized: (@Sendable () -> Void)?
    private var generation = 0

    public init(source: ThemeLibrarySource?, onUnauthorized: (@Sendable () -> Void)? = nil) {
        self.source = source
        self.onUnauthorized = onUnauthorized
    }

    /// Safe on every appearance: loaded topics stay up while reloading, and only the newest call lands.
    public func refresh() async {
        guard let source = source else { return }
        generation += 1
        let mine = generation
        if case .ready = state {} else { state = .loading }
        do {
            let data = try await source.load()
            if mine != generation { return }
            if let data = data {
                state = .ready(makeLibraryTopics(data))
            } else {
                state = .unavailable("Pick a course to see its library.")
            }
        } catch {
            if isUnauthorizedError(error) { onUnauthorized?() }
            if mine != generation { return }
            // Keep topics already on screen rather than replacing them with an error.
            if case .ready = state { return }
            state = .unavailable(AuthRules.message(for: error, fallback: "Couldn't load your course."))
        }
    }

    public static func preview(_ state: LibraryState) -> LibraryModel {
        let model = LibraryModel(source: nil)
        model.state = state
        return model
    }
}

/// One lesson in a topic.
public struct TopicLesson: Equatable, Sendable {
    public var id: String
    public var title: String
    public var commonUsageScore: Int?

    public init(id: String, title: String, commonUsageScore: Int?) {
        self.id = id
        self.title = title
        self.commonUsageScore = commonUsageScore
    }
}

/// The web's ThemeLessonRow tag: how everyday a lesson's language is (Android CommonnessLabel).
public func commonnessLabel(_ score: Int) -> String {
    if score >= 70 { return "Everyday" }
    if score >= 40 { return "Common" }
    return "Specialized"
}

/// A topic's standard lessons, in authored order. nil when the topic isn't in the index.
public func makeTopicLessons(themeId: String, data: ThemeLibraryData) -> [TopicLesson]? {
    guard let theme = data.index.themes.first(where: { $0.id == themeId }) else { return nil }
    var lessons: [TopicLesson] = []
    for ref in theme.lessons {
        guard let header = data.headers[ref.id], header.category == .standard else { continue }
        lessons.append(TopicLesson(id: ref.id, title: header.title, commonUsageScore: ref.commonUsageScore))
    }
    return lessons
}

public enum TopicOrder: String, Equatable, Sendable {
    case structured
    case random
}

public enum TopicState: Equatable, Sendable {
    case loading
    case unavailable(String)
    case ready([TopicLesson])
}

/// State for one topic's lessons (web ThemeBrowsePage, Android TopicViewModel).
@MainActor
public final class TopicModel: ObservableObject {
    @Published public private(set) var state: TopicState = .loading
    @Published public private(set) var order: TopicOrder = .structured
    /// The lesson the learner came from, outlined in the list.
    public let highlighted: String?
    public let themeId: String

    private var shuffledIds: [String] = []
    private let source: ThemeLibrarySource?
    private let shuffle: @MainActor ([String]) -> [String]
    private let onUnauthorized: (@Sendable () -> Void)?
    private var generation = 0

    public init(
        themeId: String, highlighted: String? = nil, source: ThemeLibrarySource?,
        shuffle: @escaping @MainActor ([String]) -> [String] = { $0.shuffled() },
        onUnauthorized: (@Sendable () -> Void)? = nil
    ) {
        self.themeId = themeId
        self.highlighted = highlighted
        self.source = source
        self.shuffle = shuffle
        self.onUnauthorized = onUnauthorized
    }

    /// The lessons in the chosen order. Random keeps its order until the learner picks Random again.
    public var visibleLessons: [TopicLesson] {
        guard case .ready(let lessons) = state else { return [] }
        if order == .structured { return lessons }
        var byId: [String: TopicLesson] = [:]
        for lesson in lessons { byId[lesson.id] = lesson }
        var result: [TopicLesson] = []
        for id in shuffledIds {
            if let lesson = byId[id] { result.append(lesson) }
        }
        return result
    }

    /// Each switch to Random reshuffles, as on the web.
    public func setOrder(_ next: TopicOrder) {
        if next == .random && order != .random { reshuffle() }
        order = next
    }

    private func reshuffle() {
        guard case .ready(let lessons) = state else {
            shuffledIds = []
            return
        }
        shuffledIds = shuffle(lessons.map { $0.id })
    }

    public func refresh() async {
        guard let source = source else { return }
        generation += 1
        let mine = generation
        if case .ready = state {} else { state = .loading }
        do {
            let data = try await source.load()
            if mine != generation { return }
            guard let data = data else {
                state = .unavailable("Pick a course to see its library.")
                return
            }
            guard let lessons = makeTopicLessons(themeId: themeId, data: data) else {
                state = .unavailable("No topic named \"\(themeId)\".")
                return
            }
            state = .ready(lessons)
            // Keep the current random order for lessons still present; new ones go last.
            let present = Set(lessons.map { $0.id })
            var ids = shuffledIds.filter { present.contains($0) }
            let known = Set(ids)
            for lesson in lessons where !known.contains(lesson.id) { ids.append(lesson.id) }
            shuffledIds = ids
        } catch {
            if isUnauthorizedError(error) { onUnauthorized?() }
            if mine != generation { return }
            if case .ready = state { return }
            state = .unavailable(AuthRules.message(for: error, fallback: "Couldn't load your course."))
        }
    }

    public static func preview(themeId: String, highlighted: String?, lessons: [TopicLesson]) -> TopicModel {
        let model = TopicModel(themeId: themeId, highlighted: highlighted, source: nil)
        model.state = .ready(lessons)
        return model
    }
}

/// The remix picker's checklist (web ThemeRemixPage drags tiles between panes; Android uses a checklist).
@MainActor
public final class RemixPickerModel: ObservableObject {
    @Published public private(set) var selected: [String] = []
    public private(set) var topics: [TopicSummary]

    /// Only topics with at least one standard lesson can be remixed.
    public init(allTopics: [TopicSummary]) {
        self.topics = allTopics.filter { $0.lessonCount > 0 }
    }

    /// A reload brought a new topic list: the pick survives, minus topics that vanished.
    public func update(allTopics: [TopicSummary]) {
        topics = allTopics.filter { $0.lessonCount > 0 }
        let ids = Set(topics.map { $0.id })
        selected = selected.filter { ids.contains($0) }
        objectWillChange.send()
    }

    public func isSelected(_ id: String) -> Bool { return selected.contains(id) }

    public func toggle(_ id: String) {
        if let index = selected.firstIndex(of: id) {
            selected.remove(at: index)
        } else if topics.contains(where: { $0.id == id }) {
            selected.append(id)
        }
    }

    public var canStart: Bool { return !selected.isEmpty }

    public var startTitle: String { return selected.isEmpty ? "Pick at least one topic" : "Start remix" }

    /// The picked ids in pick order, or nil when nothing is picked.
    public func start() -> [String]? { return selected.isEmpty ? nil : selected }
}
