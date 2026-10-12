import Foundation
import QModel

// Which accepted answer the learner is shown after a check, and its recording.
// The backend records every accepted answer (answerVariantAudio, one entry per
// variant, index 0 = the first answer), so the audio played has to be the
// variant on screen. Port of web domain/answerVariants.ts / Android AnswerVariants.kt.

public struct AnswerVariant: Equatable, Sendable {
    public var index: Int
    public var text: String

    public init(index: Int, text: String) {
        self.index = index
        self.text = text
    }
}

public func isTokenized(_ exercise: ExerciseArtifact) -> Bool {
    return exercise.type == .wordBank || exercise.type == .match
}

/// The accepted answer the review shows first for this submission, and its index in the backend's variant order (word_bank/match: 0 = answer, i = alternativeAnswers[i - 1]; otherwise answer[i]). Same choice as the wrong-answer screen, so text and audio agree. No submission keeps the authored first answer.
public func shownAnswerVariant(_ exercise: ExerciseArtifact, submittedText: String?) -> AnswerVariant {
    if isTokenized(exercise) {
        let shown = WordBankOrders.revealedTileOrder(exercise, submittedText: submittedText)
        let index = WordBankOrders.acceptedTileOrders(exercise).firstIndex(of: shown) ?? 0
        return AnswerVariant(index: max(index, 0), text: shown.joined(separator: " "))
    }
    let text = closestAnswerFirst(submittedText ?? "", exercise.answer).first ?? ""
    let index = exercise.answer.firstIndex(of: text) ?? 0
    return AnswerVariant(index: max(index, 0), text: text)
}

/// The recording of variant `index`, falling back to answerAudio when the field or that entry is missing, nil or holds no takes.
public func variantAudio(answerAudio: AudioMap?, answerVariantAudio: [AudioMap?]?, index: Int) -> AudioMap? {
    if let variants = answerVariantAudio, index >= 0, index < variants.count,
       let entry = variants[index], entry.values.contains(where: { !$0.isEmpty }) {
        return entry
    }
    return answerAudio
}

public func variantAudio(_ exercise: ExerciseArtifact, index: Int) -> AudioMap? {
    return variantAudio(answerAudio: exercise.answerAudio, answerVariantAudio: exercise.answerVariantAudio, index: index)
}
