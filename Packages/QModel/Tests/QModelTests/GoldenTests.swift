import XCTest
@testable import QModel

/// Golden JSON round trips: each payload is written the way the backend emits
/// it (camelCase, snake_case enum values, ISO-8601 instants, optional keys
/// present). Decoding then re-encoding must reproduce the same JSON object.
final class GoldenTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        return try QJSON.makeDecoder().decode(T.self, from: Data(json.utf8))
    }

    /// Decodes, re-encodes and checks the result is the same JSON object.
    @discardableResult
    private func golden<T: Codable & Equatable>(
        _ type: T.Type, _ json: String, file: StaticString = #filePath, line: UInt = #line
    ) throws -> T {
        let value = try decode(T.self, json)
        let encoded = try QJSON.makeEncoder().encode(value)
        let expected = try JSONSerialization.jsonObject(with: Data(json.utf8)) as AnyObject
        let actual = try JSONSerialization.jsonObject(with: encoded) as AnyObject
        XCTAssertTrue(expected.isEqual(actual), "re-encoded JSON differs: \(String(decoding: encoded, as: UTF8.self))", file: file, line: line)
        let again = try decode(T.self, String(decoding: encoded, as: UTF8.self))
        XCTAssertEqual(value, again, file: file, line: line)
        return value
    }

    func testAuthResponse() throws {
        let v = try golden(AuthResponse.self, """
        {"userId":"3f2504e0-4f89-11d3-9a0c-0305e82c3301","accessToken":"a.b.c","refreshToken":"r1","accessTokenExpiresAt":"2026-03-01T12:30:45.123Z"}
        """)
        XCTAssertEqual(v.userId, "3f2504e0-4f89-11d3-9a0c-0305e82c3301")
        XCTAssertEqual(QDates.format(v.accessTokenExpiresAt), "2026-03-01T12:30:45.123Z")
    }

    func testAuthRequests() throws {
        try golden(RegisterRequest.self, #"{"email":"a@b.co","password":"hunter22","confirmPassword":"hunter22"}"#)
        try golden(LoginRequest.self, #"{"email":"a@b.co","password":"x"}"#)
        try golden(GoogleAuthRequest.self, #"{"idToken":"tok"}"#)
        try golden(RefreshRequest.self, #"{"refreshToken":"r"}"#)
        let s = try golden(RegistrationStatusResponse.self, #"{"enabled":true}"#)
        XCTAssertTrue(s.enabled)
    }

    func testDateOffsetsAndFractions() throws {
        let a = QDates.parse("2026-03-01T12:30:45+00:00")
        let b = QDates.parse("2026-03-01T14:30:45+02:00")
        let c = QDates.parse("2026-03-01T12:30:45Z")
        XCTAssertNotNil(a)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, c)
        let d = QDates.parse("2026-03-01T12:30:45.1234567Z")
        XCTAssertNotNil(d)
        XCTAssertEqual(d!.timeIntervalSince(c!), 0.1234567, accuracy: 0.0001)
        XCTAssertNil(QDates.parse("not a date"))
    }

    func testBootstrapEnrolled() throws {
        let v = try golden(BootstrapResponse.self, """
        {"course":{"code":"fa","version":3,"manifestSha256":"abc"},
         "position":{"unitKey":"u1","skillKey":"s2"},
         "graders":[{"language":"fa","variant":"wasi","version":2,"manifestSha256":"def"}],
         "enrolledCourseCodes":["fa","ja"],
         "onboardingComplete":true,
         "update":{"version":4,"manifestSha256":"ghi","eligible":true,"notes":"New units"},
         "stowage":[],"stowableLessonKeys":[]}
        """)
        XCTAssertEqual(v.course?.version, 3)
        XCTAssertEqual(v.graders.count, 1)
        XCTAssertEqual(v.update?.notes, "New units")
        XCTAssertEqual(v.stowage, [])
        XCTAssertEqual(v.stowableLessonKeys, [])
    }

    func testBootstrapWithStowage() throws {
        let v = try golden(BootstrapResponse.self, """
        {"course":{"code":"fa","version":3,"manifestSha256":"abc"},
         "position":{"unitKey":"u3","skillKey":"s1"},
         "graders":[],"enrolledCourseCodes":["fa"],"onboardingComplete":true,
         "stowage":[
           {"unitKey":"u3","lessons":[
             {"lessonKey":"a","stowedAt":"2026-10-24T12:00:00.000Z","lessonsCompletedSince":3,"readyPromptDue":true,"muted":false},
             {"lessonKey":"b","stowedAt":"2026-10-24T13:00:00.000Z","lessonsCompletedSince":0,"readyPromptDue":false,"muted":true}]},
           {"unitKey":"u1","lessons":[
             {"lessonKey":"z","stowedAt":"2026-10-23T08:00:00.000Z","lessonsCompletedSince":5,"readyPromptDue":false,"muted":false}]}],
         "stowableLessonKeys":["c","d"]}
        """)
        // Units stay in the order the server sent (descending); lessons ascend within a unit.
        XCTAssertEqual(v.stowage.map { $0.unitKey }, ["u3", "u1"])
        XCTAssertEqual(v.stowage[0].lessons.map { $0.lessonKey }, ["a", "b"])
        XCTAssertTrue(v.stowage[0].lessons[0].readyPromptDue)
        XCTAssertTrue(v.stowage[0].lessons[1].muted)
        XCTAssertEqual(v.stowage[0].lessons[0].lessonsCompletedSince, 3)
        XCTAssertEqual(QDates.format(v.stowage[1].lessons[0].stowedAt), "2026-10-23T08:00:00.000Z")
        XCTAssertEqual(v.stowableLessonKeys, ["c", "d"])
    }

    func testBootstrapStowFieldsAbsentDecodeEmpty() throws {
        let v = try decode(BootstrapResponse.self, """
        {"course":null,"position":null,"graders":[],"enrolledCourseCodes":[],"onboardingComplete":false}
        """)
        XCTAssertEqual(v.stowage, [])
        XCTAssertEqual(v.stowableLessonKeys, [])
    }

    func testStowOffset() throws {
        // The backend emits +00:00 offsets; they decode to the same instant.
        let v = try decode(StowageResponse.self, """
        {"applied":true,"stowage":[{"unitKey":"u","lessons":[
          {"lessonKey":"a","stowedAt":"2026-10-24T12:00:00+00:00","lessonsCompletedSince":0,"readyPromptDue":false,"muted":false}]}]}
        """)
        XCTAssertEqual(QDates.format(v.stowage[0].lessons[0].stowedAt), "2026-10-24T12:00:00.000Z")
    }

    func testStowRequestAndResponses() throws {
        try golden(StowRequest.self, #"{"lessonKey":"01-hello"}"#)
        let s = try golden(StowResponse.self, """
        {"applied":false,"position":{"unitKey":"01-greetings","skillKey":"02-numbers"},"stowage":[]}
        """)
        XCTAssertFalse(s.applied)
        XCTAssertEqual(s.position.skillKey, "02-numbers")
        let m = try golden(StowageResponse.self, """
        {"applied":true,"stowage":[{"unitKey":"u","lessons":[
          {"lessonKey":"a","stowedAt":"2026-10-24T12:00:00.000Z","lessonsCompletedSince":1,"readyPromptDue":false,"muted":true}]}]}
        """)
        XCTAssertTrue(m.applied)
        XCTAssertEqual(m.stowage[0].lessons[0].lessonKey, "a")
    }

    func testSubmittedSessionStowCleared() throws {
        let v = try golden(SubmittedSessionResponse.self, """
        {"submissionId":"11111111-1111-1111-1111-111111111111","outcome":"Processed","cards":[],"lessonCompleted":true,"stowCleared":"01-hello"}
        """)
        XCTAssertEqual(v.stowCleared, "01-hello")
        let w = try decode(SubmittedSessionResponse.self, """
        {"submissionId":"11111111-1111-1111-1111-111111111111","outcome":"Processed","cards":[]}
        """)
        XCTAssertNil(w.stowCleared)
    }

    func testBootstrapNotEnrolled() throws {
        let v = try decode(BootstrapResponse.self, """
        {"course":null,"position":null,"graders":[],"enrolledCourseCodes":[],"onboardingComplete":false,"update":null}
        """)
        XCTAssertNil(v.course)
        XCTAssertNil(v.position)
        XCTAssertNil(v.update)
        XCTAssertFalse(v.onboardingComplete)
        // An omitted update decodes the same as an explicit null.
        let w = try decode(BootstrapResponse.self, """
        {"course":null,"position":null,"graders":[],"enrolledCourseCodes":[],"onboardingComplete":false}
        """)
        XCTAssertEqual(v, w)
    }

    func testCourses() throws {
        try golden(CourseCatalogResponse.self, """
        {"courses":[{"code":"fa","nativeName":"فارسی","latinName":"Persian","cultureFacts":["Nowruz is the new year."]}]}
        """)
        try golden(SwitchActiveCourseRequest.self, #"{"courseCode":"ja"}"#)
        try golden(RollForwardRequest.self, #"{"toVersion":5}"#)
        let p = try golden(RollForwardPreviewResponse.self, """
        {"courseCode":"fa","fromVersion":3,"toVersion":5,"manifestSha256":"abc","updateNotes":"n",
         "from":{"unitKey":"u1","skillKey":"s1","unitIndex":0,"lessonIndex":2},
         "to":{"unitKey":"u1","skillKey":"s2","unitIndex":0,"lessonIndex":3},
         "clamped":true,"unitClamped":false,"lessonClamped":true}
        """)
        XCTAssertEqual(p.to?.lessonIndex, 3)
        try golden(OnboardingCompleteResponse.self, #"{"onboardingComplete":true}"#)
    }

    func testSessionPlan() throws {
        let v = try golden(SessionPlanResponse.self, """
        {"courseVersion":3,"skills":[{"unitKey":"u1","skillKey":"s1"},{"skillKey":"theme-a"}],
         "reviewTags":["salam<interj>"],"newTags":["n1"],"prefetchTags":["p1","p2"]}
        """)
        XCTAssertEqual(v.skills.count, 2)
        XCTAssertNil(v.skills[1].unitKey)
    }

    func testSessionSubmitRoundTrip() throws {
        try golden(SubmitSessionsRequest.self, """
        {"sessions":[{"submissionId":"11111111-1111-1111-1111-111111111111","courseCode":"fa","unitKey":"u1","skillKey":"s1",
          "courseVersion":3,"occurredAt":"2026-03-01T12:30:45.000Z","completed":true,
          "items":[{"exerciseOrdinal":0,"lexemeTag":"salam<interj>","exerciseType":"word_bank","scriptMode":"native",
                    "submittedText":"سلام","usedHint":false,"latencyMs":1500,"attempt":1,"retypeText":"سلام"}]}]}
        """)
    }

    func testSessionSubmitResponse() throws {
        let v = try golden(SubmitSessionsResponse.self, """
        {"sessions":[
          {"submissionId":"11111111-1111-1111-1111-111111111111","outcome":"Processed","rejectionReason":"none",
           "cards":[{"lexemeTag":"salam<interj>","stability":2.5,"difficulty":4.25,
                     "lastReviewedAt":"2026-03-01T12:30:45.000Z","dueAt":"2026-03-04T12:30:45.000Z","reviewCount":3,"lapseCount":1}],
           "score":0.9,"lessonCompleted":true,"xp":12},
          {"submissionId":"22222222-2222-2222-2222-222222222222","outcome":"AlreadyProcessed","cards":[]},
          {"submissionId":"33333333-3333-3333-3333-333333333333","outcome":"Rejected","rejectionReason":"stale","cards":[]}]}
        """)
        XCTAssertEqual(v.sessions[0].outcome, .processed)
        XCTAssertEqual(v.sessions[1].outcome, .alreadyProcessed)
        XCTAssertEqual(v.sessions[2].outcome, .rejected)
        XCTAssertEqual(v.sessions[0].cards[0].reviewCount, 3)
        XCTAssertNil(v.sessions[1].score)
        XCTAssertNil(v.sessions[1].xp)
    }

    func testCardStateNullDates() throws {
        let c = try decode(CardState.self, """
        {"lexemeTag":"t","stability":0.0,"difficulty":0.0,"lastReviewedAt":null,"dueAt":null,"reviewCount":0,"lapseCount":0}
        """)
        XCTAssertNil(c.lastReviewedAt)
        XCTAssertNil(c.dueAt)
    }

    func testCheckpoint() throws {
        let plan = try golden(CheckpointPlanResponse.self, """
        {"courseVersion":3,"targetUnitKey":"u2","targetSkillKey":"s4",
         "skills":[{"unitKey":"u1","skillKey":"s1","exerciseOrdinals":[0,2,5]}],
         "skippedLessons":[{"unitKey":"u1","position":1,"lessonKeys":["s1","s1b"],"positionAlreadyCompleted":false}],
         "skippedCount":3,"alreadyCompletedCount":1,"requiresTest":true}
        """)
        XCTAssertEqual(plan.skills[0].exerciseOrdinals, [0, 2, 5])
        try golden(SubmitCheckpointRequest.self, """
        {"submissionId":"44444444-4444-4444-4444-444444444444","targetUnitKey":"u2","targetSkillKey":"s4","courseVersion":3,
         "occurredAt":"2026-03-01T12:30:45.000Z",
         "skills":[{"unitKey":"u1","skillKey":"s1","items":[{"exerciseOrdinal":0,"lexemeTag":"t","exerciseType":"type_in",
           "scriptMode":"romanized","submittedText":"salam","usedHint":true,"attempt":2}]}]}
        """)
        let r = try golden(CheckpointSubmitResponse.self, """
        {"passed":true,"score":0.85,"cards":[],"skippedLessons":[],"skippedCount":3,"alreadyCompletedCount":0,
         "requiresTest":false,"applied":true,"xp":20}
        """)
        XCTAssertEqual(r.xp, 20)
    }

    func testPrefs() throws {
        let p = try golden(PrefsResponse.self, """
        {"scriptMode":"both","register":"standard","autoplayAudio":true,"keyboardMode":"contextual",
         "desiredRetention":0.9,"dailyGoalXp":50,"preferredVoice":"v1"}
        """)
        XCTAssertEqual(p.scriptMode, .both)
        XCTAssertEqual(p.register, .standard)
        XCTAssertEqual(p.keyboardMode, .contextual)
        let u = try golden(UpdatePrefsRequest.self, """
        {"scriptMode":"romanized","register":"spoken","autoplayAudio":false,"keyboardMode":"isolated",
         "desiredRetention":0.85,"dailyGoalXp":30}
        """)
        XCTAssertNil(u.preferredVoice)
        XCTAssertThrowsError(try decode(PrefsResponse.self, """
        {"scriptMode":"klingon","register":"spoken","autoplayAudio":false,"keyboardMode":"isolated","desiredRetention":0.9,"dailyGoalXp":1}
        """))
    }

    func testProfile() throws {
        try golden(UpdateProfileRequest.self, #"{"displayName":"Nick","fullName":"Nicholas","country":"CA"}"#)
        let p = try decode(ProfileResponse.self, #"{"displayName":null,"fullName":null,"country":null}"#)
        XCTAssertNil(p.displayName)
        let full = try golden(ProfileResponse.self, #"{"displayName":"Nick","fullName":"Nicholas","country":"CA"}"#)
        XCTAssertEqual(full.country, "CA")
    }

    func testSocial() throws {
        try golden(FriendRefResponse.self, """
        {"userId":"55555555-5555-5555-5555-555555555555","displayName":"Ali","since":"2026-02-01T00:00:00.000Z"}
        """)
        let s = try golden(FriendRequestResponse.self, #"{"status":"pending"}"#)
        XCTAssertEqual(s.status, .pending)
        try golden(UserSearchResultResponse.self, #"{"userId":"55555555-5555-5555-5555-555555555555","displayName":"Ali"}"#)
        let l = try golden(CurrentLeagueResponse.self, """
        {"tier":2,"periodEndsAt":"2026-03-08T00:00:00.000Z",
         "standings":[{"userId":"55555555-5555-5555-5555-555555555555","displayName":"Ali","points":120}]}
        """)
        XCTAssertEqual(l.standings[0].points, 120)
    }

    func testStreakAndActivity() throws {
        let s = try golden(StreakResponse.self, """
        {"currentStreakDays":5,"longestStreakDays":9,"practicedToday":true,"pausedToday":false,
         "pause":{"startDay":"2026-03-10","endDay":"2026-03-12","started":false},
         "pauseDaysAvailable":2,"timeZone":"America/Toronto","dayStartHour":3,"today":"2026-03-01",
         "nextDayStartsAt":"2026-03-02T08:00:00.000Z"}
        """)
        XCTAssertEqual(s.pause?.startDay, "2026-03-10")
        XCTAssertEqual(s.today, "2026-03-01")
        let n = try decode(StreakResponse.self, """
        {"currentStreakDays":0,"longestStreakDays":0,"practicedToday":false,"pausedToday":false,"pause":null,
         "pauseDaysAvailable":3,"timeZone":"UTC","dayStartHour":3,"today":"2026-03-01","nextDayStartsAt":"2026-03-01T03:00:00+00:00"}
        """)
        XCTAssertNil(n.pause)
        try golden(StreakPauseRequest.self, #"{"startDay":"2026-03-10","endDay":"2026-03-12"}"#)
        try golden(ActivityResponse.self, """
        {"courseCode":"fa","days":[{"localDay":"2026-03-01","reviews":14,"xp":40},{"localDay":"2026-02-28","reviews":3,"xp":9}]}
        """)
    }

    func testVocabAndFlashcards() throws {
        let v = try golden(StarredVocabResponse.self, #"{"tags":["a","b"],"limit":100,"refused":["c"]}"#)
        XCTAssertEqual(v.limit, 100)
        try golden(SetStarredRequest.self, #"{"tag":"a","starred":true}"#)
        try golden(BatchSetStarredRequest.self, #"{"star":["a"],"unstar":["b"]}"#)
        let p = try golden(StarredPracticeResponse.self, """
        {"courseVersion":3,"words":[{"tag":"a","exercises":[{"unitKey":"u1","skillKey":"s1","ordinal":4}]}]}
        """)
        XCTAssertEqual(p.words[0].exercises[0].ordinal, 4)
        XCTAssertNil(p.words[0].exercises[0].form)
        let verb = try golden(StarredPracticeResponse.self, """
        {"courseVersion":45,"words":[{"tag":"خریدن<v>","exercises":[{"unitKey":"u1","skillKey":"s1","ordinal":4,"form":"خریدم<v>"}]}]}
        """)
        XCTAssertEqual(verb.words[0].exercises[0].form, "خریدم<v>")
        let f = try golden(SubmitFlashcardsRequest.self, """
        {"submissionId":"66666666-6666-6666-6666-666666666666","courseCode":"fa","occurredAt":"2026-03-01T12:30:45.000Z",
         "inRemix":false,"cards":[{"tag":"a","kind":"self_rated","correct":true},{"tag":"b","kind":"translation","correct":false}]}
        """)
        XCTAssertEqual(f.cards[0].kind, .selfRated)
        XCTAssertEqual(f.cards[1].kind, .translation)
        try golden(SubmitFlashcardsResponse.self, #"{"alreadyProcessed":false,"xp":6}"#)
        let cloze = try golden(SubmitFlashcardsRequest.self, """
        {"submissionId":"66666666-6666-6666-6666-666666666666","courseCode":"fa","occurredAt":"2026-03-01T12:30:45.000Z",
         "inRemix":false,"hardcore":true,"cards":[{"tag":"a","kind":"cloze","correct":true,"attempt":2,"elapsedMs":4200}]}
        """)
        XCTAssertEqual(cloze.cards[0].kind, .cloze)
        XCTAssertEqual(cloze.cards[0].attempt, 2)
        XCTAssertEqual(cloze.hardcore, true)
    }

    func testRace() throws {
        let start = try golden(StartRaceRequest.self, """
        {"courseCode":"fa","mode":"perfect_delivery","hardcore":false,"deviceClass":"touch","tags":["a","b"]}
        """)
        XCTAssertEqual(start.mode, .perfectDelivery)
        XCTAssertEqual(start.deviceClass, .touch)
        let started = try golden(StartRaceResponse.self, """
        {"runId":"77777777-7777-7777-7777-777777777777","serverStartedAt":"2026-03-01T12:30:45.123+00:00","weights":{"a":1.5,"b":1.9}}
        """)
        XCTAssertEqual(started.weights["b"], 1.9)
        let finish = try golden(FinishRaceRequest.self, """
        {"answers":[{"tag":"a","attempt":1,"correct":true,"elapsedMs":2100},{"tag":"b","attempt":3,"correct":false}],"deckDone":true}
        """)
        XCTAssertNil(finish.answers[1].elapsedMs)
        let done = try golden(FinishRaceResponse.self, """
        {"score":3.4,"timeMs":41200,"solved":2,"strikes":1,"endReason":"deck_done","xp":8,"held":false,"rank":12,
         "personalBest":{"score":3.4,"timeMs":41200},"alreadyFinished":false}
        """)
        XCTAssertEqual(done.rank, 12)
        let held = try decode(FinishRaceResponse.self, """
        {"score":1,"timeMs":900,"solved":1,"strikes":0,"endReason":"deck_done","xp":0,"held":true,"heldReason":"answer_too_fast",
         "rank":null,"personalBest":null,"alreadyFinished":true}
        """)
        XCTAssertTrue(held.held)
        XCTAssertNil(held.rank)
        XCTAssertNil(held.personalBest)
        let board = try golden(RaceBoardResponse.self, """
        {"entries":[{"rank":1,"userId":"88888888-8888-8888-8888-888888888888","displayName":"Sam","country":"CA","score":9.5,"timeMs":60000,"isYou":true}]}
        """)
        XCTAssertTrue(board.entries[0].isYou)
        XCTAssertEqual(RaceMode.allCases.map { $0.rawValue }, ["perfect_delivery", "endless_practice"])
        XCTAssertEqual(RaceScope.allCases.map { $0.rawValue }, ["global", "country", "weekly", "friends"])
    }

    func testExerciseReport() throws {
        let r = try golden(SubmitExerciseReportRequest.self, """
        {"exercisePrompt":"Hello","exerciseTags":["salam<interj>"],"reasons":["audio_wrong","other"],"details":"crackly",
         "submittedAnswer":"salaam","renderType":"word_bank","courseVersion":3,"unitKey":"u1","skillKey":"s1",
         "exerciseOrdinal":2,"audioFiles":["../../../audio/abc.mp3"]}
        """)
        XCTAssertEqual(r.reasons, [.audioWrong, .other])
        XCTAssertEqual(r.renderType, .wordBank)
        let minimal = try decode(SubmitExerciseReportRequest.self, """
        {"exercisePrompt":"Hello","exerciseTags":["t"],"reasons":["answer_should_be_accepted"],"details":null}
        """)
        XCTAssertNil(minimal.audioFiles)
        try golden(SubmitExerciseReportResponse.self, #"{"id":7,"createdAt":"2026-03-01T12:30:45.000Z"}"#)
    }

    func testContentManifestAndUnits() throws {
        let m = try golden(CourseManifest.self, """
        {"courseCode":"fa","version":3,"units":[{"id":"u1","path":"units/u1.json"}],"lexemeIndexPath":"lexemes.json",
         "themeIndexPath":"themes.json","audioIndexPath":"audio.json","verbIndexPath":"verbs.json"}
        """)
        XCTAssertEqual(m.units[0].path, "units/u1.json")
        // Older versions publish without theme, audio or verb indexes.
        let old = try decode(CourseManifest.self, #"{"courseCode":"fa","version":1,"units":[],"lexemeIndexPath":"lexemes.json"}"#)
        XCTAssertNil(old.themeIndexPath)
        XCTAssertNil(old.audioIndexPath)
        try golden(UnitArtifact.self, """
        {"id":"u1","title":"Basics","positions":[{"skills":[{"id":"s1","path":"skills/s1.json"},{"id":"s1b","path":"skills/s1b.json"}]}]}
        """)
        try golden(ThemeIndexArtifact.self, """
        {"themes":[{"id":"food","parentId":"life","lessons":[{"id":"l1","path":"lessons/l1.json","commonUsageScore":7}]}]}
        """)
    }

    func testSkillArtifact() throws {
        let s = try golden(SkillArtifact.self, """
        {"id":"s1","title":"Greetings","category":"story","arc":"intro","themes":["social"],"commonUsageScore":5,
         "newLexemes":["salam<interj>"],
         "exercises":[
          {"type":"word_bank","scriptMode":"native","prompt":"Hello","tiles":["سلام","خوبی"],"answer":["سلام"],
           "tags":["salam<interj>"],"alternativeAnswers":[["خوبی"]],"promptRomanization":"salam","answerRomanization":"salam",
           "promptAudio":{"v1":["../../../audio/a.mp3"]},"answerAudio":{"v1":["../../../audio/b.mp3","../../../audio/c.mp3"]},
           "speaker":"narrator","answerVariantAudio":[{"v1":["../../../audio/b.mp3"]},null]},
          {"type":"speak","scriptMode":"romanized","prompt":"Say hi","answer":["salam"],"tags":[]}]}
        """)
        XCTAssertEqual(s.category, .story)
        XCTAssertEqual(s.exercises[0].type, .wordBank)
        XCTAssertEqual(s.exercises[0].answerVariantAudio?.count, 2)
        XCTAssertNil(s.exercises[0].answerVariantAudio?[1])
        XCTAssertNil(s.exercises[1].tiles)
        XCTAssertEqual(s.newLexemes, ["salam<interj>"])
        // Older artifacts omit category, exercises' tags, themes, newLexemes.
        let old = try decode(SkillArtifact.self, #"{"id":"s0","title":"Old"}"#)
        XCTAssertEqual(old.category, .standard)
        XCTAssertEqual(old.exercises, [])
        XCTAssertEqual(old.newLexemes, [])
    }

    func testAudioIndex() throws {
        let a = try golden(AudioIndexArtifact.self, """
        {"voices":[{"id":"v1","name":"Sara","recordings":10,"bytes":2048000,"kind":"human","words":4}],
         "phrases":[{"text":"سلام","voice":"v1","path":"../../../audio/a.mp3","lexeme":"salam<interj>","take":0}],
         "speakers":[{"id":"narrator","name":"Narrator","voices":["v1"]}]}
        """)
        XCTAssertEqual(a.voices[0].bytes, 2_048_000)
        let old = try decode(AudioIndexArtifact.self, #"{"phrases":[{"text":"x","path":"audio/x.mp3"}]}"#)
        XCTAssertEqual(old.voices, [])
        XCTAssertEqual(old.speakers, [])
        XCTAssertNil(old.phrases[0].voice)
    }

    func testLexemeIndex() throws {
        let m = try golden([String: LexemeIndexEntry].self, """
        {"salam<interj><spoken>":{"gloss":"hello","register":"spoken","pos":"interj","verbForm":"inf","lemma":"salam",
          "romanization":"salaam","romanizationIsAuthored":true,"forms":["salaam"],"audio":{"v1":["../../../audio/a.mp3"]}},
         "ketab<n>":{"gloss":"book","romanizationIsAuthored":false}}
        """)
        XCTAssertEqual(m["salam<interj><spoken>"]?.register, .spoken)
        XCTAssertNil(m["ketab<n>"]?.register)
    }

    func testVerbIndex() throws {
        let v = try golden(VerbIndexEntry.self, """
        {"infinitive":"raftan","prefix":"be","presentStem":"rav","pastStem":"raft","principalParts":["raftan","rav"],
         "table":{"present":{"1sg":{"written":"miravam","spoken":"miram","negative":"nemiravam","negativeSpoken":"nemiram"}}}}
        """)
        XCTAssertEqual(v.table["present"]?["1sg"]?.spoken, "miram")
    }
}
