import Foundation
import QModel

// Vocabulary grouped by lesson and by unit, derived entirely from the course
// content (each skill's exercises' tags). Lesson vocab is the single source of
// truth: unit vocab is the deduped union of its lessons' tags (in lesson
// order), and course vocab the deduped union of every unit's (in unit order).
// Port of web courseVocabulary.ts (+ Android buildCourseVocabulary).

public struct LessonVocab: Equatable, Sendable {
    public var unitKey: String
    public var skillKey: String
    public var title: String
    /// This skill's own exercises' tags, deduped, first-occurrence order.
    public var tags: [String]

    public init(unitKey: String, skillKey: String, title: String, tags: [String]) {
        self.unitKey = unitKey
        self.skillKey = skillKey
        self.title = title
        self.tags = tags
    }
}

public struct UnitVocab: Equatable, Sendable {
    public var unitKey: String
    public var title: String
    public var lessons: [LessonVocab]

    public init(unitKey: String, title: String, lessons: [LessonVocab]) {
        self.unitKey = unitKey
        self.title = title
        self.lessons = lessons
    }
}

private func dedupe(_ tags: [String]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for tag in tags where seen.insert(tag).inserted {
        out.append(tag)
    }
    return out
}

/// This lesson's own vocabulary, or nil if the course has no such lesson.
public func lessonVocab(_ units: [UnitVocab], unitKey: String, skillKey: String) -> LessonVocab? {
    units.first(where: { $0.unitKey == unitKey })?.lessons.first(where: { $0.skillKey == skillKey })
}

/// Every tag any lesson in this unit uses, deduped, in the order those lessons are authored.
public func unitVocabTags(_ units: [UnitVocab], unitKey: String) -> [String] {
    guard let unit = units.first(where: { $0.unitKey == unitKey }) else { return [] }
    return dedupe(unit.lessons.flatMap { $0.tags })
}

/// Every tag anywhere in the course, deduped, in unit-then-lesson order.
public func courseVocabTags(_ units: [UnitVocab]) -> [String] {
    dedupe(units.flatMap { unit in unit.lessons.flatMap { $0.tags } })
}

/// Every skill in every unit, standard or not (a story's vocabulary is still
/// vocabulary). `skills` is keyed "unitKey/skillKey"; a skill missing from it
/// keeps its id as its title and contributes no tags.
public func buildCourseVocabulary(units: [UnitArtifact], skills: [String: SkillArtifact]) -> [UnitVocab] {
    units.map { unit in
        let refs = unit.positions.flatMap { $0.skills }
        let lessons = refs.map { ref -> LessonVocab in
            let skill = skills["\(unit.id)/\(ref.id)"]
            return LessonVocab(
                unitKey: unit.id,
                skillKey: ref.id,
                title: skill?.title ?? ref.id,
                tags: dedupe((skill?.exercises ?? []).flatMap { $0.tags })
            )
        }
        return UnitVocab(unitKey: unit.id, title: unit.title, lessons: lessons)
    }
}
