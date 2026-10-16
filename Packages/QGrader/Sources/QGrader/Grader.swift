import Foundation

/// Which engine is behind a Grader. Feature code never branches on this; it is for diagnostics.
public enum GraderRuntime: String, Sendable {
    case javaScriptCore
    case webView
    case fake
}

public enum GraderError: Error, Equatable, Sendable {
    case bundleMissing(String)
    case integrity(String)
    case startupFailed(String)
    case gradeFailed(String)
    case malformedResponse(String)
}

/// Copied from Android SPEC 4.5: batch-native, so every runtime shares one contract.
/// M5 code depends on this protocol only and injects a fake in tests.
public protocol Grader: Sendable {
    var runtime: GraderRuntime { get }
    func warmUp() async throws
    func grade(_ requests: [GraderRequest]) async throws -> [GraderResponse]
}

public extension Grader {
    func grade(_ request: GraderRequest) async throws -> GraderResponse {
        let out = try await grade([request])
        guard let first = out.first, out.count == 1 else {
            throw GraderError.malformedResponse("expected 1 response, got \(out.count)")
        }
        return first
    }
}

/// Uses `primary`; if it cannot start, uses `fallback` for the rest of its life.
public final class FallbackGrader: Grader, @unchecked Sendable {
    private let primary: any Grader
    private let fallback: any Grader
    private let lock = NSLock()
    private var chosen: (any Grader)?

    public init(primary: any Grader, fallback: any Grader) {
        self.primary = primary
        self.fallback = fallback
    }

    public var runtime: GraderRuntime {
        lock.lock()
        defer { lock.unlock() }
        return (chosen ?? primary).runtime
    }

    private func resolve() async throws -> any Grader {
        lock.lock()
        let existing = chosen
        lock.unlock()
        if let existing { return existing }
        var pick: any Grader = primary
        do {
            try await primary.warmUp()
        } catch {
            try await fallback.warmUp()
            pick = fallback
        }
        lock.lock()
        chosen = pick
        lock.unlock()
        return pick
    }

    public func warmUp() async throws {
        _ = try await resolve()
    }

    public func grade(_ requests: [GraderRequest]) async throws -> [GraderResponse] {
        try await resolve().grade(requests)
    }
}
