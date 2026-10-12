import Foundation

// One "read this aloud" call for everything that can be played: a recording
// when there is one, text-to-speech when there isn't, or when the recording
// fails to load. Port of web playback.ts. The audio player and the speech
// engine sit behind PlaybackBackend (AVFoundation lives in the app), so the
// ordering rules here are testable without either.

/// The platform side of playback. Each start call returns a closure that stops it.
public protocol PlaybackBackend: AnyObject {
    /// Plays the recording at `url` at `rate`. `onEnd` fires when it finishes; `onError` when it can't load or play.
    func startRecording(url: String, rate: Double, onEnd: @escaping () -> Void, onError: @escaping () -> Void) -> () -> Void
    /// Reads `text` aloud in BCP-47 `lang` at `rate`. `onEnd` fires when speech finishes or fails.
    func startSpeech(text: String, lang: String, rate: Double, onEnd: @escaping () -> Void) -> () -> Void
}

public struct PlaybackRequest: Equatable, Sendable {
    /// Absolute URL of the recording, or nil to go straight to text-to-speech.
    public var url: String?
    /// What text-to-speech reads when there's no playable recording.
    public var text: String
    /// BCP-47 tag for text-to-speech. Nil means no fallback: without a recording, nothing plays.
    public var speechLang: String?
    /// Playback speed, 1 by default; `Playback.slowRate` for the slowed replay.
    public var rate: Double

    public init(url: String?, text: String, speechLang: String?, rate: Double = 1) {
        self.url = url
        self.text = text
        self.speechLang = speechLang
        self.rate = rate
    }
}

public final class PlaybackHandle {
    private let stopAction: () -> Void
    init(stop: @escaping () -> Void) { self.stopAction = stop }
    public func stop() { stopAction() }
}

/// Plays one voice at a time: starting something stops whatever was playing. Single-threaded (call from the main actor).
public final class Playback {
    /// The slowed replay's speed: slow enough to hear each word, not so slow a recording smears.
    public static let slowRate: Double = 0.7

    private let backend: PlaybackBackend
    private var active: PlaybackHandle?

    public init(backend: PlaybackBackend) {
        self.backend = backend
    }

    /// Starts playback, stopping whatever was already playing. `onEnd` fires exactly once: when playback finishes, is stopped, or nothing could play.
    @discardableResult
    public func play(_ request: PlaybackRequest, onEnd: @escaping () -> Void = {}) -> PlaybackHandle {
        active?.stop()
        let session = Session(request: request, backend: backend, onEnd: onEnd)
        session.begin()
        let inner = PlaybackHandle(stop: { session.stop() })
        active = inner
        return PlaybackHandle(stop: { [weak self, inner] in
            inner.stop()
            if let self = self, self.active === inner { self.active = nil }
        })
    }

    private final class Session {
        let request: PlaybackRequest
        let backend: PlaybackBackend
        let onEnd: () -> Void
        var ended = false
        var stopped = false
        var speechStop: (() -> Void)?
        var audioStop: (() -> Void)?

        init(request: PlaybackRequest, backend: PlaybackBackend, onEnd: @escaping () -> Void) {
            self.request = request
            self.backend = backend
            self.onEnd = onEnd
        }

        func finish() {
            if ended { return }
            ended = true
            onEnd()
        }

        func fallback() {
            if stopped || speechStop != nil { return }
            if let lang = request.speechLang, !lang.isEmpty {
                speechStop = backend.startSpeech(text: request.text, lang: lang, rate: request.rate, onEnd: { [self] in finish() })
            } else {
                finish()
            }
        }

        func begin() {
            if let url = request.url, !url.isEmpty {
                audioStop = backend.startRecording(url: url, rate: request.rate, onEnd: { [self] in finish() }, onError: { [self] in fallback() })
            } else {
                fallback()
            }
        }

        // Stopping is once-only and ends this playback straight away: a stale
        // handle stopped again later must not reach the speech engine, which
        // would cancel whatever it is saying now.
        func stop() {
            if stopped || ended {
                stopped = true
                return
            }
            stopped = true
            audioStop?()
            speechStop?()
            finish()
        }
    }
}
