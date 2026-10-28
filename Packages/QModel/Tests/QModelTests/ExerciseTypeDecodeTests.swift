import XCTest
@testable import QModel

final class ExerciseTypeDecodeTests: XCTestCase {
    private func skill(_ types: [String]) -> Data {
        let exercises = types.map { "{\"type\":\"\($0)\",\"scriptMode\":\"native\",\"prompt\":\"p\",\"answer\":[\"a\"]}" }
        return Data("{\"id\":\"s\",\"title\":\"t\",\"exercises\":[\(exercises.joined(separator: ","))]}".utf8)
    }

    func testUnknownTypeDecodesWithoutFailingTheSkill() throws {
        let decoded = try JSONDecoder().decode(SkillArtifact.self, from: skill(["type_in", "listen_translate", "listen_type"]))
        XCTAssertEqual(decoded.exercises.map { $0.type }, [.typeIn, .unknown, .listenType])
    }

    func testMissingTypeIsUnknown() throws {
        let data = Data("{\"id\":\"s\",\"title\":\"t\",\"exercises\":[{\"scriptMode\":\"native\",\"prompt\":\"p\",\"answer\":[\"a\"]}]}".utf8)
        let decoded = try JSONDecoder().decode(SkillArtifact.self, from: data)
        XCTAssertEqual(decoded.exercises.first?.type, .unknown)
    }

    func testListenTypeWireName() throws {
        XCTAssertEqual(ExerciseType.listenType.rawValue, "listen_type")
    }

    func testPlaysUsedIsOmittedWhenNilAndKeptWhenSet() throws {
        let plain = SubmittedItem(exerciseOrdinal: 0, lexemeTag: "t", exerciseType: .typeIn, scriptMode: .native, submittedText: "x", usedHint: false, attempt: 1)
        let listened = SubmittedItem(exerciseOrdinal: 0, lexemeTag: "t", exerciseType: .listenType, scriptMode: .native, submittedText: "x", usedHint: false, attempt: 1, playsUsed: 2)
        let plainJson = String(data: try JSONEncoder().encode(plain), encoding: .utf8) ?? ""
        let listenedJson = String(data: try JSONEncoder().encode(listened), encoding: .utf8) ?? ""
        XCTAssertFalse(plainJson.contains("playsUsed"))
        XCTAssertTrue(listenedJson.contains("\"playsUsed\":2"))
        XCTAssertTrue(listenedJson.contains("\"listen_type\""))
    }
}
