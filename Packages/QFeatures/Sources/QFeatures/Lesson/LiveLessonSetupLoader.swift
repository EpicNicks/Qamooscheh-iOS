import Foundation
import QModel
import QDomain
import QNetwork
import QData

// The loader behind the lesson cover for the routes that need no session plan: a checkpoint (the server plans it,
// the skills come from disk), a story chapter (one skill read through) and a remix of picked topics. Any other route
// goes to `fallback` (the unwired placeholder until standard lessons are wired).

/// Why a route could not be turned into a lesson.
public enum LessonLoadError: Error, Equatable, Sendable {
    case noCourse
    case noUnit
    case contentMissing
}

/// Course files the loader reads, as closures so tests need no disk.
public struct LessonContentSource: Sendable {
    public var skill: @Sendable (_ course: CourseRef, _ unitKey: String, _ skillKey: String) throws -> SkillArtifact?
    public var skillAtPath: @Sendable (_ course: CourseRef, _ path: String) throws -> SkillArtifact?
    public var themes: @Sendable (_ course: CourseRef) throws -> ThemeLibraryData?

    public init(
        skill: @escaping @Sendable (CourseRef, String, String) throws -> SkillArtifact?,
        skillAtPath: @escaping @Sendable (CourseRef, String) throws -> SkillArtifact?,
        themes: @escaping @Sendable (CourseRef) throws -> ThemeLibraryData?
    ) {
        self.skill = skill
        self.skillAtPath = skillAtPath
        self.themes = themes
    }

    public static func reader(_ reader: CourseContentReader) -> LessonContentSource {
        return LessonContentSource(
            skill: { course, unitKey, skillKey in try reader.skill(course, unitKey: unitKey, skillKey: skillKey) },
            skillAtPath: { course, path in try reader.skill(course, path: path) },
            themes: { course in try reader.themeLibrary(course) }
        )
    }
}

/// Tells the shell that a checkpoint was passed, so it reloads the bootstrap and the path moves on.
public enum CheckpointRefresh {
    public static let notification = Notification.Name("QamooschehCheckpointPassed")

    /// Posts `notification` when the server passed the checkpoint.
    public static func announce(_ response: CheckpointSubmitResponse, center: NotificationCenter = .default) {
        if response.passed { center.post(name: notification, object: nil) }
    }
}

public struct LiveLessonSetupLoader: LessonSetupLoading {
    private let course: @Sendable () async throws -> CourseRef?
    private let userId: @Sendable () async -> String?
    private let cards: @Sendable (String) async -> [String: CardState]
    private let plan: @Sendable (_ unitKey: String, _ skillKey: String) async throws -> CheckpointPlanResponse
    private let content: LessonContentSource
    private let fallback: LessonSetupLoading

    public init(
        course: @escaping @Sendable () async throws -> CourseRef?,
        userId: @escaping @Sendable () async -> String?,
        cards: @escaping @Sendable (String) async -> [String: CardState],
        plan: @escaping @Sendable (String, String) async throws -> CheckpointPlanResponse,
        content: LessonContentSource,
        fallback: LessonSetupLoading = UnwiredLessonSetupLoader()
    ) {
        self.course = course
        self.userId = userId
        self.cards = cards
        self.plan = plan
        self.content = content
        self.fallback = fallback
    }

    /// The production loader: course files and the card mirror under Application Support/content (where the downloader and the submit pipeline keep them).
    public static func live(
        baseURL: URL,
        clientHeader: String,
        store: SessionStore,
        pinnedCourse: @escaping @Sendable () async throws -> CourseRef?
    ) -> LiveLessonSetupLoader {
        let client = ApiClient(baseURL: baseURL, clientHeader: clientHeader, store: store)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let files = FileContentStore(root: support.appendingPathComponent("content", isDirectory: true))
        let cardStore = CardStateStore(store: files)
        let checkpoints = CheckpointRepository(client: client)
        return LiveLessonSetupLoader(
            course: pinnedCourse,
            userId: { await store.load()?.userId },
            cards: { id in await cardStore.all(userId: id) },
            plan: { unitKey, skillKey in try await checkpoints.plan(unitKey: unitKey, skillKey: skillKey) },
            content: LessonContentSource.reader(CourseContentReader(store: files))
        )
    }

    public func setup(for route: LessonRoute) async throws -> LessonSetup? {
        if route.checkpoint { return try await checkpointSetup(route) }
        if let themeIds = route.remixThemeIds { return try await remixSetup(themeIds) }
        if let refs = route.exerciseRefs { return try await exercisesSetup(refs) }
        if let unitKey = route.unitKey, let found = try await course() {
            if let skill = try content.skill(found, unitKey, route.skillKey), skill.category == .story {
                return await storySetup(course: found, unitKey: unitKey, skillKey: route.skillKey, skill: skill)
            }
        }
        return try await fallback.setup(for: route)
    }

    public func serverPrefs() async -> LessonServerPrefs { await fallback.serverPrefs() }
    public func saveScriptMode(_ mode: ScriptMode) async { await fallback.saveScriptMode(mode) }

    private func cardsForUser() async -> [String: CardState] {
        guard let id = await userId(), !id.isEmpty else { return [:] }
        return await cards(id)
    }

    private func checkpointSetup(_ route: LessonRoute) async throws -> LessonSetup? {
        guard let unitKey = route.unitKey else { throw LessonLoadError.noUnit }
        guard let found = try await course() else { throw LessonLoadError.noCourse }
        let response = try await plan(unitKey, route.skillKey)
        var skills: [(ref: SkillRef, skill: SkillArtifact)] = []
        var seen = Set<String>()
        for entry in response.skills where seen.insert(entry.unitKey + "/" + entry.skillKey).inserted {
            guard let skill = try content.skill(found, entry.unitKey, entry.skillKey) else { throw LessonLoadError.contentMissing }
            skills.append((ref: SkillRef(unitKey: entry.unitKey, skillKey: entry.skillKey), skill: skill))
        }
        let held = await cardsForUser()
        return CheckpointLogic.setup(courseCode: found.code, plan: response, skills: skills, cards: held)
    }

    private func storySetup(course found: CourseRef, unitKey: String, skillKey: String, skill: SkillArtifact) async -> LessonSetup {
        let held = await cardsForUser()
        let ref = SkillRef(unitKey: unitKey, skillKey: skillKey)
        return LessonSetup(
            courseCode: found.code,
            courseVersion: found.version,
            instances: buildInstances(skills: [(ref: ref, skill: skill)], cards: held),
            exerciseCountBySkill: [skillKey: skill.exercises.count],
            story: StoryChapter(title: skill.title, exercises: skill.exercises)
        )
    }

    /// Saved-words practice: just the exercises the server picked, in its order; ones whose skill file or ordinal is gone are skipped.
    private func exercisesSetup(_ refs: [StarredPracticeExercise]) async throws -> LessonSetup? {
        guard let found = try await course() else { throw LessonLoadError.noCourse }
        let held = await cardsForUser()
        var built: [String: [ExerciseInstance]] = [:]
        var counts: [String: Int] = [:]
        var instances: [ExerciseInstance] = []
        var seen = Set<String>()
        for ref in refs {
            let skillId = ref.unitKey + "/" + ref.skillKey
            if built[skillId] == nil {
                guard let skill = try content.skill(found, ref.unitKey, ref.skillKey) else { continue }
                built[skillId] = buildInstances(skills: [(ref: SkillRef(unitKey: ref.unitKey, skillKey: ref.skillKey), skill: skill)], cards: held)
                counts[ref.skillKey] = skill.exercises.count
            }
            guard let instance = built[skillId]?.first(where: { $0.ordinal == ref.ordinal }) else { continue }
            if seen.insert(instance.key).inserted { instances.append(instance) }
        }
        if instances.isEmpty { return nil }
        return LessonSetup(courseCode: found.code, courseVersion: found.version, instances: instances, exerciseCountBySkill: counts)
    }

    private func remixSetup(_ themeIds: [String]) async throws -> LessonSetup? {
        guard let found = try await course() else { throw LessonLoadError.noCourse }
        guard let library = try content.themes(found) else { throw LessonLoadError.contentMissing }
        let pool = buildRemixPool(
            themeIndex: library.index, categoryOf: { library.headers[$0]?.category }, themeIds: themeIds
        )
        var skills: [String: SkillArtifact] = [:]
        var tags: [String] = []
        var seenTags = Set<String>()
        for lesson in pool {
            guard let skill = try content.skillAtPath(found, lesson.path) else { continue }
            skills[lesson.id] = skill
            for exercise in skill.exercises {
                for tag in exercise.tags where seenTags.insert(tag).inserted { tags.append(tag) }
            }
        }
        let held = await cardsForUser()
        let chosen = selectRemixLessons(
            candidates: pool.filter { skills[$0.id] != nil },
            masteryScore: computeMasteryScore(cards: held, tags: tags),
            count: remixMaxLessons
        )
        var picked: [(ref: SkillRef, skill: SkillArtifact)] = []
        var counts: [String: Int] = [:]
        for lesson in chosen {
            guard let skill = skills[lesson.id] else { continue }
            picked.append((ref: SkillRef(unitKey: nil, skillKey: lesson.id), skill: skill))
            counts[lesson.id] = skill.exercises.count
        }
        let built = buildInstances(skills: picked, cards: held)
        let instances = filterRemixExercises(built, contents: .all, max: remixMaxExercises, renderType: { $0.renderType })
        if instances.isEmpty { return nil }
        return LessonSetup(courseCode: found.code, courseVersion: found.version, instances: instances, exerciseCountBySkill: counts)
    }
}
