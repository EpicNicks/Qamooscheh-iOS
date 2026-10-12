import Foundation

// When a word's hint closes after the pointer leaves it. The hint sits a few
// points off the word, and the learner may want to reach it (its "Verb forms"
// entry), so the pointer is given a moment to cross the gap before the hint
// goes: leaving cancels nothing at once, entering the word OR the hint again
// within the delay keeps it open. Port of web hintHover.ts.

/// Long enough to cross the gap between the word and its hint, short enough not to feel stuck.
public let hintCloseDelayMs = 150

/// Starts a one-shot timer and returns the function that cancels it. Injectable so tests drive time by hand.
public typealias HoverTimerStart = (_ delayMs: Int, _ fire: @escaping () -> Void) -> () -> Void

public final class HoverCloser {
    private let setHovered: (Bool) -> Void
    private let delayMs: Int
    private let startTimer: HoverTimerStart
    private var cancelTimer: (() -> Void)?

    public init(
        delayMs: Int = hintCloseDelayMs,
        startTimer: @escaping HoverTimerStart = HoverCloser.mainQueueTimer,
        setHovered: @escaping (Bool) -> Void
    ) {
        self.setHovered = setHovered
        self.delayMs = delayMs
        self.startTimer = startTimer
    }

    /// The pointer is over the word or the hint: opens now, and cancels a pending close.
    public func enter() {
        cancel()
        setHovered(true)
    }

    /// The pointer left the word and the hint: closes after the delay unless it comes back.
    public func leave() {
        cancel()
        cancelTimer = startTimer(delayMs) { [weak self] in
            guard let self = self else { return }
            self.cancelTimer = nil
            self.setHovered(false)
        }
    }

    /// Closes now, dropping a pending close: a dismissal, or the word going away.
    public func close() {
        cancel()
        setHovered(false)
    }

    private func cancel() {
        cancelTimer?()
        cancelTimer = nil
    }

    public static func mainQueueTimer(_ delayMs: Int, _ fire: @escaping () -> Void) -> () -> Void {
        let item = DispatchWorkItem(block: fire)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs), execute: item)
        return { item.cancel() }
    }
}

public func createHoverCloser(
    delayMs: Int = hintCloseDelayMs,
    startTimer: @escaping HoverTimerStart = HoverCloser.mainQueueTimer,
    setHovered: @escaping (Bool) -> Void
) -> HoverCloser {
    return HoverCloser(delayMs: delayMs, startTimer: startTimer, setHovered: setHovered)
}
