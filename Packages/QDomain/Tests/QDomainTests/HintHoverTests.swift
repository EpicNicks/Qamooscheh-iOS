import XCTest
@testable import QDomain

// Port of web hintHover.test.ts. Time is driven by hand through an injected timer
// (the web uses fake timers).
private final class FakeClock {
    private var now = 0
    private var nextId = 0
    private var timers: [(id: Int, due: Int, fire: () -> Void)] = []

    func start(_ delayMs: Int, _ fire: @escaping () -> Void) -> () -> Void {
        let id = nextId
        nextId += 1
        timers.append((id: id, due: now + delayMs, fire: fire))
        return { [weak self] in self?.timers.removeAll { $0.id == id } }
    }

    func advance(by ms: Int) {
        let target = now + ms
        while let next = timers.filter({ $0.due <= target }).min(by: { $0.due < $1.due }) {
            timers.removeAll { $0.id == next.id }
            now = next.due
            next.fire()
        }
        now = target
    }
}

final class HintHoverTests: XCTestCase {
    private var states: [Bool] = []
    private var clock = FakeClock()
    private var closer: HoverCloser!

    override func setUp() {
        super.setUp()
        states = []
        clock = FakeClock()
        let clock = self.clock
        closer = createHoverCloser(startTimer: { clock.start($0, $1) }, setHovered: { [unowned self] in self.states.append($0) })
    }

    func testOpensAtOnceOnEnter() {
        closer.enter()
        XCTAssertEqual(states, [true])
    }

    func testClosesOnlyAfterTheDelayOnceThePointerLeaves() {
        closer.enter()
        closer.leave()
        clock.advance(by: hintCloseDelayMs - 1)
        XCTAssertEqual(states, [true])
        clock.advance(by: 1)
        XCTAssertEqual(states, [true, false])
    }

    func testStaysOpenWhenThePointerCrossesToTheHintWithinTheDelay() {
        closer.enter()
        closer.leave()
        clock.advance(by: hintCloseDelayMs / 2)
        closer.enter()
        clock.advance(by: hintCloseDelayMs * 2)
        XCTAssertEqual(states, [true, true])
    }

    func testRestartsTheDelayOnASecondLeave() {
        closer.enter()
        closer.leave()
        clock.advance(by: hintCloseDelayMs - 10)
        closer.leave()
        clock.advance(by: hintCloseDelayMs - 10)
        XCTAssertEqual(states, [true])
        clock.advance(by: 10)
        XCTAssertEqual(states, [true, false])
    }

    func testCloseEndsItNowAndDropsAPendingClose() {
        closer.enter()
        closer.leave()
        closer.close()
        clock.advance(by: hintCloseDelayMs * 2)
        XCTAssertEqual(states, [true, false])
    }

    func testDefaultDelayIs150Ms() {
        XCTAssertEqual(hintCloseDelayMs, 150)
    }
}
