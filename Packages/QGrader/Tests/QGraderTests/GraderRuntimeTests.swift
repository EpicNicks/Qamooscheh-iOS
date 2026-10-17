import XCTest
@testable import QGrader

#if canImport(JavaScriptCore)
import JavaScriptCore

final class JSCoreGraderTests: XCTestCase {
    /// True when this JSContext accepts wasm SIMD, which the .NET loader requires.
    private static func supportsWasmSimd() -> Bool {
        let simd = "0,97,115,109,1,0,0,0,1,5,1,96,0,1,123,3,2,1,0,10,10,1,8,0,65,0,253,15,253,98,11"
        return JSContext()?.evaluateScript("WebAssembly.validate(new Uint8Array([\(simd)]))")?.toBool() ?? false
    }

    func testFixturesOnJavaScriptCore() async throws {
        // The only documented unsupported condition: no wasm SIMD (macOS hosts). Any other
        // startup or grading failure is a real failure and is not skipped.
        guard Self.supportsWasmSimd() else {
            print("QGRADER-SPIKE runtime=javaScriptCore UNSUPPORTED wasm-simd=false")
            throw XCTSkip("JavaScriptCore on this host lacks wasm SIMD (documented unsupported)")
        }
        let grader = JSCoreGrader(bundle: try GraderBundle.bundled(language: "fa"))
        defer { grader.shutdown() }
        let problems = try await runFixtureSuite(grader, label: "fa-v\(try GraderBundle.bundled().version)")
        XCTAssertEqual(problems, [])
    }

    /// Which wasm features this JSContext accepts (wasm-feature-detect probe modules).
    func testJavaScriptCoreWasmFeatureProbe() throws {
        let probes: [(String, String)] = [
            ("simd", "0,97,115,109,1,0,0,0,1,5,1,96,0,1,123,3,2,1,0,10,10,1,8,0,65,0,253,15,253,98,11"),
            ("exceptions-legacy", "0,97,115,109,1,0,0,0,1,4,1,96,0,0,3,2,1,0,10,8,1,6,0,6,64,25,11,11"),
            ("bulk-memory", "0,97,115,109,1,0,0,0,1,4,1,96,0,0,3,2,1,0,5,3,1,0,1,10,14,1,12,0,65,0,65,0,65,0,252,10,0,0,11"),
            ("tail-call", "0,97,115,109,1,0,0,0,1,4,1,96,0,0,3,2,1,0,10,6,1,4,0,18,0,11"),
        ]
        let context = try XCTUnwrap(JSContext())
        var report: [String] = []
        for (name, bytes) in probes {
            let ok = context.evaluateScript("WebAssembly.validate(new Uint8Array([\(bytes)]))")?.toBool() ?? false
            report.append("\(name)=\(ok)")
        }
        print("QGRADER-SPIKE jscore-wasm-features \(report.joined(separator: " "))")
    }
}
#endif

#if canImport(WebKit)
final class WebViewGraderTests: XCTestCase {
    @MainActor
    func testFixturesOnWebView() async throws {
        // The iOS-simulator WKWebView cold start is erratic on shared CI (8 s to never, docs/grader-spike.md):
        // runs 38914372675, 39041546444 and 39042188312 timed out at 120/60/300 s with no vector graded, while the
        // recovery test in the same run started. JavaScriptCore is the shipping runtime, so on the simulator this
        // fixture run is opt-in (QGRADER_WEBVIEW_FIXTURES=1, a separate non-gating CI step). It always runs on
        // macOS hosts and on devices; once it runs, any startup timeout or grading failure fails it.
        #if targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["QGRADER_WEBVIEW_FIXTURES"] == "1" else {
            print("QGRADER-SPIKE runtime=webView SKIPPED simulator-fixtures-opt-in")
            throw XCTSkip("WKWebView fixture run on the iOS simulator is opt-in (QGRADER_WEBVIEW_FIXTURES=1)")
        }
        #endif
        let grader = WebViewGrader(bundle: try GraderBundle.bundled(language: "fa"), startupTimeout: 300)
        defer { grader.shutdown() }
        let problems = try await runFixtureSuite(grader, label: "fa-v\(try GraderBundle.bundled().version)")
        XCTAssertEqual(problems, [])
    }

    /// The web content process dying after ready must not leave the grader dead: the next grade relaunches.
    @MainActor
    func testRecoversAfterContentProcessTermination() async throws {
        let grader = WebViewGrader(bundle: try GraderBundle.bundled(language: "fa"), startupTimeout: 120)
        defer { grader.shutdown() }
        let request = GraderRequest(exerciseType: "TypeIn", scriptMode: "Native", submitted: "a", acceptedAnswers: ["a"])
        try await grader.warmUp()
        let before = try await grader.grade(request)
        grader.handleContentProcessTerminated()
        let after = try await grader.grade(request)
        XCTAssertNotNil(before.verdict)
        XCTAssertEqual(after.verdict, before.verdict)
    }
}
#endif

final class FallbackGraderTests: XCTestCase {
    private struct Failing: Grader {
        let runtime = GraderRuntime.fake
        func warmUp() async throws { throw GraderError.startupFailed("nope") }
        func grade(_ requests: [GraderRequest]) async throws -> [GraderResponse] { throw GraderError.gradeFailed("nope") }
    }

    private struct Fixed: Grader {
        let runtime = GraderRuntime.webView
        func warmUp() async throws {}
        func grade(_ requests: [GraderRequest]) async throws -> [GraderResponse] {
            requests.map { _ in GraderResponse(verdict: "Correct", correct: true) }
        }
    }

    func testFallsBackWhenPrimaryCannotStart() async throws {
        let grader = FallbackGrader(primary: Failing(), fallback: Fixed())
        let r = try await grader.grade(GraderRequest(exerciseType: "TypeIn", scriptMode: "Native", submitted: "a", acceptedAnswers: ["a"]))
        XCTAssertEqual(r.verdict, "Correct")
        XCTAssertEqual(grader.runtime, .webView)
    }
}
