import Foundation
import Combine
import QModel
import QDomain
import QData

/// Sends queued results through a closure (the Stow flow flushes before it stows).
struct ClosureStowFlusher: StowQueueFlushing {
    let run: @Sendable () async -> Void

    func flushQueue() async {
        await run()
    }
}

/// Everything behind the Learn tab that is not drawing: it reloads the path from each bootstrap, downloads the pinned
/// course when it is not on the device, drives the update banner's roll-forward and builds the Stow models once the
/// user is known. SwiftUI-free, so `swift test` covers it.
@MainActor
public final class PathHostModel: ObservableObject {
    public let path: PathModel
    public let banner: UpdateBannerModel
    /// Non-nil while the pinned course is being fetched, or when that failed.
    @Published public private(set) var download: CourseDownloadPhase?
    @Published public private(set) var themeIndex: ThemeIndexArtifact?
    @Published public private(set) var stowFlow: StowFlowModel?
    @Published public private(set) var stowReminder: StowReminderModel?

    private let services: PathServices?
    private weak var shell: SignedInShell?
    private let reminderPrefs: StowReminderPrefs
    private var stowUserId: String?
    private var downloadingCourse: CourseRef?
    private var downloadTask: Task<Void, Never>?
    /// Downloads that finished but still failed the on-disk check, for the current course.
    private var unverifiedDownloads = 0
    /// How many finished-but-unverified downloads are retried before the screen shows Try again.
    static let maxUnverifiedDownloads = 2

    public init(shell: SignedInShell, services: PathServices? = nil, reminderPrefs: StowReminderPrefs = UserDefaultsStowReminderPrefs()) {
        let resolved = services ?? shell.app?.path
        self.services = resolved
        self.shell = shell
        self.reminderPrefs = reminderPrefs
        self.path = PathModel(repository: resolved?.repository ?? UnavailablePathRepository())
        self.banner = UpdateBannerModel()
    }

    // MARK: Bootstrap

    /// A new bootstrap arrived: reload the path, offer any update, and fetch the course if it is missing.
    public func bootstrapChanged(_ bootstrap: BootstrapResponse) async {
        banner.setOffer(ContentUpdateOffer.detect(course: bootstrap.course, update: bootstrap.update))
        prepareStow()
        // Start the download first, so the screen never flashes "couldn't read" for a course that isn't on the device yet.
        var missing = false
        if let course = bootstrap.course, let services = services, !services.isDownloaded(course) {
            missing = true
            if downloadingCourse != course { startDownload(course) }
        } else {
            cancelDownload()
            download = nil
        }
        await path.refresh(bootstrap: bootstrap)
        if !missing, let course = bootstrap.course, let services = services {
            themeIndex = await services.themeIndex(course)
        }
    }

    /// Try again after a failed download.
    public func retryDownload() {
        guard let course = shell?.course, let services = services, !services.isDownloaded(course) else { return }
        downloadingCourse = nil
        unverifiedDownloads = 0
        startDownload(course)
    }

    private func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadingCourse = nil
    }

    private func startDownload(_ course: CourseRef) {
        guard let services = services else { return }
        downloadTask?.cancel()
        downloadingCourse = course
        download = .downloading(done: 0, total: 0)
        downloadTask = Task { @MainActor [weak self] in
            do {
                try await services.download(course, { progress in
                    Task { @MainActor [weak self] in self?.downloadProgressed(progress, course: course) }
                })
                guard let self = self, self.downloadingCourse == course else { return }
                if !services.isDownloaded(course) {
                    // Finished, yet the files don't verify on disk: retry a bounded number of times, then offer Try again.
                    self.unverifiedDownloads += 1
                    if self.unverifiedDownloads < PathHostModel.maxUnverifiedDownloads {
                        self.startDownload(course)
                    } else {
                        self.downloadTask = nil
                        self.download = .failed
                    }
                    return
                }
                self.unverifiedDownloads = 0
                self.downloadingCourse = nil
                self.downloadTask = nil
                self.download = nil
                if let bootstrap = self.shell?.bootstrap { await self.bootstrapChanged(bootstrap) }
            } catch {
                guard let self = self, self.downloadingCourse == course, !(error is CancellationError) else { return }
                self.download = .failed
            }
        }
    }

    private func downloadProgressed(_ progress: DownloadProgress, course: CourseRef) {
        guard downloadingCourse == course else { return }
        download = CourseDownloadPhase(progress)
    }

    // MARK: Stow

    /// The Stow models need the signed-in user (to flush that user's queue); build them once it is known.
    private func prepareStow() {
        guard let services = services, let shell = shell, let userId = shell.userId, !userId.isEmpty else { return }
        if stowFlow != nil && stowUserId == userId { return }
        stowUserId = userId
        let flush = services.flushQueue
        stowFlow = StowFlowModel(
            service: services.stow,
            flusher: ClosureStowFlusher(run: { await flush(userId) }),
            host: path,
            refresh: { [weak shell] in await shell?.refresh() })
        stowReminder = StowReminderModel(service: services.stow, prefs: reminderPrefs, host: path)
    }

    /// A submit result's `stowCleared`: the lesson was passed, so it leaves the Stowage now.
    public func stowCleared(_ lessonKey: String) async {
        await path.applyStowCleared(lessonKey)
    }

    // MARK: Roll-forward

    /// Update tapped on the banner: fetch the preview and open the confirm dialog.
    public func openRollForward() async {
        guard let services = services, let code = shell?.course?.code else { return }
        await banner.requestUpdate(courseCode: code, loadPreview: { code, version in
            try await services.rollForwardPreview(code, version)
        })
    }

    /// Confirm tapped: download, roll the pin forward, and take the new bootstrap. A failure shows on the banner.
    @discardableResult
    public func confirmRollForward() -> Task<Void, Never>? {
        guard let services = services, let shell = shell, let code = shell.course?.code else { return nil }
        return banner.confirm { offer, onProgress in
            let next = try await services.applyUpdate(code, offer, onProgress)
            await shell.apply(next)
        }
    }

    public func cancelRollForward() {
        banner.cancelConfirmation()
    }
}
