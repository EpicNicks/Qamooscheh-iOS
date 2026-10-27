import XCTest
import QModel
@testable import QDomain

/// backend tools/Qamooscheh.GraderBuilder/verify/xp-vectors.json (21 Persian rows), embedded so no runtime file read is needed.
private let xpVectorsJSON = #"""
[
  {"name": "right first time", "verdict": "Correct", "attempt": 1, "usedHint": false, "retype": false, "retypeNumber": 1, "xp": 10, "xpBase": 10, "xpReasons": ["first_try"], "xpLines": ["Right first time"]},
  {"name": "missing half-space accepted with a correction first time", "verdict": "AcceptedWithCorrection", "attempt": 1, "usedHint": false, "retype": false, "retypeNumber": 1, "xp": 7, "xpBase": 7, "xpReasons": ["corrected"], "xpLines": ["Accepted with a correction"]},
  {"name": "accepted with a correction first time", "verdict": "AcceptedWithCorrection", "attempt": 1, "usedHint": false, "retype": false, "retypeNumber": 1, "xp": 7, "xpBase": 7, "xpReasons": ["corrected"], "xpLines": ["Accepted with a correction"]},
  {"name": "right on a requeue", "verdict": "Correct", "attempt": 2, "usedHint": false, "retype": false, "retypeNumber": 1, "xp": 3, "xpBase": 3, "xpReasons": ["retry"], "xpLines": ["Right on a retry"]},
  {"name": "right on a later requeue", "verdict": "Correct", "attempt": 5, "usedHint": false, "retype": false, "retypeNumber": 1, "xp": 3, "xpBase": 3, "xpReasons": ["retry"], "xpLines": ["Right on a retry"]},
  {"name": "accepted with a correction on a requeue", "verdict": "AcceptedWithCorrection", "attempt": 3, "usedHint": false, "retype": false, "retypeNumber": 1, "xp": 3, "xpBase": 3, "xpReasons": ["retry"], "xpLines": ["Right on a retry"]},
  {"name": "correct retype", "verdict": "Correct", "attempt": 1, "usedHint": false, "retype": true, "retypeNumber": 1, "xp": 2, "xpBase": 2, "xpReasons": ["retype"], "xpLines": ["Retyped the answer"]},
  {"name": "retype accepted with a correction", "verdict": "AcceptedWithCorrection", "attempt": 1, "usedHint": false, "retype": true, "retypeNumber": 1, "xp": 2, "xpBase": 2, "xpReasons": ["retype"], "xpLines": ["Retyped the answer"]},
  {"name": "retype on a requeue", "verdict": "Correct", "attempt": 2, "usedHint": false, "retype": true, "retypeNumber": 1, "xp": 2, "xpBase": 2, "xpReasons": ["retype"], "xpLines": ["Retyped the answer"]},
  {"name": "second correct retype", "verdict": "Correct", "attempt": 2, "usedHint": false, "retype": true, "retypeNumber": 2, "xp": 1, "xpBase": 1, "xpReasons": ["second_retype"], "xpLines": ["Retyped it again"]},
  {"name": "second retype accepted with a correction", "verdict": "AcceptedWithCorrection", "attempt": 3, "usedHint": false, "retype": true, "retypeNumber": 2, "xp": 1, "xpBase": 1, "xpReasons": ["second_retype"], "xpLines": ["Retyped it again"]},
  {"name": "third correct retype", "verdict": "Correct", "attempt": 3, "usedHint": false, "retype": true, "retypeNumber": 3, "xp": 0, "xpBase": 0, "xpReasons": [], "xpLines": []},
  {"name": "wrong", "verdict": "Incorrect", "attempt": 1, "usedHint": false, "retype": false, "retypeNumber": 1, "xp": 0, "xpBase": 0, "xpReasons": [], "xpLines": []},
  {"name": "wrong on a requeue with a hint", "verdict": "Incorrect", "attempt": 2, "usedHint": true, "retype": false, "retypeNumber": 1, "xp": 0, "xpBase": 0, "xpReasons": [], "xpLines": []},
  {"name": "wrong retype", "verdict": "Incorrect", "attempt": 1, "usedHint": false, "retype": true, "retypeNumber": 1, "xp": 0, "xpBase": 0, "xpReasons": [], "xpLines": []},
  {"name": "hinted right first time", "verdict": "Correct", "attempt": 1, "usedHint": true, "retype": false, "retypeNumber": 1, "xp": 5, "xpBase": 10, "xpReasons": ["first_try", "hint_halved"], "xpLines": ["Right first time", "You used a hint, so it's half the XP"]},
  {"name": "hinted accepted with a correction", "verdict": "AcceptedWithCorrection", "attempt": 1, "usedHint": true, "retype": false, "retypeNumber": 1, "xp": 4, "xpBase": 7, "xpReasons": ["corrected", "hint_halved"], "xpLines": ["Accepted with a correction", "You used a hint, so it's half the XP"]},
  {"name": "hinted right on a requeue", "verdict": "Correct", "attempt": 2, "usedHint": true, "retype": false, "retypeNumber": 1, "xp": 2, "xpBase": 3, "xpReasons": ["retry", "hint_halved"], "xpLines": ["Right on a retry", "You used a hint, so it's half the XP"]},
  {"name": "hinted accepted on a requeue", "verdict": "AcceptedWithCorrection", "attempt": 2, "usedHint": true, "retype": false, "retypeNumber": 1, "xp": 2, "xpBase": 3, "xpReasons": ["retry", "hint_halved"], "xpLines": ["Right on a retry", "You used a hint, so it's half the XP"]},
  {"name": "hinted retype", "verdict": "Correct", "attempt": 1, "usedHint": true, "retype": true, "retypeNumber": 1, "xp": 1, "xpBase": 2, "xpReasons": ["retype", "hint_halved"], "xpLines": ["Retyped the answer", "You used a hint, so it's half the XP"]},
  {"name": "hinted second retype", "verdict": "Correct", "attempt": 2, "usedHint": true, "retype": true, "retypeNumber": 2, "xp": 1, "xpBase": 1, "xpReasons": ["second_retype"], "xpLines": ["Retyped it again"]}
]
"""#

private struct XpRow: Decodable {
    let name: String
    let verdict: String
    let attempt: Int
    let usedHint: Bool
    let retype: Bool
    let retypeNumber: Int
    let xp: Int
    let xpBase: Int
    let xpReasons: [String]
    let xpLines: [String]
}

private final class RowGrader: Grader {
    let response: GraderResponse
    init(_ response: GraderResponse) { self.response = response }
    func gradeEnvelope(_ request: GraderRequest) -> GraderResponse { response }
    func xp(verdict: String, attempt: Int, usedHint: Bool, retype: Bool, retypeNumber: Int?) -> Int { response.xp ?? 0 }
}

final class XpReasonTextTests: XCTestCase {
    private func rows() throws -> [XpRow] {
        return try JSONDecoder().decode([XpRow].self, from: Data(xpVectorsJSON.utf8))
    }

    func testEveryVectorRowFlowsThroughFeedbackAndLinesPassThroughInOrder() throws {
        let all = try rows()
        XCTAssertEqual(all.count, 21)
        for row in all {
            let response = GraderResponse(verdict: row.verdict, matchedAnswer: "x", correct: row.verdict == "Correct", acceptedWithCorrection: row.verdict == "AcceptedWithCorrection", xp: row.xp, xpBase: row.xpBase, xpReasons: row.xpReasons, xpLines: row.xpLines)
            let ex = GradedExercise(type: .typeIn, scriptMode: .native, answer: ["x"])
            let feedback = checkAnswer(RowGrader(response), courseCode: "fa", exercise: ex, submittedText: "x")
            XCTAssertEqual(feedback.xp, row.xp, row.name)
            XCTAssertEqual(feedback.xpBase, row.xpBase, row.name)
            XCTAssertEqual(feedback.xpReasons, row.xpReasons, row.name)
            XCTAssertEqual(feedback.xpLines, row.xpLines, row.name)
            XCTAssertTrue(feedback.gradedXp, row.name)
            XCTAssertEqual(feedback.xpExplanation, row.xpLines, row.name)
            XCTAssertEqual(XpReasonText.lines(reasons: row.xpReasons, lines: row.xpLines), row.xpLines, row.name)
        }
    }

    func testEveryVectorCodeIsKnown() throws {
        for row in try rows() {
            for code in row.xpReasons { XCTAssertTrue(XpReasonText.knownCodes.contains(code), "\(row.name): \(code)") }
        }
    }

    func testUnknownCodeFallsBack() {
        XCTAssertEqual(XpReasonText.lines(reasons: ["first_try", "brand_new"], lines: ["Right first time", "Something new"]), ["Right first time", XpReasonCopy.fallbackLine])
    }

    func testShortOrEmptyLinesFallBackPerEntry() {
        XCTAssertEqual(XpReasonText.lines(reasons: ["retry", "hint_halved"], lines: ["Right on a retry"]), ["Right on a retry", XpReasonCopy.fallbackLine])
        XCTAssertEqual(XpReasonText.lines(reasons: ["retry"], lines: [""]), [XpReasonCopy.fallbackLine])
    }

    func testAbsentLinesYieldNoLine() {
        XCTAssertEqual(XpReasonText.lines(reasons: ["first_try"], lines: nil), [])
        XCTAssertEqual(XpReasonText.lines(reasons: nil, lines: nil), [])
        XCTAssertEqual(XpReasonText.lines(reasons: [], lines: []), [])
    }

    func testOlderGraderResponseLeavesFeedbackUnpriced() {
        let ex = GradedExercise(type: .typeIn, scriptMode: .native, answer: ["x"])
        let feedback = checkAnswer(RowGrader(GraderResponse(verdict: "Correct", matchedAnswer: "x", correct: true, xp: 10)), courseCode: "fa", exercise: ex, submittedText: "x")
        XCTAssertNil(feedback.xpBase)
        XCTAssertNil(feedback.xpReasons)
        XCTAssertFalse(feedback.gradedXp)
        XCTAssertEqual(feedback.xpExplanation, [])
    }
}
