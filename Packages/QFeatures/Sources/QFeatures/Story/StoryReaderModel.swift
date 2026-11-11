import Foundation
import QModel
import QDomain

/// The story reader screen's state: it holds the chapter, drives the playback from QDomain and mirrors its state for
/// the view. Logic lives in StoryReaderPlayback, StoryWords and StoryReaderCompletionTrigger; this only wires them.
@MainActor
public final class StoryReaderModel: ObservableObject {
    public enum Phase: Equatable {
        case loading
        case ready
        case unavailable
    }

    @Published public private(set) var phase: Phase = .loading
    @Published public private(set) var title = ""
    @Published public private(set) var lines: [StoryReaderLine] = []
    @Published public private(set) var words: [[StoryLineWord]] = []
    @Published public private(set) var segments: [StorySegmentState] = []
    @Published public private(set) var position = 0
    @Published public private(set) var isPlaying = false
    @Published public private(set) var playingLine: Int?
    @Published public private(set) var savedTags: Set<String> = []
    @Published public private(set) var tip: StoryWordTap?
    /// Whether tapping a word speaks it (the speakHoveredWords setting); the card shows either way.
    @Published public var speakHoveredWords = true {
        didSet {
            if speakHoveredWords != oldValue, let user = userId { prefs.setSpeakHoveredWords(speakHoveredWords, userId: user) }
        }
    }
    @Published public var autoscroll = true {
        didSet {
            if autoscroll != oldValue, let user = userId { prefs.setAutoscroll(autoscroll, userId: user) }
        }
    }

    public let unitKey: String
    public let skillKey: String
    private let services: StoryReaderServices?
    private let starred: StoryStarring
    private let userIdSource: @Sendable () async -> String?
    private let prefs: StoryReaderPrefs
    private var userId: String?
    private var courseCode = ""
    private var lexemes: [String: LexemeIndexEntry] = [:]
    private var playback: StoryReaderPlayback?
    private var trigger: StoryReaderCompletionTrigger?
    private var loadStarted = false

    public init(
        unitKey: String,
        skillKey: String,
        services: StoryReaderServices?,
        starred: StoryStarring,
        userId: @escaping @Sendable () async -> String? = { nil },
        prefs: StoryReaderPrefs = StoryReaderPrefs()
    ) {
        self.unitKey = unitKey
        self.skillKey = skillKey
        self.services = services
        self.starred = starred
        self.userIdSource = userId
        self.prefs = prefs
    }

    /// Loads the chapter once; later calls do nothing.
    public func load() async {
        if loadStarted { return }
        loadStarted = true
        guard let services = services, let content = await services.load(unitKey, skillKey) else {
            phase = .unavailable
            return
        }
        let user = await userIdSource()
        userId = user
        if let user = user {
            autoscroll = prefs.autoscroll(userId: user)
            speakHoveredWords = prefs.speakHoveredWords(userId: user)
        }
        courseCode = content.courseCode
        title = content.title
        lines = content.lines
        lexemes = content.lexemes
        let map = StoryReaderWords.hintMap(content.lexemes)
        words = content.lines.map { StoryReaderWords.words($0, hintMap: map) }
        let base = services.makePlayer(content.courseCode, content.courseVersion) ?? SilentStoryClipPlayer()
        let observed = ObservedStoryClipPlayer(base: base, changed: { [weak self] in
            Task { @MainActor in self?.sync() }
        })
        let made = StoryReaderPlayback(lines: content.lines, player: observed)
        let completion = StoryReaderCompletionTrigger(
            unitKey: unitKey, skillKey: skillKey, courseCode: content.courseCode, submitter: services.submitter)
        made.onReachedEnd = { completion.fire() }
        playback = made
        trigger = completion
        savedTags = Set(starred.starredTags)
        phase = .ready
        sync()
    }

    /// Re-reads the playback after it changed.
    func sync() {
        guard let playback = playback else { return }
        position = playback.position
        isPlaying = playback.isMainPlaying
        playingLine = playback.playingLine
        segments = playback.segments
    }

    public func hasPlayButton(_ index: Int) -> Bool {
        return playback?.hasPlayButton(index) ?? false
    }

    public func toggleMain() {
        playback?.toggleMain()
        sync()
    }

    public func playLine(_ index: Int) {
        playback?.playLine(index)
        sync()
    }

    public func seek(to index: Int) {
        playback?.seek(to: index)
        sync()
    }

    /// Leaving the screen, or opening a lesson over it.
    public func stop() {
        playback?.stopAll()
        sync()
    }

    /// The line the autoscroll keeps in view while the chain plays: the playing line, only with the setting on.
    public var followedLine: Int? {
        guard autoscroll, isPlaying, lines.indices.contains(position) else { return nil }
        return position
    }

    public func highlight(_ word: StoryLineWord) -> StoryWordHighlight {
        guard word.isWord, let tag = word.tag else { return .none }
        return StoryWords.highlight(tag: tag, saved: savedTags, lexemes: lexemes)
    }

    /// Tapping a word shows its card and speaks it when the setting is on and the main audio is not playing.
    public func tapWord(_ word: StoryLineWord) {
        guard word.isTappable, let hint = word.hint else { return }
        if StoryWords.canSpeakWord(speakHoveredWords: speakHoveredWords, mainPlaying: isPlaying) {
            services?.speakWord(courseCode, word.text)
        }
        if let tag = word.tag {
            tip = StoryWordTap.make(tag: tag, lexemes: lexemes, starred: starred)
            if tip?.hint.isEmpty == true { tip?.hint = hint }
        } else {
            tip = StoryWordTap(tag: "", hint: hint, isSaved: false, highlight: .none)
        }
        tipText = word.text
    }

    /// The tapped word as written, shown on the card.
    @Published public private(set) var tipText = ""

    public func dismissTip() {
        tip = nil
    }

    public func toggleTipSaved() async {
        guard let current = tip, !current.tag.isEmpty else { return }
        await current.toggleSaved(on: starred)
        savedTags = Set(starred.starredTags)
        tip = StoryWordTap.make(tag: current.tag, lexemes: lexemes, starred: starred)
        if tip?.hint.isEmpty == true { tip?.hint = current.hint }
    }

    /// Whether the completion has been recorded for this open (the stub transport only records it in memory).
    public var completionFired: Bool { return trigger?.hasFired ?? false }
}
