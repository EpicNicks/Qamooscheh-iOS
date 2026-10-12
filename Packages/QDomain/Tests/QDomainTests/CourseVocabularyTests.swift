import XCTest
import QModel
@testable import QDomain

final class CourseVocabularyTests: XCTestCase {
    private func exercise(_ tags: String...) -> ExerciseArtifact {
        ExerciseArtifact(type: .typeIn, scriptMode: .native, prompt: "p", answer: ["a"], tags: tags)
    }

    private func ref(_ id: String) -> ManifestRef { ManifestRef(id: id, path: "\(id).json") }

    private var units: [UnitArtifact] {
        [
            UnitArtifact(id: "u1", title: "Greetings", positions: [UnitPosition(skills: [ref("a")]), UnitPosition(skills: [ref("b"), ref("s")])]),
            UnitArtifact(id: "u2", title: "Food", positions: [UnitPosition(skills: [ref("c")])]),
        ]
    }

    private var skills: [String: SkillArtifact] {
        [
            "u1/a": SkillArtifact(id: "a", title: "Hello", exercises: [exercise("salam", "khoda"), exercise("salam")]),
            "u1/b": SkillArtifact(id: "b", title: "Thanks", exercises: [exercise("merci", "salam")]),
            "u1/s": SkillArtifact(id: "s", title: "At the caf\u{00E9}", category: .story, exercises: [exercise("ghahve")]),
            "u2/c": SkillArtifact(id: "c", title: "Bread", exercises: [exercise("nan", "merci")]),
        ]
    }

    private var vocab: [UnitVocab] { buildCourseVocabulary(units: units, skills: skills) }

    func testLessonTagsAreDedupedInFirstOccurrenceOrder() {
        XCTAssertEqual(lessonVocab(vocab, unitKey: "u1", skillKey: "a")?.tags, ["salam", "khoda"])
        XCTAssertEqual(lessonVocab(vocab, unitKey: "u1", skillKey: "a")?.title, "Hello")
    }

    func testStoriesCountAsVocabularyToo() {
        XCTAssertEqual(lessonVocab(vocab, unitKey: "u1", skillKey: "s")?.tags, ["ghahve"])
    }

    func testUnitVocabIsUnionOfLessonsInOrder() {
        XCTAssertEqual(unitVocabTags(vocab, unitKey: "u1"), ["salam", "khoda", "merci", "ghahve"])
    }

    func testCourseVocabIsUnionOfEveryUnitInOrder() {
        XCTAssertEqual(courseVocabTags(vocab), ["salam", "khoda", "merci", "ghahve", "nan"])
    }

    func testUnknownKeysFindNothing() {
        XCTAssertNil(lessonVocab(vocab, unitKey: "u1", skillKey: "zzz"))
        XCTAssertEqual(unitVocabTags(vocab, unitKey: "nope"), [])
    }

    func testSkillThatDidNotLoadKeepsIdAndContributesNothing() {
        var partial = skills
        partial.removeValue(forKey: "u1/b")
        let built = buildCourseVocabulary(units: units, skills: partial)
        XCTAssertEqual(lessonVocab(built, unitKey: "u1", skillKey: "b"), LessonVocab(unitKey: "u1", skillKey: "b", title: "b", tags: []))
    }
}
