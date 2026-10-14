import Foundation
import Combine
import QModel
import QDomain

public enum VocabScope: Hashable, Sendable {
    case lesson
    case unit
    case course
}

public struct VocabScopeOption: Equatable, Sendable {
    public var scope: VocabScope
    public var label: String

    public init(scope: VocabScope, label: String) {
        self.scope = scope
        self.label = label
    }
}

/// One lesson's vocabulary, widenable to its unit or the whole course (web VocabularyReviewPage at
/// /vocabulary/:unitKey/:skillKey, Android SkillVocabularyViewModel). Without a lesson it opens on
/// the unit and offers only the unit and the course. Scope and search text live here, so a reload
/// on reappearing never resets them.
@MainActor
public final class SkillVocabularyModel: ObservableObject {
    public let store: VocabularyStore
    public let unitKey: String
    public let skillKey: String?
    @Published public private(set) var requestedScope: VocabScope
    @Published public var query: String = ""

    private let now: () -> Date
    private var forwarding: AnyCancellable?

    public init(store: VocabularyStore, unitKey: String, skillKey: String?, now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.unitKey = unitKey
        self.skillKey = skillKey
        self.now = now
        self.requestedScope = skillKey != nil ? .lesson : .unit
        forwarding = store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    public func refresh() async { await store.refresh() }

    public func setScope(_ scope: VocabScope) { requestedScope = scope }

    private var lesson: LessonVocab? {
        guard let content = store.content, let skillKey = skillKey else { return nil }
        return lessonVocab(content.units, unitKey: unitKey, skillKey: skillKey)
    }

    /// Lesson and unit appear only when the course has them, then "Whole course" always.
    public var scopes: [VocabScopeOption] {
        guard let content = store.content else { return [] }
        var options: [VocabScopeOption] = []
        if let lesson = lesson { options.append(VocabScopeOption(scope: .lesson, label: lesson.title)) }
        if let unit = content.units.first(where: { $0.unitKey == unitKey }) {
            options.append(VocabScopeOption(scope: .unit, label: unit.title))
        }
        options.append(VocabScopeOption(scope: .course, label: "Whole course"))
        return options
    }

    /// A lesson or unit missing from this version falls through to the widest scope, as the web does.
    public var scope: VocabScope {
        scopes.contains(where: { $0.scope == requestedScope }) ? requestedScope : .course
    }

    public var terms: [VocabTerm] {
        guard let content = store.content else { return [] }
        let tags: [String]
        switch scope {
        case .lesson: tags = lesson?.tags ?? []
        case .unit: tags = unitVocabTags(content.units, unitKey: unitKey)
        case .course: tags = courseVocabTags(content.units)
        }
        let all = vocabTerms(
            tags: tags, lexemes: content.lexemes, cards: store.cards, starred: Set(store.starredTags), now: now())
        return filterVocabTerms(all, query: query)
    }

    public var emptyText: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Nothing here yet." : "No words match \"\(trimmed)\"."
    }
}
