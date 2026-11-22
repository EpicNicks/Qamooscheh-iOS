import Foundation
import Combine

/// The caption of a rough-spots row with nothing to practise.
public let roughSpotsEmptyCaption = "Nothing is rough right now"

/// Whether there are rough spots to practise: the Library picker and the Review tab read it. A failed or missing fetch counts as none.
@MainActor
public final class RoughSpotsAvailability: ObservableObject {
    /// Words with at least one exercise, as of the last load; nil before one finishes, after a failure, or with no source.
    @Published public private(set) var wordCount: Int?
    private let source: RoughSpotsSource?

    public init(source: RoughSpotsSource?) {
        self.source = source
    }

    public var available: Bool { return (wordCount ?? 0) > 0 }

    /// Loads the words; the row stays as it was when the load was cancelled.
    public func refresh() async {
        guard let source = source else {
            wordCount = nil
            return
        }
        do {
            let response = try await source.roughSpots(count: roughSpotsWordCount)
            wordCount = response.words.filter { !$0.exercises.isEmpty }.count
        } catch {
            if Task.isCancelled { return }
            wordCount = nil
        }
    }
}
