import Foundation

// Reads lesson text aloud with the platform text-to-speech. Port of the
// speech half of Android core/platform Speech.kt: one voice at a time (a new
// request cuts off the old one), a rate where 1 is normal, and a false return
// when the device has no voice for the language (Persian voices are often
// missing) so callers can say so instead of failing silently.
//
// Recorded-audio-first ordering lives in QDomain Playback. SpeechService has
// the same shape as Playback's speech backend (startSpeech returns a stop
// closure) so the app can hand it to Playback as the fallback half.

/// The platform synthesizer behind SpeechService. AVSpeechSynthesizer in the app; a fake in tests.
public protocol SpeechSynthesizing: AnyObject {
    /// BCP-47 tags of the installed voices, e.g. "ja-JP".
    func installedVoiceLanguages() -> [String]
    /// Whether the synthesizer is speaking right now.
    var isSpeaking: Bool { get }
    /// Speaks `text` with a voice for `voiceLanguage` (a tag from `installedVoiceLanguages`) at `rate` (1 is normal). `onEnd` fires when it finishes, fails or is stopped.
    func speak(text: String, voiceLanguage: String, rate: Double, onEnd: @escaping () -> Void)
    /// Cuts off any speech in progress.
    func stop()
}

public final class SpeechService {
    /// The slowed replay's speed (web SLOW_RATE): slow enough to hear each word.
    public static let slowRate: Double = 0.7

    private let synthesizer: SpeechSynthesizing
    private var current: Utterance?

    /// One request's end-callback, fired exactly once however it ends.
    private final class Utterance {
        private var onEnd: (() -> Void)?
        init(onEnd: @escaping () -> Void) { self.onEnd = onEnd }
        func finish() {
            guard let callback = onEnd else { return }
            onEnd = nil
            callback()
        }
    }

    public init(synthesizer: SpeechSynthesizing) {
        self.synthesizer = synthesizer
    }

    /// The installed voice that speaks `languageTag`: the exact tag first (fa-IR), else any voice for the same language (fa-AF for fa-IR). Nil when there is none.
    public func voice(for languageTag: String) -> String? {
        let installed = synthesizer.installedVoiceLanguages()
        let wanted = normalize(languageTag)
        if let exact = installed.first(where: { normalize($0) == wanted }) { return exact }
        let language = primaryLanguage(wanted)
        if language.isEmpty { return nil }
        return installed.first(where: { primaryLanguage(normalize($0)) == language })
    }

    /// Whether text-to-speech can speak `languageTag` on this device.
    public func hasVoice(_ languageTag: String) -> Bool {
        return voice(for: languageTag) != nil
    }

    /// Whether something is being spoken right now: sound effects stay quiet over it.
    public var isSpeaking: Bool {
        return synthesizer.isSpeaking
    }

    /// Speaks `text`, cutting off whatever was being said. False (nothing spoken, `onEnd` not called) when there is no voice for the language. `onEnd` fires once when the speech finishes, fails or is cut off.
    @discardableResult
    public func speak(_ text: String, languageTag: String, rate: Double = 1, onEnd: @escaping () -> Void = {}) -> Bool {
        stop()
        guard let voice = voice(for: languageTag) else { return false }
        let utterance = Utterance(onEnd: onEnd)
        current = utterance
        synthesizer.speak(text: text, voiceLanguage: voice, rate: rate, onEnd: { [weak self] in
            utterance.finish()
            if let self = self, self.current === utterance { self.current = nil }
        })
        return true
    }

    /// Cuts off the current speech, if any; its `onEnd` fires.
    public func stop() {
        let previous = current
        current = nil
        if previous != nil { synthesizer.stop() }
        previous?.finish()
    }

    /// Playback-backend shape: speaks and returns a closure that stops only this speech. With no voice, `onEnd` fires at once and the closure does nothing.
    public func startSpeech(text: String, lang: String, rate: Double, onEnd: @escaping () -> Void) -> () -> Void {
        let started = speak(text, languageTag: lang, rate: rate, onEnd: onEnd)
        if !started {
            onEnd()
            return {}
        }
        let mine = current
        return { [weak self] in
            guard let self = self, let mine = mine, self.current === mine else { return }
            self.stop()
        }
    }

    private func normalize(_ tag: String) -> String {
        return tag.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private func primaryLanguage(_ normalized: String) -> String {
        return normalized.split(separator: "-").first.map(String.init) ?? ""
    }
}

#if canImport(AVFoundation)
import AVFoundation

/// AVSpeechSynthesizer behind SpeechSynthesizing.
public final class AVSpeechSynthesizerAdapter: NSObject, SpeechSynthesizing, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var endings: [ObjectIdentifier: () -> Void] = [:]

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    public func installedVoiceLanguages() -> [String] {
        return AVSpeechSynthesisVoice.speechVoices().map { $0.language }
    }

    public var isSpeaking: Bool {
        return synthesizer.isSpeaking
    }

    public func speak(text: String, voiceLanguage: String, rate: Double, onEnd: @escaping () -> Void) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: voiceLanguage)
        // Rate 1 is the system default speed; scale it, within the engine range.
        let scaled = Double(AVSpeechUtteranceDefaultSpeechRate) * rate
        let low = Double(AVSpeechUtteranceMinimumSpeechRate)
        let high = Double(AVSpeechUtteranceMaximumSpeechRate)
        utterance.rate = Float(min(max(scaled, low), high))
        endings[ObjectIdentifier(utterance)] = onEnd
        synthesizer.speak(utterance)
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func ended(_ utterance: AVSpeechUtterance) {
        let callback = endings.removeValue(forKey: ObjectIdentifier(utterance))
        callback?()
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        ended(utterance)
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        ended(utterance)
    }
}
#endif
