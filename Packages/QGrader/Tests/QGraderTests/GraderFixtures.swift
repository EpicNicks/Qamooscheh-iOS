import Foundation
import XCTest
@testable import QGrader

/// Backend verify vectors (tools/Qamooscheh.GraderBuilder/verify/vectors.json, xp-vectors.json),
/// copied into Fixtures/. Only vectors with `expect` carry exact expected verdicts; the rest
/// must be interpreted (a verdict, no error) except those named "unknown ...", which must be refused.
struct Vector: Decodable {
    struct Expect: Decodable {
        let verdict: String
        let reasons: [String]
        let separatorEdits: [SeparatorEditResponse]?
    }

    let name: String
    let exerciseType: String
    let scriptMode: String
    let submitted: String
    let acceptedAnswers: [String]
    let alternativeAnswers: [[String]]?
    let expect: Expect?

    var request: GraderRequest {
        GraderRequest(
            exerciseType: exerciseType,
            scriptMode: scriptMode,
            submitted: submitted,
            acceptedAnswers: acceptedAnswers,
            alternativeAnswers: alternativeAnswers
        )
    }
}

struct XpVector: Decodable {
    let name: String
    let verdict: String
    let attempt: Int
    let usedHint: Bool
    let retype: Bool
    let retypeNumber: Int
    let xp: Int
}

enum Fixtures {
    static func load<T: Decodable>(_ file: String, as type: T.Type) throws -> T {
        guard let dir = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            throw GraderError.bundleMissing("Fixtures")
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: dir.appendingPathComponent(file)))
    }

    static func vectors() throws -> [Vector] { try load("vectors.json", as: [Vector].self) }
    static func xpVectors() throws -> [XpVector] { try load("xp-vectors.json", as: [XpVector].self) }
}

func percentile(_ sorted: [Double], _ p: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let index = min(sorted.count - 1, Int((Double(sorted.count) * p).rounded(.up)) - 1)
    return sorted[max(0, index)]
}

func nowMs() -> Double {
    Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000
}

/// Runs the whole fixture set against `grader`, prints the timings CI records in docs/grader-spike.md,
/// and returns the mismatches (empty when correct).
func runFixtureSuite(_ grader: any Grader, label: String, iterations: Int = 200) async throws -> [String] {
    var problems: [String] = []

    let t0 = nowMs()
    try await grader.warmUp()
    let warmMs = nowMs() - t0

    let vectors = try Fixtures.vectors()
    var byName: [String: GraderResponse] = [:]
    for v in vectors {
        let r = try await grader.grade(v.request)
        byName[v.name] = r
        if let expect = v.expect {
            if r.verdict != expect.verdict { problems.append("\(v.name): verdict \(r.verdict ?? "nil") != \(expect.verdict)") }
            if r.reasons != expect.reasons { problems.append("\(v.name): reasons \(r.reasons) != \(expect.reasons)") }
            if let edits = expect.separatorEdits, (r.separatorEdits ?? []) != edits {
                problems.append("\(v.name): separatorEdits \(String(describing: r.separatorEdits)) != \(edits)")
            }
        } else if v.name.hasPrefix("unknown ") {
            if r.error == nil { problems.append("\(v.name): expected an error, got \(r)") }
        } else if r.error != nil || r.verdict == nil {
            problems.append("\(v.name): not interpreted: \(r)")
        }
    }

    // XP through the grading call, replaying a vector that earned each row's verdict (as the web verifier does).
    for row in try Fixtures.xpVectors() {
        guard let sample = vectors.first(where: { byName[$0.name]?.verdict == row.verdict }) else {
            problems.append("xp \(row.name): no sample vector with verdict \(row.verdict)")
            continue
        }
        var request = sample.request
        request.attempt = row.attempt
        request.usedHint = row.usedHint
        request.retype = row.retype
        request.retypeNumber = row.retypeNumber
        let r = try await grader.grade(request)
        if r.xp != row.xp { problems.append("xp \(row.name): \(String(describing: r.xp)) != \(row.xp)") }
    }

    // Warm single-answer latency over the interpretable vectors.
    let timed = vectors.filter { !$0.name.hasPrefix("unknown ") }.map(\.request)
    var samples: [Double] = []
    for i in 0..<iterations {
        let request = timed[i % timed.count]
        let s = nowMs()
        _ = try await grader.grade(request)
        samples.append(nowMs() - s)
    }
    samples.sort()

    let batch = vectors.map(\.request)
    let b0 = nowMs()
    _ = try await grader.grade(batch)
    let batchMs = nowMs() - b0

    let line = String(
        format: "QGRADER-SPIKE runtime=%@ label=%@ warmup_ms=%.1f single_p50_ms=%.2f single_p95_ms=%.2f single_max_ms=%.2f n=%d batch%d_ms=%.2f problems=%d",
        grader.runtime.rawValue, label, warmMs, percentile(samples, 0.5), percentile(samples, 0.95),
        samples.last ?? 0, samples.count, batch.count, batchMs, problems.count
    )
    print(line)
    return problems
}
