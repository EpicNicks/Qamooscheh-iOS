import XCTest
import QModel
@testable import QDomain

final class ThemeTreeTests: XCTestCase {
    private func theme(_ id: String, _ parentId: String?, _ lessons: [String]) -> ThemeEntry {
        return ThemeEntry(id: id, parentId: parentId, lessons: lessons.map { ThemeLessonRef(id: $0, path: "lessons/\($0).json") })
    }

    // Grammar > Tenses > (Past, Present); Grammar > Plurals; Food (root) > Restaurant.
    // lessons is rolled up the way the backend publishes it.
    private var themes: [ThemeEntry] {
        return [
            theme("Grammar", nil, ["past-1", "present-1", "plural-1", "shared"]),
            theme("Food", nil, ["menu-1", "shared"]),
            theme("Tenses", "Grammar", ["past-1", "present-1", "shared"]),
            theme("Past", "Tenses", ["past-1", "shared"]),
            theme("Present", "Tenses", ["present-1"]),
            theme("Plurals", "Grammar", ["plural-1"]),
            theme("Restaurant", "Food", ["menu-1", "shared"]),
        ]
    }
    private var index: ThemeIndexArtifact { return ThemeIndexArtifact(themes: themes) }

    /// Leaves as ids, parents as "id[child,child]".
    private func shape(_ nodes: [ThemeNode]) -> [String] {
        return nodes.map { node in
            node.children.isEmpty ? node.theme.id : "\(node.theme.id)[\(shape(node.children).joined(separator: ","))]"
        }
    }

    private func pairs(_ list: [ThemeAtDepth]) -> [String] {
        return list.map { "\($0.theme.id):\($0.depth)" }
    }

    private func ids(_ list: [ThemeEntry]) -> [String] {
        return list.map { $0.id }
    }

    // buildThemeForest

    func testForestNestsChildrenUnderParentsInThemesJsonOrder() {
        XCTAssertEqual(shape(buildThemeForest(themes)), ["Grammar[Tenses[Past,Present],Plurals]", "Food[Restaurant]"])
    }

    func testForestTreatsAnOrphanParentIdAsARootInsteadOfDroppingIt() {
        let forest = buildThemeForest([theme("A", nil, []), theme("Lost", "Missing", []), theme("Child", "Lost", [])])
        XCTAssertEqual(shape(forest), ["A", "Lost[Child]"])
    }

    func testForestIsEmptyForNoThemes() {
        XCTAssertEqual(buildThemeForest([]), [])
    }

    func testForestOmitsNodesOnlyReachableThroughACycle() {
        XCTAssertEqual(shape(buildThemeForest([theme("A", "B", []), theme("B", "A", [])])), [])
    }

    // indexThemesById / childrenOf

    func testIndexesEveryEntryById() {
        let byId = indexThemesById(themes)
        XCTAssertEqual(byId.count, themes.count)
        XCTAssertEqual(byId["Past"]?.parentId, "Tenses")
    }

    func testChildrenOfListsDirectChildrenOnlyAndNilListsRootsOrphansIncluded() {
        XCTAssertEqual(ids(childrenOf(themes, parentId: "Tenses")), ["Past", "Present"])
        XCTAssertEqual(childrenOf(themes, parentId: "Past"), [])
        XCTAssertEqual(ids(childrenOf(themes + [theme("Lost", "Missing", [])], parentId: nil)), ["Grammar", "Food", "Lost"])
    }

    // rootThemesForLesson

    func testRootThemesAreOnlyTopLevelTagsDespiteRollup() {
        XCTAssertEqual(ids(rootThemesForLesson(index, lessonKey: "past-1")), ["Grammar"])
        XCTAssertEqual(ids(rootThemesForLesson(index, lessonKey: "shared")), ["Grammar", "Food"])
    }

    func testRootThemesHandleAMissingIndexOrUnknownLesson() {
        XCTAssertEqual(rootThemesForLesson(nil, lessonKey: "past-1"), [])
        XCTAssertEqual(rootThemesForLesson(index, lessonKey: "nope"), [])
    }

    // dfsThemesForLesson

    func testDfsOrdersEveryTaggedThemeInPreOrderWithOneBasedDepth() {
        XCTAssertEqual(pairs(dfsThemesForLesson(index, lessonKey: "shared")), ["Grammar:1", "Tenses:2", "Past:3", "Food:1", "Restaurant:2"])
    }

    func testDfsIsPreOrderEvenWhenChildrenPrecedeParentsInThemesJson() {
        let reversed = ThemeIndexArtifact(themes: Array(themes.reversed()))
        XCTAssertEqual(pairs(dfsThemesForLesson(reversed, lessonKey: "past-1")), ["Grammar:1", "Tenses:2", "Past:3"])
    }

    func testDfsKeepsATaggedNodeWhoseAncestorIsNotTaggedAtItsTrueDepth() {
        let sparse = ThemeIndexArtifact(themes: [theme("Grammar", nil, []), theme("Tenses", "Grammar", []), theme("Past", "Tenses", ["x"])])
        XCTAssertEqual(pairs(dfsThemesForLesson(sparse, lessonKey: "x")), ["Past:3"])
    }

    func testDfsIsEmptyForAMissingIndexOrUntaggedLesson() {
        XCTAssertEqual(dfsThemesForLesson(nil, lessonKey: "past-1"), [])
        XCTAssertEqual(dfsThemesForLesson(index, lessonKey: "nope"), [])
    }

    // ancestorsOf

    func testAncestorsAreTheRootToIdChainInclusive() {
        XCTAssertEqual(ids(ancestorsOf(index, id: "Past")), ["Grammar", "Tenses", "Past"])
        XCTAssertEqual(ids(ancestorsOf(index, id: "Food")), ["Food"])
    }

    func testAncestorsStopAtAnUnknownIdAMissingParentOrACycle() {
        XCTAssertEqual(ancestorsOf(index, id: "nope"), [])
        XCTAssertEqual(ids(ancestorsOf(ThemeIndexArtifact(themes: [theme("Lost", "Missing", [])]), id: "Lost")), ["Lost"])
        let cyclic = ThemeIndexArtifact(themes: [theme("A", "B", []), theme("B", "A", [])])
        XCTAssertEqual(ids(ancestorsOf(cyclic, id: "A")), ["B", "A"])
    }

    func testAncestorsOfAMissingIndexIsEmpty() {
        XCTAssertEqual(ancestorsOf(nil, id: "Past"), [])
    }

    // dfsAllThemes

    func testDfsAllThemesWalksTheWholeTreeInPreOrderWithOneBasedDepth() {
        XCTAssertEqual(
            pairs(dfsAllThemes(themes)),
            ["Grammar:1", "Tenses:2", "Past:3", "Present:3", "Plurals:2", "Food:1", "Restaurant:2"]
        )
    }

    func testDfsAllThemesReturnsPlainEntriesAndTreatsOrphansAsRoots() {
        let result = dfsAllThemes([theme("Lost", "Missing", ["x"]), theme("Child", "Lost", [])])
        XCTAssertEqual(pairs(result), ["Lost:1", "Child:2"])
        XCTAssertEqual(result[0].theme, theme("Lost", "Missing", ["x"]))
    }

    func testDfsAllThemesIsEmptyForNoThemes() {
        XCTAssertEqual(dfsAllThemes([]), [])
    }

    // subtreeIds

    func testSubtreeIsTheIdPlusEveryDescendantPreOrder() {
        XCTAssertEqual(subtreeIds(themes, rootId: "Grammar"), ["Grammar", "Tenses", "Past", "Present", "Plurals"])
        XCTAssertEqual(subtreeIds(themes, rootId: "Tenses"), ["Tenses", "Past", "Present"])
    }

    func testSubtreeOfALeafIsJustTheId() {
        XCTAssertEqual(subtreeIds(themes, rootId: "Past"), ["Past"])
    }

    func testSubtreeOfAnUnknownIdIsEmpty() {
        XCTAssertEqual(subtreeIds(themes, rootId: "nope"), [])
    }

    func testSubtreeDoesNotLoopForeverOnAParentIdCycle() {
        XCTAssertEqual(subtreeIds([theme("A", "B", []), theme("B", "A", [])], rootId: "A"), ["A", "B"])
    }
}
