import XCTest
import QModel
@testable import QDomain

final class StoryTranscriptTests: XCTestCase {
    private func exercise(_ type: ExerciseType, prompt: String, answer: [String]) -> ExerciseArtifact {
        ExerciseArtifact(type: type, scriptMode: .native, prompt: prompt, answer: answer)
    }

    private var chapter: StoryChapter {
        StoryChapter(title: "Ch 1", exercises: [
            exercise(.wordBank, prompt: "a", answer: ["x", "y"]),
            exercise(.typeIn, prompt: "b", answer: ["p", "q"]),
            exercise(.match, prompt: "c", answer: ["m", "n"]),
        ])
    }

    func testAnswerTextJoins() {
        XCTAssertEqual(StoryTranscript.answerText(chapter.exercises[0]), "x y")
        XCTAssertEqual(StoryTranscript.answerText(chapter.exercises[1]), "p / q")
        XCTAssertEqual(StoryTranscript.answerText(chapter.exercises[2]), "m n")
    }

    func testLinesShowOnlyThoseBeforeCurrent() {
        XCTAssertEqual(StoryTranscript.lines(chapter, upTo: 0, results: [:]).count, 0)
        let two = StoryTranscript.lines(chapter, upTo: 2, results: [0: true, 1: false])
        XCTAssertEqual(two.map { $0.mark }, [.correct, .incorrect])
        XCTAssertEqual(two.map { $0.ordinal }, [0, 1])
    }

    func testLinesClampAndUnmarked() {
        let all = StoryTranscript.lines(chapter, upTo: 99, results: [:])
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all.map { $0.mark }, [.unmarked, .unmarked, .unmarked])
        XCTAssertEqual(StoryTranscript.lines(chapter, upTo: -1, results: [:]).count, 0)
    }

    func testRecordingKeepsFirstAnswer() {
        var results = StoryTranscript.recording([:], ordinal: 1, verdict: .incorrect)
        XCTAssertEqual(results[1], false)
        results = StoryTranscript.recording(results, ordinal: 1, verdict: .correct)
        XCTAssertEqual(results[1], false)
    }

    func testCountsAsRight() {
        XCTAssertTrue(StoryTranscript.countsAsRight(.correct))
        XCTAssertTrue(StoryTranscript.countsAsRight(.acceptedWithCorrection))
        XCTAssertTrue(StoryTranscript.countsAsRight(.pending))
        XCTAssertFalse(StoryTranscript.countsAsRight(.incorrect))
    }

    func testGlyphAndLabel() {
        XCTAssertEqual(StoryTranscript.glyph(.correct), "\u{2713}")
        XCTAssertEqual(StoryTranscript.glyph(.unmarked), "")
        let line = StoryTranscript.lines(chapter, upTo: 2, results: [1: false])[1]
        XCTAssertEqual(StoryTranscript.accessibilityLabel(line), "Answered incorrectly: b, p / q")
    }
}
