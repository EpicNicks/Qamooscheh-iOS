import Foundation
import QModel

// What a story chapter reads as in the reader (web domain/storyLines.ts): per exercise, the course-language
// sentence with its own recording and romanization; an exercise with none is not a line. Pure.

public struct StoryReaderLine: Equatable, Sendable {
    /// Index of the exercise in the chapter.
    public var exerciseIndex: Int
    /// The course-language sentence.
    public var text: String
    public var romanization: String?
    /// Recordings of `text`, by voice.
    public var audio: AudioMap?
    /// The exercise's lexeme tags, for hints and saving.
    public var tags: [String]
    public var speaker: String?
    /// The take to play, or nil when nothing usable is recorded: the line then has no play button and the chain skips it.
    public var clip: String?

    public init(exerciseIndex: Int, text: String, romanization: String?, audio: AudioMap?, tags: [String], speaker: String?, clip: String?) {
        self.exerciseIndex = exerciseIndex
        self.text = text
        self.romanization = romanization
        self.audio = audio
        self.tags = tags
        self.speaker = speaker
        self.clip = clip
    }
}

public enum StoryReaderLines {
    /// The line for one exercise, without a clip chosen yet, or nil when neither side is in the course language.
    public static func line(_ exercise: ExerciseArtifact, index: Int, courseCode: String?) -> StoryReaderLine? {
        guard Languages.languageInfo(courseCode) != nil else { return nil }
        func inCourseLanguage(_ text: String) -> Bool {
            return !text.isEmpty && Languages.isNativeText(courseCode, text)
        }
        if inCourseLanguage(exercise.prompt) {
            return StoryReaderLine(
                exerciseIndex: index, text: exercise.prompt, romanization: exercise.promptRomanization,
                audio: exercise.promptAudio, tags: exercise.tags, speaker: exercise.speaker, clip: nil)
        }
        let shown = shownAnswerVariant(exercise, submittedText: nil)
        guard inCourseLanguage(shown.text) else { return nil }
        return StoryReaderLine(
            exerciseIndex: index, text: shown.text, romanization: exercise.answerRomanization,
            audio: variantAudio(exercise, index: shown.index), tags: exercise.tags, speaker: exercise.speaker, clip: nil)
    }

    /// The chapter's lines in authored order, each with the take its voice rules pick (the speaker's voices first, as the lesson player does).
    public static func lines(
        _ exercises: [ExerciseArtifact],
        courseCode: String?,
        preferredVoice: String?,
        defaultVoice: String?,
        speakers: [AudioSpeakerEntry] = []
    ) -> [StoryReaderLine] {
        var out: [StoryReaderLine] = []
        for (index, exercise) in exercises.enumerated() {
            guard var found = line(exercise, index: index, courseCode: courseCode) else { continue }
            var speakerVoices: [String] = []
            if let speaker = found.speaker, let entry = speakers.first(where: { $0.id == speaker }) {
                speakerVoices = entry.voices
            }
            let choice = VoiceChoice(preferredVoice: preferredVoice, defaultVoice: defaultVoice, speakerVoices: speakerVoices)
            found.clip = Recordings.pickRecording(found.audio, choice: choice)
            out.append(found)
        }
        return out
    }
}
