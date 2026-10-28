import Foundation
import QDomain

/// Plays a course recording from the content store. A listening exercise plays recordings only, never speech.
public protocol RecordingPlaying: AnyObject {
    /// Plays the first of `keys` the store holds, at `rate` (1 = normal). `onEnd` runs exactly once: `.completed` only if
    /// the take ran to its end, `.failed` if none could be loaded or it broke off, `.cutOff` if `stop()` ended it.
    func play(keys: [String], rate: Double, onEnd: @escaping (PlayEnd) -> Void)
    /// Ends the running take, if any (its `onEnd` gets `.cutOff`).
    func stop()
}

#if canImport(AVFoundation)
import AVFoundation

/// AVAudioPlayer over the bytes `read` returns for a store key.
public final class StoreRecordingPlayer: NSObject, RecordingPlaying, AVAudioPlayerDelegate {
    private let read: (String) -> Data?
    private var player: AVAudioPlayer?
    private var onEnd: ((PlayEnd) -> Void)?

    public init(read: @escaping (String) -> Data?) {
        self.read = read
        super.init()
    }

    public func play(keys: [String], rate: Double, onEnd: @escaping (PlayEnd) -> Void) {
        stop()
        var loaded: AVAudioPlayer?
        for key in keys {
            if let data = read(key), let made = try? AVAudioPlayer(data: data) {
                loaded = made
                break
            }
        }
        guard let next = loaded else {
            onEnd(.failed)
            return
        }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        next.enableRate = true
        next.rate = Float(rate)
        next.delegate = self
        self.onEnd = onEnd
        player = next
        if !next.play() { finish(.failed) }
    }

    public func stop() {
        guard let running = player else { return }
        running.stop()
        finish(.cutOff)
    }

    private func finish(_ how: PlayEnd) {
        player = nil
        let callback = onEnd
        onEnd = nil
        callback?(how)
    }

    public func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        if finished !== player { return }
        finish(flag ? .completed : .failed)
    }

    public func audioPlayerDecodeErrorDidOccur(_ failing: AVAudioPlayer, error: Error?) {
        if failing !== player { return }
        finish(.failed)
    }
}
#endif
