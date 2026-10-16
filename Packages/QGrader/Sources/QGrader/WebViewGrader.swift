#if canImport(WebKit)
import Foundation
import WebKit

/// Runs the bundled browser grader in a hidden WKWebView. The bundle is served from a
/// custom scheme (qgrader://grader/) so `main.mjs` loads exactly as it does on the web,
/// with the application/wasm MIME type the loader wants.
@MainActor
public final class WebViewGrader: NSObject, Grader, WKScriptMessageHandler, WKURLSchemeHandler {
    public nonisolated let runtime = GraderRuntime.webView

    private let bundle: GraderBundle
    private let timeout: TimeInterval
    private var webView: WKWebView?
    private var ready = false
    private var failure: GraderError?
    private var waiters: [CheckedContinuation<Void, Error>] = []
    private var started = false
    private var warmed = false
    private(set) public var diagnostics: [String] = []

    public init(bundle: GraderBundle, startupTimeout: TimeInterval = 120) {
        self.bundle = bundle
        self.timeout = startupTimeout
        super.init()
    }

    public func shutdown() {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "qgrader")
        webView?.stopLoading()
        webView = nil
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
        try await warmUpStartOnly()
        // The first real call pays for lazy assembly setup; pay it here, as the JSCore host does.
        _ = try await grade([GraderRequest(exerciseType: "TypeIn", scriptMode: "Native", submitted: "a", acceptedAnswers: ["a"])])
        warmed = true
    }

    private func start() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(self, forURLScheme: "qgrader")
        config.userContentController.add(self, name: "qgrader")
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        webView = view
        view.load(URLRequest(url: URL(string: "qgrader://grader/index.html")!))
        Task { [weak self, timeout] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            self?.settle(.startupFailed("timed out after \(Int(timeout)) s"))
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

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let text = message.body as? String else { return }
        if text == "ready" {
            settle(nil)
        } else {
            settle(.startupFailed(text))
        }
    }

    public func grade(_ requests: [GraderRequest]) async throws -> [GraderResponse] {
        if !ready { try await warmUpStartOnly() }
        guard let webView else { throw GraderError.gradeFailed("web view released") }
        let encoded = try JSONEncoder().encode(requests)
        let json = String(decoding: encoded, as: UTF8.self)
        let value: Any?
        do {
            value = try await webView.callAsyncJavaScript(
                "return window.__qmGrade(json);",
                arguments: ["json": json],
                in: nil,
                contentWorld: .page
            )
        } catch {
            throw GraderError.gradeFailed("\(error)")
        }
        guard let text = value as? String else { throw GraderError.malformedResponse("non-string result") }
        do {
            return try JSONDecoder().decode([GraderResponse].self, from: Data(text.utf8))
        } catch {
            throw GraderError.malformedResponse("\(error)")
        }
    }

    private func warmUpStartOnly() async throws {
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

    // MARK: WKURLSchemeHandler

    public func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        var path = url.path
        if path.hasPrefix("/") { path.removeFirst() }
        let data: Data
        if path == "index.html" {
            data = Data(Self.indexHTML.utf8)
        } else if let file = try? bundle.readData(path) {
            data = file
        } else {
            diagnostics.append("404 \(path)")
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didFinish()
            return
        }
        let headers = [
            "Content-Type": Self.mimeType(path),
            "Content-Length": String(data.count),
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "no-store",
        ]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    public func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    private static func mimeType(_ path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "html": return "text/html"
        case "js", "mjs": return "text/javascript"
        case "wasm": return "application/wasm"
        case "json": return "application/json"
        default: return "application/octet-stream"
        }
    }
}
#endif
