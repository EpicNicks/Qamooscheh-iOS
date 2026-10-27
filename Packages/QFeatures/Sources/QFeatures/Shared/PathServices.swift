import Foundation
import QModel
import QDomain
import QNetwork
import QData

/// Everything the Learn tab's host calls that touches the disk or the network: the path's content, the course
/// download, the Stow calls and the roll-forward. Closures, so tests can stub each one.
public struct PathServices: @unchecked Sendable {
    public var repository: PathRepository
    /// The course's theme index (Deep Dive); nil when it has none or it can't be read.
    public var themeIndex: @Sendable (CourseRef) async -> ThemeIndexArtifact?
    /// True when every file of the pinned version is on disk.
    public var isDownloaded: @Sendable (CourseRef) -> Bool
    /// Downloads the pinned version; throws when it can't finish.
    public var download: @Sendable (CourseRef, @escaping @Sendable (DownloadProgress) -> Void) async throws -> Void
    public var stow: StowService
    /// Sends the user's queued lesson results (before a stow).
    public var flushQueue: @Sendable (String) async -> Void
    /// GET /v1/courses/{code}/roll-forward-preview?toVersion=.
    public var rollForwardPreview: @Sendable (_ courseCode: String, _ toVersion: Int) async throws -> RollForwardPreviewResponse
    /// Downloads the offered version, then POST /v1/courses/{code}/roll-forward; returns the new bootstrap.
    public var applyUpdate: @Sendable (_ courseCode: String, _ offer: ContentUpdateOffer, _ onProgress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> BootstrapResponse

    public init(
        repository: PathRepository,
        themeIndex: @escaping @Sendable (CourseRef) async -> ThemeIndexArtifact?,
        isDownloaded: @escaping @Sendable (CourseRef) -> Bool,
        download: @escaping @Sendable (CourseRef, @escaping @Sendable (DownloadProgress) -> Void) async throws -> Void,
        stow: StowService,
        flushQueue: @escaping @Sendable (String) async -> Void,
        rollForwardPreview: @escaping @Sendable (String, Int) async throws -> RollForwardPreviewResponse,
        applyUpdate: @escaping @Sendable (String, ContentUpdateOffer, @escaping @Sendable (DownloadProgress) -> Void) async throws -> BootstrapResponse
    ) {
        self.repository = repository
        self.themeIndex = themeIndex
        self.isDownloaded = isDownloaded
        self.download = download
        self.stow = stow
        self.flushQueue = flushQueue
        self.rollForwardPreview = rollForwardPreview
        self.applyUpdate = applyUpdate
    }

    /// A course code that is safe to put in a URL path.
    static func isSafeCode(_ code: String) -> Bool {
        !code.isEmpty && code.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    /// The production services on `client`, with course files in `contentStore` and the course CDN at `cdnBaseURL`.
    ///
    /// `flushQueue` is the app's single shared queue flush (`SharedOfflineQueue.flush`); no second queue is built here.
    /// Without one the Stow flow skips its pre-flush (the lesson submit already flushes).
    public static func live(
        client: ApiClient, contentStore: ContentFileStore, cdnBaseURL: URL,
        flushQueue: (@Sendable (String) async -> Void)? = nil
    ) -> PathServices {
        let reader = CourseContentReader(store: contentStore)
        let lessons = LessonRepository(client: client)
        let repository = LivePathRepository(
            reader: reader,
            completed: { code in try await lessons.completedLessons(courseCode: code).completedLessonKeys },
            prefs: { try await PrefsRepository(client: client).fetch() },
            activity: { code in
                guard PathServices.isSafeCode(code) else { throw URLError(.badURL) }
                return try await client.send(.get, "/v1/activity/\(code)")
            })
        let downloader = CourseDownloader(cdn: CdnClient(baseURL: cdnBaseURL), store: contentStore)
        let updater = ContentUpdater(downloader: downloader)

        return PathServices(
            repository: repository,
            themeIndex: { course in (try? reader.themeLibrary(course))?.index },
            isDownloaded: { course in reader.isDownloaded(course) },
            download: { course, onProgress in
                try await downloader.download(
                    courseCode: course.code, version: course.version,
                    manifestSha256: course.manifestSha256, onProgress: onProgress)
            },
            stow: StowApi(client: client),
            flushQueue: flushQueue ?? { _ in },
            rollForwardPreview: { code, version in
                guard isSafeCode(code) else { throw URLError(.badURL) }
                return try await client.send(.get, "/v1/courses/\(code)/roll-forward-preview?toVersion=\(version)")
            },
            applyUpdate: { code, offer, onProgress in
                guard isSafeCode(code) else { throw URLError(.badURL) }
                let rolled = RolledForward()
                try await updater.accept(courseCode: code, offer: offer, onProgress: onProgress, commit: { version in
                    let response: BootstrapResponse = try await client.send(
                        .post, "/v1/courses/\(code)/roll-forward", body: RollForwardRequest(toVersion: version))
                    rolled.bootstrap = response
                })
                guard let bootstrap = rolled.bootstrap else { throw URLError(.badServerResponse) }
                return bootstrap
            })
    }
}

/// Carries the roll-forward answer out of `ContentUpdater.accept`'s commit step.
private final class RolledForward: @unchecked Sendable {
    var bootstrap: BootstrapResponse?
}

/// The path's content from the downloaded course, the completed lessons and the daily-goal sources.
public struct LivePathRepository: PathRepository {
    private let reader: CourseContentReader
    private let completed: @Sendable (String) async throws -> [String]
    private let prefsFetch: @Sendable () async throws -> PrefsResponse
    private let activityFetch: @Sendable (String) async throws -> ActivityResponse

    public init(
        reader: CourseContentReader,
        completed: @escaping @Sendable (String) async throws -> [String],
        prefs: @escaping @Sendable () async throws -> PrefsResponse,
        activity: @escaping @Sendable (String) async throws -> ActivityResponse
    ) {
        self.reader = reader
        self.completed = completed
        self.prefsFetch = prefs
        self.activityFetch = activity
    }

    public func pathContent(course: CourseRef) async throws -> PathContent {
        guard reader.isDownloaded(course) else { throw PathContentError.notDownloaded }
        guard let content = try reader.pathUnits(course) else { throw PathContentError.unreadable }
        return PathContent(units: content)
    }

    public func completedLessonKeys(courseCode: String) async throws -> Set<String> {
        Set(try await completed(courseCode))
    }

    public func prefs() async throws -> PrefsResponse {
        try await prefsFetch()
    }

    public func activity(courseCode: String) async throws -> ActivityResponse {
        try await activityFetch(courseCode)
    }
}

public enum PathContentError: Error, Equatable, LocalizedError, Sendable {
    case notDownloaded
    case unreadable

    public var errorDescription: String? {
        switch self {
        case .notDownloaded: return "This course isn't downloaded yet."
        case .unreadable: return "Couldn't read this course from the device."
        }
    }
}

/// Stands in for the repository where there are no services (previews, snapshot tests): every read fails.
struct UnavailablePathRepository: PathRepository {
    func pathContent(course: CourseRef) async throws -> PathContent { throw PathContentError.unreadable }
    func completedLessonKeys(courseCode: String) async throws -> Set<String> { [] }
    func prefs() async throws -> PrefsResponse { throw URLError(.notConnectedToInternet) }
    func activity(courseCode: String) async throws -> ActivityResponse { throw URLError(.notConnectedToInternet) }
}

public extension CourseContentReader {
    /// The course's units as path inputs (web `useCoursePath`, Android `buildPathUnitInputs`): only standard skills
    /// form positions, in published order; the rest are the unit's other skills. nil when the manifest or a unit is missing.
    func pathUnits(_ course: CourseRef) throws -> [PathUnitInput]? {
        guard let manifest = try manifest(course) else { return nil }
        var inputs: [PathUnitInput] = []
        for ref in manifest.units {
            guard let unit = try unitArtifact(course, path: ref.path) else { return nil }
            var standard: [PathPositionInput] = []
            var others: [PathSkillInput] = []
            for position in unit.positions {
                var lessons: [PathSkillInput] = []
                for skillRef in position.skills {
                    let header = try skill(course, path: skillRef.path)
                    // The artifact's category (QModel) as the path's own (QDomain).
                    var category = QDomain.SkillCategory.standard
                    if let found = header, let mapped = QDomain.SkillCategory(rawValue: found.category.rawValue) { category = mapped }
                    let input = PathSkillInput(
                        skillKey: skillRef.id, title: header?.title ?? skillRef.id,
                        category: category, arc: header?.arc)
                    if category == QDomain.SkillCategory.standard {
                        lessons.append(input)
                    } else {
                        others.append(input)
                    }
                }
                if !lessons.isEmpty { standard.append(PathPositionInput(skills: lessons)) }
            }
            inputs.append(PathUnitInput(unitKey: unit.id, title: unit.title, standardPositions: standard, otherSkills: others))
        }
        return inputs
    }
}
