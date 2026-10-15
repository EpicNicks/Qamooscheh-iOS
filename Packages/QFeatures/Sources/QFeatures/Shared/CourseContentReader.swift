import Foundation
import QModel
import QDomain
import QNetwork
import QData

/// Reads the pinned course from the downloaded store (the keys CourseDownloader wrote).
public struct CourseContentReader: Sendable {
    private let store: ContentFileStore

    public init(store: ContentFileStore) {
        self.store = store
    }

    /// The store key for a path relative to the version root; ".." resolves within the version tree only.
    /// Nil for an empty or "." segment, an absolute path, or one that climbs above the version root.
    static func key(course: CourseRef, path: String) -> String? {
        let root = ["course", course.code, "v\(course.version)"]
        var parts = root
        for segment in path.split(separator: "/", omittingEmptySubsequences: false).map(String.init) {
            switch segment {
            case "", ".":
                return nil
            case "..":
                if parts.count <= root.count { return nil }
                parts.removeLast()
            default:
                parts.append(segment)
            }
        }
        return parts.count > root.count ? parts.joined(separator: "/") : nil
    }

    /// True when every file of the pinned version is on disk.
    public func isDownloaded(_ course: CourseRef) -> Bool {
        ContentStoreKeys.isComplete(store, courseCode: course.code, version: course.version, manifestSha256: course.manifestSha256)
    }

    private func decode<T: Decodable>(_ type: T.Type, course: CourseRef, path: String) throws -> T? {
        guard let key = Self.key(course: course, path: path), let data = try store.read(key) else { return nil }
        return try QJSON.makeDecoder().decode(T.self, from: data)
    }

    public func manifest(_ course: CourseRef) throws -> CourseManifest? {
        try decode(CourseManifest.self, course: course, path: "manifest.json")
    }

    /// Units, skills and the lexeme index, or nil when the manifest, a unit or the lexeme index is missing.
    public func vocabContent(_ course: CourseRef) throws -> VocabContent? {
        guard let manifest = try manifest(course) else { return nil }
        var units: [UnitArtifact] = []
        var skills: [String: SkillArtifact] = [:]
        for ref in manifest.units {
            guard let unit = try decode(UnitArtifact.self, course: course, path: ref.path) else { return nil }
            units.append(unit)
            for skillRef in unit.positions.flatMap({ $0.skills }) {
                if let skill = try decode(SkillArtifact.self, course: course, path: skillRef.path) {
                    skills["\(unit.id)/\(skillRef.id)"] = skill
                }
            }
        }
        guard let lexemes = try decode([String: LexemeIndexEntry].self, course: course, path: manifest.lexemeIndexPath) else { return nil }
        return VocabContent(courseCode: course.code, units: buildCourseVocabulary(units: units, skills: skills), lexemes: lexemes)
    }

    /// The course's voices (audio.json), default first, each with a word it recorded for the Play button.
    /// Like Android, a voice with no recordings is labelled so and has no sample, which hides Play.
    /// iOS speaks the sample word with the device voice for the course language.
    public func settingsVoices(_ course: CourseRef) throws -> [SettingsVoice] {
        guard let manifest = try manifest(course), let path = manifest.audioIndexPath,
              let index = try decode(AudioIndexArtifact.self, course: course, path: path) else { return [] }
        let lexemes = try decode([String: LexemeIndexEntry].self, course: course, path: manifest.lexemeIndexPath) ?? [:]
        let tags = lexemes.keys.sorted()
        let language = Languages.languageInfo(course.code)?.speechTag
        return index.voices.enumerated().map { offset, voice in
            let defaultMark = offset == 0 ? " (default)" : ""
            let emptyMark = voice.recordings > 0 ? "" : " \u{2014} no recordings yet"
            let sampleTag = tags.first { lexemes[$0]?.audio?[voice.id]?.first != nil }
            let text = sampleTag.map { parseLexemeTag($0).surface }
            return SettingsVoice(
                id: voice.id, label: voice.name + defaultMark + emptyMark,
                sampleText: text, sampleLanguage: text == nil ? nil : language)
        }
    }

    /// themes.json and each lesson's title and category; nil when the course has no themes.
    public func themeLibrary(_ course: CourseRef) throws -> ThemeLibraryData? {
        guard let manifest = try manifest(course), let path = manifest.themeIndexPath,
              let index = try decode(ThemeIndexArtifact.self, course: course, path: path) else { return nil }
        var headers: [String: ThemeLessonHeader] = [:]
        for lesson in index.themes.flatMap({ $0.lessons }) where headers[lesson.id] == nil {
            if let skill = try decode(SkillArtifact.self, course: course, path: lesson.path) {
                headers[lesson.id] = ThemeLessonHeader(title: skill.title, category: skill.category)
            }
        }
        return ThemeLibraryData(index: index, headers: headers)
    }
}
