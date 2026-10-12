import XCTest
import QModel
@testable import QDomain

/// Deterministic generator (SplitMix64) so sampling tests are reproducible.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

final class DeepDiveRemixTests: XCTestCase {
    private func lesson(_ id: String, _ score: Int? = nil) -> ThemeLessonRef {
        return ThemeLessonRef(id: id, path: "lessons/\(id).json", commonUsageScore: score)
    }

    private func theme(_ id: String, _ parentId: String?, _ lessonIds: [String]) -> ThemeEntry {
        return ThemeEntry(id: id, parentId: parentId, lessons: lessonIds.map { lesson($0) })
    }

    // Mirrors the web buildRemixPool fixture.
    private var index: ThemeIndexArtifact {
        return ThemeIndexArtifact(themes: [
            theme("Grammar", nil, ["a", "b", "story-1"]),
            theme("Tenses", "Grammar", ["a", "b"]),
            theme("Food", nil, ["b", "c", "unloaded"]),
        ])
    }

    // "unloaded" has no artifact, so its category is nil.
    private let categories: [String: SkillCategory] = ["a": .standard, "b": .standard, "c": .standard, "story-1": .story]

    private func pool(_ themeIds: [String], exclude: String? = nil, noIndex: Bool = false) -> [String] {
        let idx: ThemeIndexArtifact? = noIndex ? nil : index
        return buildRemixPool(themeIndex: idx, categoryOf: { self.categories[$0] }, themeIds: themeIds, excludeLessonKey: exclude).map { $0.id }
    }

    func testPoolUnionsTheGivenThemesLessonsDedupedInFirstSeenOrderStandardOnly() {
        XCTAssertEqual(pool(["Grammar", "Food"]), ["a", "b", "c"])
    }

    func testPoolExcludesTheSourceLessonWhenAsked() {
        XCTAssertEqual(pool(["Grammar", "Food"], exclude: "b"), ["a", "c"])
    }

    func testPoolIgnoresUnknownThemeIdsAndAMissingIndex() {
        XCTAssertEqual(pool(["Nope", "Tenses"]), ["a", "b"])
        XCTAssertEqual(pool(["Grammar"], noIndex: true), [])
    }

    func testPoolLeavesOutLessonsWithUnknownContent() {
        let result = buildRemixPool(themeIndex: index, categoryOf: { _ in nil }, themeIds: ["Food"])
        XCTAssertEqual(result, [])
    }

    func testMasteryAveragesCappedStability() {
        let cards: [String: CardState] = [
            "a": CardState(lexemeTag: "a", stability: 60, difficulty: 5, reviewCount: 1, lapseCount: 0),
            "b": CardState(lexemeTag: "b", stability: 15, difficulty: 5, reviewCount: 1, lapseCount: 0),
        ]
        XCTAssertEqual(computeMasteryScore(cards: cards, tags: ["a", "b", "c"]), (1.0 + 0.5 + 0.0) / 3, accuracy: 1e-9)
        XCTAssertEqual(computeMasteryScore(cards: cards, tags: []), 0)
    }

    func testSelectionTakesDistinctLessonsUpToTheCount() {
        let candidates = (1...10).map { lesson("l\($0)", $0 * 10) }
        var generator = SeededGenerator(seed: 7)
        let picked = selectRemixLessons(candidates: candidates, masteryScore: 0.5, count: 4, using: &generator)
        XCTAssertEqual(picked.count, 4)
        XCTAssertEqual(Set(picked.map { $0.id }).count, 4)
        let few = selectRemixLessons(candidates: Array(candidates.prefix(3)), masteryScore: 0.5, count: 4, using: &generator)
        XCTAssertEqual(few.count, 3)
    }

    func testSelectionWithSystemGeneratorReturnsRequestedCount() {
        let candidates = (1...5).map { lesson("l\($0)", $0 * 10) }
        XCTAssertEqual(selectRemixLessons(candidates: candidates, masteryScore: 0.2, count: 2).count, 2)
        XCTAssertEqual(selectRemixLessons(candidates: [], masteryScore: 0.2, count: 2), [])
    }

    func testBeginnersLeanTowardEverydayLessons() {
        let common = lesson("common", 100)
        let rare = lesson("rare", 0)
        var commonPicks = 0
        for seed in 0..<200 {
            var generator = SeededGenerator(seed: UInt64(seed))
            if selectRemixLessons(candidates: [common, rare], masteryScore: 0, count: 1, using: &generator).first == common {
                commonPicks += 1
            }
        }
        XCTAssertGreaterThan(commonPicks, 180)
    }

    func testStrongLearnersLeanTowardRarerLessons() {
        let common = lesson("common", 100)
        let rare = lesson("rare", 0)
        var rarePicks = 0
        for seed in 0..<200 {
            var generator = SeededGenerator(seed: UInt64(seed))
            if selectRemixLessons(candidates: [common, rare], masteryScore: 1, count: 1, using: &generator).first == rare {
                rarePicks += 1
            }
        }
        XCTAssertGreaterThan(rarePicks, 180)
    }

    func testCaps() {
        XCTAssertEqual(remixMaxLessons, 4)
        XCTAssertEqual(remixMaxExercises, 20)
    }
}
