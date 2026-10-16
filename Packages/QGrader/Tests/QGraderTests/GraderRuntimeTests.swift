import XCTest
@testable import QGrader

#if canImport(JavaScriptCore)
final class JSCoreGraderTests: XCTestCase {
    func testFixturesOnJavaScriptCore() async throws {
        let grader = JSCoreGrader(bundle: try GraderBundle.bundled(language: "fa"))
        defer { grader.shutdown() }
        do {
            let problems = try await runFixtureSuite(grader, label: "fa-v\(try GraderBundle.bundled().version)")
            XCTAssertEqual(problems, [])
        } catch {
            print("QGRADER-SPIKE runtime=javaScriptCore FAILED \(error) diagnostics=\(grader.diagnostics)")
            throw error
        }
    }
}
#endif

#if canImport(WebKit)
final class WebViewGraderTests: XCTestCase {
    @MainActor
    func testFixturesOnWebView() async throws {
        let grader = WebViewGrader(bundle: try GraderBundle.bundled(language: "fa"))
        defer { grader.shutdown() }
        do {
            let problems = try await runFixtureSuite(grader, label: "fa-v\(try GraderBundle.bundled().version)")
            XCTAssertEqual(problems, [])
        } catch {
            print("QGRADER-SPIKE runtime=webView FAILED \(error) diagnostics=\(grader.diagnostics)")
            throw error
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
