import XCTest
@testable import QGrader

#if canImport(JavaScriptCore)
import JavaScriptCore

final class JSCoreGraderTests: XCTestCase {
    func testFixturesOnJavaScriptCore() async throws {
        let grader = JSCoreGrader(bundle: try GraderBundle.bundled(language: "fa"))
        defer { grader.shutdown() }
        do {
            let problems = try await runFixtureSuite(grader, label: "fa-v\(try GraderBundle.bundled().version)")
            XCTAssertEqual(problems, [])
        } catch let error as GraderError {
            // A runtime that cannot start this build is a spike result, not a test failure.
            print("QGRADER-SPIKE runtime=javaScriptCore UNSUPPORTED \(error) diagnostics=\(grader.diagnostics)")
            throw XCTSkip("JavaScriptCore cannot run this grader build: \(error)")
        }
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
        let grader = WebViewGrader(bundle: try GraderBundle.bundled(language: "fa"), startupTimeout: 60)
        defer { grader.shutdown() }
        do {
            let problems = try await runFixtureSuite(grader, label: "fa-v\(try GraderBundle.bundled().version)")
            XCTAssertEqual(problems, [])
        } catch let error as GraderError {
            print("QGRADER-SPIKE runtime=webView UNSUPPORTED \(error)")
            throw XCTSkip("WKWebView could not start in this test host: \(error)")
        }
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
