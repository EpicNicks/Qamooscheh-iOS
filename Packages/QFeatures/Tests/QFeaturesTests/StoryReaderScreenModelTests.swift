import XCTest
import QModel
import QDomain
@testable import QFeatures

@MainActor
private final class ScreenStars: StoryStarring {
    var starredTags: [String] = []
    func toggleStar(_ tag: String) async {
        if let at = starredTags.firstIndex(of: tag) {
            starredTags.remove(at: at)
        } else {
            starredTags.append(tag)
        }
    }
}

private final class ScreenPlayer: StoryClipPlayer {
    var clips: [String] = []
    var ends: [(PlayEnd) -> Void] = []
    func play(clip: String, onEnd: @escaping (PlayEnd) -> Void) {
        clips.append(clip)
        ends.append(onEnd)
    }
    func stop() {}
    func finishLast() {
        guard let last = ends.popLast() else { return }
        last(.completed)
    }
}

private final class PlayerBox: @unchecked Sendable {
    let player = ScreenPlayer()
}

private func line(_ index: Int, _ text: String, clip: String?, tags: [String] = []) -> StoryReaderLine {
    return StoryReaderLine(
        exerciseIndex: index, text: text, romanization: nil, audio: nil, tags: tags, speaker: nil, clip: clip)
}

final class StoryReaderScreenModelTests: XCTestCase {
    func testWordsCarryTheTaggedSenseAndHint() {
        let lexemes = ["tea": LexemeIndexEntry(gloss: "a drink", romanizationIsAuthored: false)]
        let map = StoryReaderWords.hintMap(lexemes)
        let words = StoryReaderWords.words(line(0, "I drink tea", clip: nil, tags: ["tea"]), hintMap: map)
        XCTAssertEqual(words.map { $0.text }.joined(), "I drink tea")
        let tappable = words.filter { $0.isTappable }
        XCTAssertEqual(tappable.map { $0.text }, ["tea"])
        XCTAssertEqual(tappable.first?.tag, "tea")
        XCTAssertEqual(tappable.first?.hint, "a drink")
    }

    @MainActor
    private func makeModel(box: PlayerBox, stars: ScreenStars, submitter: RecordingStoryReaderCompletionSubmitter) -> StoryReaderModel {
        let content = StoryReaderContent(
            title: "Tea", courseCode: "fa", courseVersion: 1,
            lines: [line(0, "one tea", clip: "a.mp3", tags: ["tea"]), line(1, "two", clip: "b.mp3")],
            lexemes: ["tea": LexemeIndexEntry(gloss: "a drink", romanizationIsAuthored: false)])
        let services = StoryReaderServices(
            load: { _, _ in content }, makePlayer: { _, _ in box.player }, submitter: submitter)
        let suite = "storyscreen-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        return StoryReaderModel(
            unitKey: "u1", skillKey: "s1", services: services, starred: stars,
            userId: { "user" }, prefs: StoryReaderPrefs(defaults: defaults))
    }

    @MainActor
    func testUnavailableWithoutServices() async {
        let model = StoryReaderModel(unitKey: "u", skillKey: "s", services: nil, starred: ScreenStars())
        await model.load()
        XCTAssertEqual(model.phase, .unavailable)
    }

    @MainActor
    func testWordCardSavesAndHighlights() async {
        let stars = ScreenStars()
        let model = makeModel(box: PlayerBox(), stars: stars, submitter: RecordingStoryReaderCompletionSubmitter())
        await model.load()
        XCTAssertEqual(model.phase, .ready)
        let tea = model.words[0].first(where: { $0.isTappable })
        XCTAssertNotNil(tea)
        guard let word = tea else { return }
        XCTAssertEqual(model.highlight(word), .none)
        model.tapWord(word)
        XCTAssertEqual(model.tip?.hint, "a drink")
        XCTAssertEqual(model.tipText, "tea")
        await model.toggleTipSaved()
        XCTAssertEqual(stars.starredTags, ["tea"])
        XCTAssertEqual(model.highlight(word), .saved)
        XCTAssertEqual(model.tip?.isSaved, true)
    }

    @MainActor
    func testChainReachingTheEndRecordsOneCompletion() async {
        let box = PlayerBox()
        let submitter = RecordingStoryReaderCompletionSubmitter()
        let model = makeModel(box: box, stars: ScreenStars(), submitter: submitter)
        await model.load()
        XCTAssertEqual(model.segments, [.current, .upcoming])
        model.toggleMain()
        XCTAssertEqual(box.player.clips, ["a.mp3"])
        XCTAssertTrue(model.isPlaying)
        box.player.finishLast()
        XCTAssertEqual(box.player.clips, ["a.mp3", "b.mp3"])
        model.sync()
        XCTAssertEqual(model.position, 1)
        XCTAssertEqual(model.segments, [.filled, .current])
        box.player.finishLast()
        model.sync()
        XCTAssertEqual(submitter.requests.count, 1)
        XCTAssertEqual(submitter.requests.first?.skillKey, "s1")
        XCTAssertFalse(model.isPlaying)
    }

    @MainActor
    func testFollowedLineNeedsTheSettingAndAPlayingChain() async {
        let box = PlayerBox()
        let model = makeModel(box: box, stars: ScreenStars(), submitter: RecordingStoryReaderCompletionSubmitter())
        await model.load()
        XCTAssertNil(model.followedLine)
        model.toggleMain()
        XCTAssertEqual(model.followedLine, 0)
        model.autoscroll = false
        XCTAssertNil(model.followedLine)
    }
}
