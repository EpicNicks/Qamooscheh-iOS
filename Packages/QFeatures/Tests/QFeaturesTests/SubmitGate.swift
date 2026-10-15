import Foundation

/// Deterministic suspension point for tests: the stub calls `pass()` and suspends
/// until the test calls `release()`; the test awaits `waitUntilEntered()` first.
actor SubmitGate {
    private var entered = false
    private var released = false
    private var enterWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func pass() async {
        entered = true
        let waiting = enterWaiters
        enterWaiters = []
        for waiter in waiting { waiter.resume() }
        if released { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            releaseWaiters.append(cont)
        }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            enterWaiters.append(cont)
        }
    }

    func release() {
        released = true
        let waiting = releaseWaiters
        releaseWaiters = []
        for waiter in waiting { waiter.resume() }
    }
}
