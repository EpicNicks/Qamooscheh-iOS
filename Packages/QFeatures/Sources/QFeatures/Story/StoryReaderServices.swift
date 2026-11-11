import Foundation
import QModel
import QDomain
import QData

/// What the reader shows once a chapter is loaded from the downloaded course.
public struct StoryReaderContent: Equatable, Sendable {
    public var title: String
    public var courseCode: String
    public var courseVersion: Int
    public var lines: [StoryReaderLine]
    public var lexemes: [String: LexemeIndexEntry]

    public init(title: String, courseCode: String, courseVersion: Int, lines: [StoryReaderLine], lexemes: [String: LexemeIndexEntry]) {
        self.title = title
        self.courseCode = courseCode
        self.courseVersion = courseVersion
        self.lines = lines
        self.lexemes = lexemes
    }
}

/// Everything the reader needs from outside: the chapter, a clip player and where a completion goes. Closures so tests stub each.
public struct StoryReaderServices: @unchecked Sendable {
    /// nil when the course or the chapter is not on this device.
    public var load: @Sendable (_ unitKey: String, _ skillKey: String) async -> StoryReaderContent?
    public var makePlayer: @Sendable (_ courseCode: String, _ version: Int) -> StoryClipPlayer?
    public var submitter: StoryReaderCompletionSubmitting

    public init(
        load: @escaping @Sendable (String, String) async -> StoryReaderContent?,
        makePlayer: @escaping @Sendable (String, Int) -> StoryClipPlayer? = { _, _ in nil },
        submitter: StoryReaderCompletionSubmitting = RecordingStoryReaderCompletionSubmitter()
    ) {
        self.load = load
        self.makePlayer = makePlayer
        self.submitter = submitter
    }

    /// Production wiring: the chapter from the pinned course on disk, takes chosen by the learner's voice, clips from the content store.
    public static func live(
        reader: CourseContentReader,
        course: @escaping @Sendable () async throws -> CourseRef?,
        preferredVoice: @escaping @Sendable (_ courseCode: String) async -> String?,
        files: ContentFileStore
    ) -> StoryReaderServices {
        return StoryReaderServices(
            load: { unitKey, skillKey in
                guard let found = try? await course(),
                      let skill = try? reader.skill(found, unitKey: unitKey, skillKey: skillKey) else { return nil }
                let audio = try? reader.audioIndex(found)
                let lexemes = (try? reader.lexemeIndex(found)) ?? [:]
                let voice = await preferredVoice(found.code)
                let lines = StoryReaderLines.lines(
                    skill.exercises, courseCode: found.code, preferredVoice: voice,
                    defaultVoice: audio?.voices.first?.id, speakers: audio?.speakers ?? [])
                return StoryReaderContent(
                    title: skill.title, courseCode: found.code, courseVersion: found.version, lines: lines, lexemes: lexemes)
            },
            makePlayer: { code, version in
                #if canImport(AVFoundation)
                let player = StoreRecordingPlayer(read: { key in try? files.read(key) })
                return RecordingStoryClipPlayer(recordings: player, courseCode: code, version: version)
                #else
                return nil
                #endif
            })
    }
}

/// Plays a story clip through the recording player: the clip path is relative to the course version root.
public final class RecordingStoryClipPlayer: StoryClipPlayer {
    private let recordings: RecordingPlaying
    private let courseCode: String
    private let version: Int

    public init(recordings: RecordingPlaying, courseCode: String, version: Int) {
        self.recordings = recordings
        self.courseCode = courseCode
        self.version = version
    }

    public func play(clip: String, onEnd: @escaping (PlayEnd) -> Void) {
        guard let key = RecordingKeys.storeKey(courseCode: courseCode, version: version, path: clip) else {
            onEnd(.failed)
            return
        }
        recordings.play(keys: [key], rate: 1, onEnd: onEnd)
    }

    public func stop() {
        recordings.stop()
    }
}

/// Tells the screen's model to re-read the playback after every play, stop and end, since the playback itself is not observable.
final class ObservedStoryClipPlayer: StoryClipPlayer {
    private let base: StoryClipPlayer
    private let changed: () -> Void

    init(base: StoryClipPlayer, changed: @escaping () -> Void) {
        self.base = base
        self.changed = changed
    }

    func play(clip: String, onEnd: @escaping (PlayEnd) -> Void) {
        base.play(clip: clip, onEnd: { [changed] end in
            onEnd(end)
            changed()
        })
        changed()
    }

    func stop() {
        base.stop()
        changed()
    }
}

/// Stands in when no audio is available (previews, tests): every clip fails at once.
final class SilentStoryClipPlayer: StoryClipPlayer {
    func play(clip: String, onEnd: @escaping (PlayEnd) -> Void) { onEnd(.failed) }
    func stop() {}
}
