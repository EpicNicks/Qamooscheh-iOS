import Foundation
import QModel

// Picking which recording to play. Every exercise carries promptAudio and
// answerAudio and every lexeme its word-only takes, each an AudioMap of
// voice id -> takes. Which voice follows audio.json's rules: a line with a
// speaker plays one of that speaker's voices, anything else the learner's
// preferred voice, falling back to the course's default (audio.json's first
// voice). Port of web recordings.ts, shaped like Android's Recordings.kt.

public struct VoiceChoice: Equatable, Sendable {
    /// user_prefs.preferred_voice; nil means the course default.
    public var preferredVoice: String?
    /// audio.json's first voice, or nil on a course without one.
    public var defaultVoice: String?
    /// The line's speaker's voices (audio.json `speakers`), when it has a speaker. Empty means any voice.
    public var speakerVoices: [String]

    public init(preferredVoice: String?, defaultVoice: String?, speakerVoices: [String] = []) {
        self.preferredVoice = preferredVoice
        self.defaultVoice = defaultVoice
        self.speakerVoices = speakerVoices
    }
}

public enum Recordings {
    /// FNV-1a over UTF-16 code units, finished with murmur3's fmix32, as on the web.
    public static func voiceHash(_ text: String) -> UInt32 {
        var h: UInt32 = 0x811c9dc5
        for unit in text.utf16 {
            h ^= UInt32(unit)
            h = h &* 0x01000193
        }
        h ^= h >> 16
        h = h &* 0x85ebca6b
        h ^= h >> 13
        h = h &* 0xc2b2ae35
        h ^= h >> 16
        return h
    }

    /// Sorts by UTF-16 code units, like JS and Kotlin default string order.
    private static func utf16Less(_ a: String, _ b: String) -> Bool {
        return a.utf16.lexicographicallyPrecedes(b.utf16)
    }

    /// One of `voices`, drawn by `seed` and `key`; sorted and de-duplicated first, so the draw doesn't depend on listing order. Nil when there are none.
    public static func drawVoice(_ voices: [String], seed: Int, key: String) -> String? {
        let pool = Array(Set(voices)).sorted(by: utf16Less)
        if pool.isEmpty { return nil }
        let index = Int(voiceHash("\(seed):\(key)") % UInt32(pool.count))
        return pool[index]
    }

    private static func recordedVoices(_ audio: AudioMap?) -> [String] {
        guard let audio = audio else { return [] }
        var voices: [String] = []
        for (voice, takes) in audio {
            if let first = takes.first, !first.isEmpty { voices.append(voice) }
        }
        return voices.sorted(by: utf16Less)
    }

    /// The first non-empty tier's draw.
    private static func drawFromTiers(_ tiers: [[String]], seed: Int, key: String) -> String? {
        guard let tier = tiers.first(where: { !$0.isEmpty }) else { return nil }
        return drawVoice(tier, seed: seed, key: key)
    }

    /// With voices shuffled, the voice a whole exercise plays in: drawn from the voices that recorded both its prompt and its answer, else either, else the whole `cast`; a line with a speaker draws only among `speakerVoices`.
    public static func exerciseVoice(
        prompt: String,
        answer: String?,
        promptAudio: AudioMap?,
        answerAudio: AudioMap?,
        cast: [String],
        speakerVoices: [String],
        seed: Int
    ) -> String? {
        let own: [String]? = speakerVoices.isEmpty ? nil : speakerVoices
        func allowed(_ voice: String) -> Bool {
            if let own = own { return own.contains(voice) }
            return true
        }
        let prompted = recordedVoices(promptAudio)
        let answered = recordedVoices(answerAudio)
        let both = prompted.filter { answered.contains($0) && allowed($0) }
        let either = (prompted + answered).filter { allowed($0) }
        return drawFromTiers(
            [both, either, own ?? cast],
            seed: seed,
            key: "\(prompt)\n\(answer ?? "")"
        )
    }

    /// The same outside any exercise: one recording's own draw, keyed by its takes, the speaker's voices first.
    public static func lineVoice(audio: AudioMap?, speakerVoices: [String], seed: Int) -> String? {
        let recorded = recordedVoices(audio)
        let takes = recorded.compactMap { audio?[$0]?.first }.sorted(by: utf16Less)
        let key = takes.joined(separator: "|")
        return drawFromTiers([recorded.filter { speakerVoices.contains($0) }, recorded], seed: seed, key: key)
    }

    /// The path of the take to play, relative to the version root, or nil when nothing usable is recorded. Always a voice's first take.
    public static func pickRecording(_ audio: AudioMap?, choice: VoiceChoice) -> String? {
        guard let audio = audio else { return nil }
        func takeOf(_ voice: String?) -> String? {
            guard let voice = voice else { return nil }
            return audio[voice]?.first
        }
        if !choice.speakerVoices.isEmpty {
            if let preferred = choice.preferredVoice, choice.speakerVoices.contains(preferred), let take = takeOf(preferred) {
                return take
            }
            for voice in choice.speakerVoices {
                if let take = takeOf(voice) { return take }
            }
        }
        if let take = takeOf(choice.preferredVoice) { return take }
        if let take = takeOf(choice.defaultVoice) { return take }
        // Dictionary order is unspecified; sort the voices so the fallback is stable.
        for voice in audio.keys.sorted(by: utf16Less) {
            if let take = audio[voice]?.first { return take }
        }
        return nil
    }

    /// Spelling compared without reading aids, so a vowel-marked tile still finds its lexeme.
    private static func sameWord(_ a: String, _ b: String) -> Bool {
        return a == b || PersianNormalize.stripReadingAids(a) == PersianNormalize.stripReadingAids(b)
    }

    /// The recording of one word as written on screen (a word-bank tile), or nil. The exercise's own tags are tried before the rest of the course's lexemes; a tile with endings attached has no recording.
    public static func wordRecording(
        text: String,
        exerciseTags: [String],
        lexemeIndex: [String: LexemeIndexEntry]?,
        choice: VoiceChoice
    ) -> String? {
        guard let lexemeIndex = lexemeIndex else { return nil }
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if word.isEmpty { return nil }
        // Sorted so the course-wide search is deterministic (a Swift dictionary has no key order).
        let candidates = exerciseTags + lexemeIndex.keys.sorted(by: utf16Less)
        for tag in candidates {
            guard let entry = lexemeIndex[tag], let audio = entry.audio else { continue }
            let spellings = [parseLexemeTag(tag).surface] + (entry.forms ?? [])
            if !spellings.contains(where: { sameWord($0, word) }) { continue }
            if let recording = pickRecording(audio, choice: choice) { return recording }
        }
        return nil
    }
}
