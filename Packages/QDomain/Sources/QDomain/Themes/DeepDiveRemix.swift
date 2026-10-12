import Foundation
import QModel

// "More like this" for a Deep Dive lesson, or a blend of the themes a learner
// picked. Matches the Android port (core/domain theme/DeepDiveRemix.kt).

/// Most lessons blended into one remix.
public let remixMaxLessons = 4

/// Most exercises in a remix session.
public let remixMaxExercises = 20

private let masteryStabilityCap = 30.0

/// Every standard lesson under themeIds, once each (first-seen order), minus excludeLessonKey.
/// Stories, conversations and songs only make sense in order, so they are left out.
/// categoryOf is nil for a lesson whose content isn't known (excluded).
public func buildRemixPool(
    themeIndex: ThemeIndexArtifact?,
    categoryOf: (_ lessonKey: String) -> SkillCategory?,
    themeIds: [String],
    excludeLessonKey: String? = nil
) -> [ThemeLessonRef] {
    guard let themeIndex = themeIndex else { return [] }
    let byId = indexThemesById(themeIndex.themes)
    var seen = Set<String>()
    if let exclude = excludeLessonKey { seen.insert(exclude) }
    var pool: [ThemeLessonRef] = []
    for themeId in themeIds {
        for lesson in byId[themeId]?.lessons ?? [] {
            let isNew = seen.insert(lesson.id).inserted
            if isNew && categoryOf(lesson.id) == .standard { pool.append(lesson) }
        }
    }
    return pool
}

/// How well the learner knows tags, 0...1: each card's stability against a 30-day cap, averaged.
/// A tag with no card counts as 0; an empty list is 0.
public func computeMasteryScore(cards: [String: CardState], tags: [String]) -> Double {
    if tags.isEmpty { return 0 }
    var total = 0.0
    for tag in tags {
        if let card = cards[tag] { total += min(card.stability / masteryStabilityCap, 1) }
    }
    return total / Double(tags.count)
}

/// Up to count lessons, sampled without replacement and weighted toward those whose
/// common-usage score fits the learner's mastery: a beginner gets everyday lessons
/// (high scores), a strong learner rarer ones. A nil score counts as 50.
public func selectRemixLessons<G: RandomNumberGenerator>(
    candidates: [ThemeLessonRef],
    masteryScore: Double,
    count: Int,
    using generator: inout G
) -> [ThemeLessonRef] {
    let target = 100 * (1 - masteryScore)
    var pool: [(lesson: ThemeLessonRef, weight: Double)] = candidates.map { lesson in
        let score = Double(lesson.commonUsageScore ?? 50)
        return (lesson: lesson, weight: 1 / (1 + abs(score - target)))
    }
    var result: [ThemeLessonRef] = []
    while !pool.isEmpty && result.count < count {
        var total = 0.0
        for entry in pool { total += entry.weight }
        // All remaining weights zero: fall back to a uniform pick.
        let unit = Double.random(in: 0..<1, using: &generator)
        var roll = total > 0 ? unit * total : unit * Double(pool.count)
        var index = 0
        while index < pool.count {
            let weight = total > 0 ? pool[index].weight : 1.0
            if roll < weight { break }
            roll -= weight
            index += 1
        }
        result.append(pool.remove(at: min(index, pool.count - 1)).lesson)
    }
    return result
}

/// selectRemixLessons with the system random generator.
public func selectRemixLessons(candidates: [ThemeLessonRef], masteryScore: Double, count: Int) -> [ThemeLessonRef] {
    var generator = SystemRandomNumberGenerator()
    return selectRemixLessons(candidates: candidates, masteryScore: masteryScore, count: count, using: &generator)
}
