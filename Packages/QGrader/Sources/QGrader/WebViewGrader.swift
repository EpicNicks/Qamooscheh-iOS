#if canImport(QGraderWebKit)
import Foundation
import QGraderWebKit

/// Runs the bundled browser grader in a hidden WKWebView (see QGWebHost, which owns all WebKit use).
/// The bundle is served from a custom scheme so `main.mjs` loads exactly as it does on the web,
/// with the application/wasm MIME type the loader wants.
@MainActor
public final class WebViewGrader: Grader {
    public nonisolated let runtime = GraderRuntime.webView

    private let bundle: GraderBundle
    private let timeout: TimeInterval
    private var host: QGWebHost?
    private var ready = false
    private var failure: GraderError?
    private var waiters: [CheckedContinuation<Void, Error>] = []
    private var started = false
    private var warmed = false
    private var generation = 0

    public init(bundle: GraderBundle, startupTimeout: TimeInterval = 120) {
        self.bundle = bundle
        self.timeout = startupTimeout
    }

    public func shutdown() {
        host?.shutdown()
        host = nil
    }

    private static let indexHTML = """
    <!doctype html><html><head><meta charset="utf-8"></head><body><script type="module">
    const post = (m) => window.webkit.messageHandlers.qgrader.postMessage(m);
    try {
      const mod = await import("./main.mjs");
      window.__qmGrade = (json) => JSON.stringify(JSON.parse(json).map((r) => mod.grader.gradeEnvelope(r)));
      post("ready");
    } catch (e) {
      post("error: " + ((e && e.stack) || e));
    }
    </script></body></html>
    """

    public func warmUp() async throws {
        if warmed { return }
        try await startIfNeeded()
        // The first real call pays for lazy assembly setup; pay it here, as the JSCore host does.
        _ = try await grade([GraderRequest(exerciseType: "TypeIn", scriptMode: "Native", submitted: "a", acceptedAnswers: ["a"])])
        warmed = true
    }

    private func startIfNeeded() async throws {
        if ready { return }
        if let failure { throw failure }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            waiters.append(cont)
            if !started {
                started = true
                start()
            }
        }
    }

    private func start() {
        let bundle = self.bundle
        generation += 1
        let gen = generation
        let host = QGWebHost(
            indexHTML: Self.indexHTML,
            provider: { path in try? bundle.readData(path) },
            onMessage: { [weak self] message in
                // Delivered on the main thread by WebKit.
                MainActor.assumeIsolated {
                    guard let self, self.generation == gen else { return }
                    if message == "ready" {
                        self.settle(nil)
                    } else if message == "error: web content process terminated" {
                        self.handleContentProcessTerminated()
                    } else {
                        self.settle(.startupFailed(message))
                    }
                }
            }
        )
        self.host = host
        host.start()
        let seconds = timeout
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, self.generation == gen else { return }
            self.settle(.startupFailed("timed out after \(Int(seconds)) s"))
        }
    }

    /// WebKit killed the web content process (memory pressure, background). Once the page was ready
    /// the next grade() launches a fresh web view; during startup it is a startup failure.
    func handleContentProcessTerminated() {
        if ready {
            generation += 1
            host?.shutdown()
            host = nil
            ready = false
            started = false
            warmed = false
        } else {
            settle(.startupFailed("web content process terminated"))
        }
    }

    private func settle(_ error: GraderError?) {
        if ready || failure != nil { return }
        if let error { failure = error } else { ready = true }
        let pending = waiters
        waiters = []
        for cont in pending {
            if let error { cont.resume(throwing: error) } else { cont.resume() }
        }
    }

    public func grade(_ requests: [GraderRequest]) async throws -> [GraderResponse] {
        try await startIfNeeded()
        guard let host else { throw GraderError.gradeFailed("web view released") }
        let json = String(decoding: try JSONEncoder().encode(requests), as: UTF8.self)
        let text: String = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            host.gradeJSON(json) { result, error in
                if let result {
                    cont.resume(returning: result)
                } else {
                    cont.resume(throwing: GraderError.gradeFailed(error ?? "unknown"))
                }
            }
        }
        do {
            return try JSONDecoder().decode([GraderResponse].self, from: Data(text.utf8))
        } catch {
            throw GraderError.malformedResponse("\(error)")
        }
    }
}
#endif
