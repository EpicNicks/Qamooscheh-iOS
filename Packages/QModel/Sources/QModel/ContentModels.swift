import Foundation

/// Voice id to that voice takes of one phrase or word, first take first.
public typealias AudioMap = [String: [String]]


/// Pointer from a parent artifact to a child JSON file.
public struct ManifestRef: Codable, Equatable, Sendable {
    public var id: String
    public var path: String

    public init(id: String, path: String) {
        self.id = id
        self.path = path
    }
}

/// course/{code}/v{version}/manifest.json.
public struct CourseManifest: Codable, Equatable, Sendable {
    public var courseCode: String
    public var version: Int
    public var units: [ManifestRef]
    public var lexemeIndexPath: String
    public var themeIndexPath: String?
    public var audioIndexPath: String?
    public var verbIndexPath: String?

    public init(courseCode: String, version: Int, units: [ManifestRef], lexemeIndexPath: String, themeIndexPath: String? = nil, audioIndexPath: String? = nil, verbIndexPath: String? = nil) {
        self.courseCode = courseCode
        self.version = version
        self.units = units
        self.lexemeIndexPath = lexemeIndexPath
        self.themeIndexPath = themeIndexPath
        self.audioIndexPath = audioIndexPath
        self.verbIndexPath = verbIndexPath
    }
}

/// A voice in audio.json.
public struct AudioVoiceEntry: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var recordings: Int
    public var bytes: Int64
    public var kind: String?
    public var words: Int?

    public init(id: String, name: String, recordings: Int = 0, bytes: Int64 = 0, kind: String? = nil, words: Int? = nil) {
        self.id = id
        self.name = name
        self.recordings = recordings
        self.bytes = bytes
        self.kind = kind
        self.words = words
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.recordings = try c.decodeIfPresent(Int.self, forKey: .recordings) ?? 0
        self.bytes = try c.decodeIfPresent(Int64.self, forKey: .bytes) ?? 0
        self.kind = try c.decodeIfPresent(String.self, forKey: .kind)
        self.words = try c.decodeIfPresent(Int.self, forKey: .words)
    }
}

/// A story character; empty voices means any voice.
public struct AudioSpeakerEntry: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var voices: [String]

    public init(id: String, name: String, voices: [String] = []) {
        self.id = id
        self.name = name
        self.voices = voices
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.voices = try c.decodeIfPresent([String].self, forKey: .voices) ?? []
    }
}

/// One recorded phrase.
public struct AudioIndexEntry: Codable, Equatable, Sendable {
    public var text: String
    public var voice: String?
    public var path: String
    public var lexeme: String?
    public var take: Int?

    public init(text: String, voice: String? = nil, path: String, lexeme: String? = nil, take: Int? = nil) {
        self.text = text
        self.voice = voice
        self.path = path
        self.lexeme = lexeme
        self.take = take
    }
}

/// audio.json; older versions lack voices and speakers.
public struct AudioIndexArtifact: Codable, Equatable, Sendable {
    public var voices: [AudioVoiceEntry]
    public var phrases: [AudioIndexEntry]
    public var speakers: [AudioSpeakerEntry]

    public init(voices: [AudioVoiceEntry] = [], phrases: [AudioIndexEntry] = [], speakers: [AudioSpeakerEntry] = []) {
        self.voices = voices
        self.phrases = phrases
        self.speakers = speakers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.voices = try c.decodeIfPresent([AudioVoiceEntry].self, forKey: .voices) ?? []
        self.phrases = try c.decodeIfPresent([AudioIndexEntry].self, forKey: .phrases) ?? []
        self.speakers = try c.decodeIfPresent([AudioSpeakerEntry].self, forKey: .speakers) ?? []
    }
}

/// One exercise.
public struct ExerciseArtifact: Codable, Equatable, Sendable {
    public var type: ExerciseType
    public var scriptMode: ExerciseScriptMode
    public var prompt: String
    public var tiles: [String]?
    public var answer: [String]
    public var tags: [String]
    public var alternativeAnswers: [[String]]?
    public var promptRomanization: String?
    public var answerRomanization: String?
    public var promptAudio: AudioMap?
    public var answerAudio: AudioMap?
    public var speaker: String?
    public var answerVariantAudio: [AudioMap?]?

    public init(type: ExerciseType, scriptMode: ExerciseScriptMode, prompt: String, tiles: [String]? = nil, answer: [String], tags: [String] = [], alternativeAnswers: [[String]]? = nil, promptRomanization: String? = nil, answerRomanization: String? = nil, promptAudio: AudioMap? = nil, answerAudio: AudioMap? = nil, speaker: String? = nil, answerVariantAudio: [AudioMap?]? = nil) {
        self.type = type
        self.scriptMode = scriptMode
        self.prompt = prompt
        self.tiles = tiles
        self.answer = answer
        self.tags = tags
        self.alternativeAnswers = alternativeAnswers
        self.promptRomanization = promptRomanization
        self.answerRomanization = answerRomanization
        self.promptAudio = promptAudio
        self.answerAudio = answerAudio
        self.speaker = speaker
        self.answerVariantAudio = answerVariantAudio
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try c.decodeIfPresent(ExerciseType.self, forKey: .type) ?? .unknown
        self.scriptMode = try c.decode(ExerciseScriptMode.self, forKey: .scriptMode)
        self.prompt = try c.decode(String.self, forKey: .prompt)
        self.tiles = try c.decodeIfPresent([String].self, forKey: .tiles)
        self.answer = try c.decode([String].self, forKey: .answer)
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.alternativeAnswers = try c.decodeIfPresent([[String]].self, forKey: .alternativeAnswers)
        self.promptRomanization = try c.decodeIfPresent(String.self, forKey: .promptRomanization)
        self.answerRomanization = try c.decodeIfPresent(String.self, forKey: .answerRomanization)
        self.promptAudio = try c.decodeIfPresent(AudioMap.self, forKey: .promptAudio)
        self.answerAudio = try c.decodeIfPresent(AudioMap.self, forKey: .answerAudio)
        self.speaker = try c.decodeIfPresent(String.self, forKey: .speaker)
        self.answerVariantAudio = try c.decodeIfPresent([AudioMap?].self, forKey: .answerVariantAudio)
    }
}

/// units/{unit}/skills/{skill}.json, exercises included.
public struct SkillArtifact: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var category: SkillCategory
    public var arc: String?
    public var exercises: [ExerciseArtifact]
    public var themes: [String]
    public var commonUsageScore: Int?

    public init(id: String, title: String, category: SkillCategory = .standard, arc: String? = nil, exercises: [ExerciseArtifact] = [], themes: [String] = [], commonUsageScore: Int? = nil) {
        self.id = id
        self.title = title
        self.category = category
        self.arc = arc
        self.exercises = exercises
        self.themes = themes
        self.commonUsageScore = commonUsageScore
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.category = try c.decodeIfPresent(SkillCategory.self, forKey: .category) ?? .standard
        self.arc = try c.decodeIfPresent(String.self, forKey: .arc)
        self.exercises = try c.decodeIfPresent([ExerciseArtifact].self, forKey: .exercises) ?? []
        self.themes = try c.decodeIfPresent([String].self, forKey: .themes) ?? []
        self.commonUsageScore = try c.decodeIfPresent(Int.self, forKey: .commonUsageScore)
    }
}

/// One position; several skills are side versions.
public struct UnitPosition: Codable, Equatable, Sendable {
    public var skills: [ManifestRef]

    public init(skills: [ManifestRef]) {
        self.skills = skills
    }
}

/// units/{unitKey}.json.
public struct UnitArtifact: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var positions: [UnitPosition]

    public init(id: String, title: String, positions: [UnitPosition]) {
        self.id = id
        self.title = title
        self.positions = positions
    }
}

/// One entry of lexemes.json (a tag to entry map).
public struct LexemeIndexEntry: Codable, Equatable, Sendable {
    public var gloss: String
    public var register: Register?
    public var pos: String?
    public var verbForm: String?
    public var lemma: String?
    public var romanization: String?
    public var romanizationIsAuthored: Bool
    public var forms: [String]?
    public var audio: AudioMap?

    public init(gloss: String, register: Register? = nil, pos: String? = nil, verbForm: String? = nil, lemma: String? = nil, romanization: String? = nil, romanizationIsAuthored: Bool, forms: [String]? = nil, audio: AudioMap? = nil) {
        self.gloss = gloss
        self.register = register
        self.pos = pos
        self.verbForm = verbForm
        self.lemma = lemma
        self.romanization = romanization
        self.romanizationIsAuthored = romanizationIsAuthored
        self.forms = forms
        self.audio = audio
    }
}

/// A lesson inside a theme.
public struct ThemeLessonRef: Codable, Equatable, Sendable {
    public var id: String
    public var path: String
    public var commonUsageScore: Int?

    public init(id: String, path: String, commonUsageScore: Int? = nil) {
        self.id = id
        self.path = path
        self.commonUsageScore = commonUsageScore
    }
}

/// A theme.
public struct ThemeEntry: Codable, Equatable, Sendable {
    public var id: String
    public var parentId: String?
    public var lessons: [ThemeLessonRef]

    public init(id: String, parentId: String? = nil, lessons: [ThemeLessonRef]) {
        self.id = id
        self.parentId = parentId
        self.lessons = lessons
    }
}

/// themes.json.
public struct ThemeIndexArtifact: Codable, Equatable, Sendable {
    public var themes: [ThemeEntry]

    public init(themes: [ThemeEntry]) {
        self.themes = themes
    }
}

/// One conjugation cell.
public struct VerbFormCell: Codable, Equatable, Sendable {
    public var written: String
    public var spoken: String?
    public var negative: String
    public var negativeSpoken: String?

    public init(written: String, spoken: String? = nil, negative: String, negativeSpoken: String? = nil) {
        self.written = written
        self.spoken = spoken
        self.negative = negative
        self.negativeSpoken = negativeSpoken
    }
}

/// One verb in verbs.json.
public struct VerbIndexEntry: Codable, Equatable, Sendable {
    public var infinitive: String
    public var prefix: String?
    public var presentStem: String
    public var pastStem: String
    public var principalParts: [String]
    public var table: [String: [String: VerbFormCell]]

    public init(infinitive: String, prefix: String? = nil, presentStem: String, pastStem: String, principalParts: [String], table: [String: [String: VerbFormCell]]) {
        self.infinitive = infinitive
        self.prefix = prefix
        self.presentStem = presentStem
        self.pastStem = pastStem
        self.principalParts = principalParts
        self.table = table
    }
}
