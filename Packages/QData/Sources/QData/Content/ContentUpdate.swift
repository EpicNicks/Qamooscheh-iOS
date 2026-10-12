import Foundation
import QModel
import QNetwork

/// A newer pinned course version offered by bootstrap (`BootstrapResponse.update`).
/// Copy matches Android's `CourseUpdateBanner` (and the web banner).
public struct ContentUpdateOffer: Equatable, Sendable {
    public let version: Int
    public let manifestSha256: String
    public let eligible: Bool
    public let notes: String?

    public init(version: Int, manifestSha256: String, eligible: Bool, notes: String? = nil) {
        self.version = version
        self.manifestSha256 = manifestSha256
        self.eligible = eligible
        self.notes = notes
    }

    public init(_ update: CourseUpdateRef) {
        self.init(version: update.version, manifestSha256: update.manifestSha256, eligible: update.eligible, notes: update.notes)
    }

    /// The offer to show, or nil. Needs a pinned course and an update newer than its pin.
    /// An ineligible update is still offered (the server decides on accept), as on Android.
    public static func detect(course: CourseRef?, update: CourseUpdateRef?) -> ContentUpdateOffer? {
        guard let course = course, let update = update, update.version > course.version else { return nil }
        return ContentUpdateOffer(update)
    }

    public var title: String {
        "Course update available \u{2014} version \(version)"
    }

    /// Notes when present, else a hint for an ineligible update, else nothing.
    public var hint: String? {
        if let notes = notes { return notes }
        return eligible ? nil : "Tap Update to see what's going on."
    }
}

/// What the banner shows while an accepted update is in flight.
public enum ContentUpdateState: Equatable, Sendable {
    case idle
    case downloading(DownloadProgress)
    case failed(String)

    public var isBusy: Bool {
        if case .downloading = self { return true }
        return false
    }

    /// 0...1, nil until the total is known.
    public var fraction: Double? {
        guard case .downloading(let progress) = self, progress.discovered > 0 else { return nil }
        return min(1, max(0, Double(progress.done) / Double(progress.discovered)))
    }
}

/// Downloads a newer course version, then rolls the pin forward.
///
/// Atomic by construction: the new version lives under its own `course/<code>/v<N>/`
/// tree and is marked complete only after every file verified, and the pin
/// (`commit`) moves only after that. A hash mismatch, an interrupted download or a
/// cancellation throws before `commit` runs, so the old version stays pinned,
/// complete and usable. The old version is never touched.
public struct ContentUpdater: Sendable {
    private let downloader: CourseDownloader

    public init(downloader: CourseDownloader) {
        self.downloader = downloader
    }

    /// `commit` receives the new version and performs the server roll-forward.
    public func accept(
        courseCode: String,
        offer: ContentUpdateOffer,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void = { _ in },
        commit: @Sendable (Int) async throws -> Void
    ) async throws {
        try await downloader.download(
            courseCode: courseCode, version: offer.version,
            manifestSha256: offer.manifestSha256, onProgress: onProgress)
        try Task.checkCancellation()
        try await commit(offer.version)
    }

    /// A user-facing message for a failed update.
    public static func message(for error: Error) -> String {
        if error is CancellationError { return "Update cancelled." }
        if error is ManifestHashMismatchError || error is FileHashMismatchError {
            return "The update didn't verify, so your course wasn't changed."
        }
        return "Couldn't update the course."
    }
}
