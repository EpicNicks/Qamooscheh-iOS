import XCTest
import QModel
import QNetwork
@testable import QFeatures

private func ref(_ id: String, _ score: Int? = nil) -> ThemeLessonRef {
    return ThemeLessonRef(id: id, path: "p/\(id)", commonUsageScore: score)
}

private func sampleData() -> ThemeLibraryData {
    let index = ThemeIndexArtifact(themes: [
        ThemeEntry(id: "Food", parentId: nil, lessons: [ref("a", 80), ref("b", 50), ref("story1")]),
        ThemeEntry(id: "Drinks", parentId: "Food", lessons: [ref("c", 10)]),
        ThemeEntry(id: "Travel", parentId: nil, lessons: [ref("story2")]),
    ])
    let headers: [String: ThemeLessonHeader] = [
        "a": ThemeLessonHeader(title: "A", category: .standard),
        "b": ThemeLessonHeader(title: "B", category: .standard),
        "c": ThemeLessonHeader(title: "C", category: .standard),
        "story1": ThemeLessonHeader(title: "S1", category: .story),
        "story2": ThemeLessonHeader(title: "S2", category: .story),
    ]
    return ThemeLibraryData(index: index, headers: headers)
}

private final class FakeSource: ThemeLibrarySource, @unchecked Sendable {
    var data: ThemeLibraryData?
    var error: Error?
    var calls = 0
    var during: (@MainActor (Int) async -> Void)?

    func load() async throws -> ThemeLibraryData? {
        calls += 1
        let n = calls
        let snapshot = data
        if let hook = during { await hook(n) }
        if let e = error { throw e }
        return snapshot
    }
}

@MainActor
final class ThemesModelTests: XCTestCase {
    func testTopicSummariesCountOnlyStandardLessons() {
        let ui = makeLibraryTopics(sampleData())
        XCTAssertEqual(ui.topics.map { $0.id }, ["Food", "Travel"])
        XCTAssertEqual(ui.topics.map { $0.lessonCount }, [2, 0])
        XCTAssertEqual(ui.allTopics.map { $0.id }, ["Food", "Drinks", "Travel"])
        XCTAssertEqual(ui.allTopics.map { $0.depth }, [1, 2, 1])
        XCTAssertEqual(ui.allTopics[1].breadcrumb, "Food \u{203A} Drinks")
    }

    func testCommonnessThresholds() {
        XCTAssertEqual(commonnessLabel(70), "Everyday")
        XCTAssertEqual(commonnessLabel(69), "Common")
        XCTAssertEqual(commonnessLabel(40), "Common")
        XCTAssertEqual(commonnessLabel(39), "Specialized")
    }

    func testTopicLessonsFilterAndUnknown() {
        let lessons = makeTopicLessons(themeId: "Food", data: sampleData())
        XCTAssertEqual(lessons?.map { $0.id }, ["a", "b"])
        XCTAssertEqual(lessons?.first?.commonUsageScore, 80)
        XCTAssertNil(makeTopicLessons(themeId: "Nope", data: sampleData()))
    }

    func testLibraryRefreshReady() async {
        let source = FakeSource()
        source.data = sampleData()
        let model = LibraryModel(source: source)
        await model.refresh()
        guard case .ready(let ready) = model.state else { return XCTFail("not ready") }
        XCTAssertEqual(ready.topics.count, 2)
    }

    func testLibraryNoCourse() async {
        let model = LibraryModel(source: FakeSource())
        await model.refresh()
        XCTAssertEqual(model.state, .unavailable("Pick a course to see its library."))
    }

    func testLibraryErrorShownThenKeptOnLaterFailure() async {
        let source = FakeSource()
        source.error = ApiError(status: 500, body: ApiErrorBody(error: "boom"))
        let model = LibraryModel(source: source)
        await model.refresh()
        XCTAssertEqual(model.state, .unavailable("boom"))
        source.error = nil
        source.data = sampleData()
        await model.refresh()
        source.error = ApiError(status: 500, body: ApiErrorBody(error: "boom"))
        await model.refresh()
        if case .ready = model.state {} else { XCTFail("lost topics on a failed reload") }
    }

    func testUnauthorizedReportedEvenWhenSuperseded() async {
        let source = FakeSource()
        source.error = ApiError(status: 401, body: nil)
        let hits = Counter()
        let model = LibraryModel(source: source, onUnauthorized: { hits.bump() })
        source.during = { n in
            if n == 1 {
                source.during = nil
                await model.refresh()
            }
        }
        await model.refresh()
        XCTAssertEqual(hits.value, 2)
    }

    func testStaleLibraryResultDoesNotOverwriteNewer() async {
        let source = FakeSource()
        var old = sampleData()
        old.index.themes = [ThemeEntry(id: "Old", parentId: nil, lessons: [])]
        source.data = old
        let model = LibraryModel(source: source)
        source.during = { n in
            if n == 1 {
                source.data = sampleData()
                source.during = nil
                await model.refresh()
            }
        }
        await model.refresh()
        guard case .ready(let ready) = model.state else { return XCTFail("not ready") }
        XCTAssertEqual(ready.topics.map { $0.id }, ["Food", "Travel"])
    }

    func testTopicRandomReshufflesOnEachSwitchAndSurvivesReload() async {
        let source = FakeSource()
        source.data = sampleData()
        var shuffles = 0
        let model = TopicModel(themeId: "Food", highlighted: "b", source: source, shuffle: { ids in
            shuffles += 1
            return ids.reversed()
        })
        await model.refresh()
        XCTAssertEqual(model.visibleLessons.map { $0.id }, ["a", "b"])
        model.setOrder(.random)
        XCTAssertEqual(model.visibleLessons.map { $0.id }, ["b", "a"])
        // Reappearing must not reshuffle or reset the order.
        await model.refresh()
        XCTAssertEqual(model.order, .random)
        XCTAssertEqual(model.visibleLessons.map { $0.id }, ["b", "a"])
        XCTAssertEqual(shuffles, 1)
        model.setOrder(.structured)
        model.setOrder(.random)
        XCTAssertEqual(shuffles, 2)
    }

    func testTopicUnknownTheme() async {
        let source = FakeSource()
        source.data = sampleData()
        let model = TopicModel(themeId: "Zzz", source: source)
        await model.refresh()
        XCTAssertEqual(model.state, .unavailable("No topic named \"Zzz\"."))
    }

    func testPickerKeepsPickOrderAndSkipsEmptyTopics() {
        let picker = RemixPickerModel(allTopics: makeLibraryTopics(sampleData()).allTopics)
        XCTAssertEqual(picker.topics.map { $0.id }, ["Food", "Drinks"])
        XCTAssertFalse(picker.canStart)
        XCTAssertNil(picker.start())
        XCTAssertEqual(picker.startTitle, "Pick at least one topic")
        picker.toggle("Drinks")
        picker.toggle("Food")
        picker.toggle("Travel")
        XCTAssertEqual(picker.start() ?? [], ["Drinks", "Food"])
        picker.toggle("Drinks")
        XCTAssertEqual(picker.selected, ["Food"])
        XCTAssertEqual(picker.startTitle, "Start remix")
    }

    func testPickerUpdateKeepsPickAndDropsVanishedTopics() {
        let all = makeLibraryTopics(sampleData()).allTopics
        let picker = RemixPickerModel(allTopics: all)
        picker.toggle("Food")
        picker.toggle("Drinks")
        picker.update(allTopics: all.filter { $0.id != "Drinks" })
        XCTAssertEqual(picker.selected, ["Food"])
    }
}

private final class Counter: @unchecked Sendable {
    private(set) var value = 0
    func bump() { value += 1 }
}
