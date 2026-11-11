import Foundation
import QModel

// The story reader's audio state machine: the main player chains each line's clip; a per-line play plays only
// that clip. Audio sits behind StoryClipPlayer so tests use a fake. Single-threaded (call from the main actor).

public protocol StoryClipPlayer: AnyObject {
    /// Plays the take at `clip`; `onEnd` runs once with how it ended (`.cutOff` after `stop()`).
    func play(clip: String, onEnd: @escaping (PlayEnd) -> Void)
    func stop()
}

public enum StorySegmentState: Equatable, Sendable {
    case filled
    case current
    case upcoming
}

public final class StoryReaderPlayback {
    public let lines: [StoryReaderLine]
    private let player: StoryClipPlayer
    private var generation = 0

    /// The line the timeline is at: lines before it are filled. `lines.count` once the chain has finished.
    public private(set) var position = 0
    public private(set) var isMainPlaying = false
    /// The line a per-line play is playing, if any.
    public private(set) var playingLine: Int?
    /// Fires when the chain runs past its last clip.
    public var onFinished: (() -> Void)?
    /// Fires each time the timeline lands on the last line (seek or chain) and when the chain finishes; the
    /// receiver dedupes (see StoryReaderCompletionTrigger).
    public var onReachedEnd: (() -> Void)?

    public init(lines: [StoryReaderLine], player: StoryClipPlayer) {
        self.lines = lines
        self.player = player
    }

    public func hasPlayButton(_ index: Int) -> Bool {
        return lines.indices.contains(index) && lines[index].clip != nil
    }

    /// One segment per line, derived from `position` alone.
    public var segments: [StorySegmentState] {
        return lines.indices.map { index in
            if index < position { return .filled }
            if index == position { return .current }
            return .upcoming
        }
    }

    public var isFinished: Bool { return !lines.isEmpty && position >= lines.count }

    private func nextPlayable(from start: Int) -> Int? {
        var i = max(0, start)
        while i < lines.count {
            if lines[i].clip != nil { return i }
            i += 1
        }
        return nil
    }

    /// Play from the current line (from the top after a finish); lines without a clip are skipped.
    public func playMain() {
        if isMainPlaying { return }
        if isFinished { position = 0 }
        stopCurrent()
        isMainPlaying = true
        run(from: position)
    }

    public func pauseMain() {
        if !isMainPlaying { return }
        isMainPlaying = false
        stopCurrent()
    }

    public func toggleMain() {
        if isMainPlaying { pauseMain() } else { playMain() }
    }

    /// A segment tap: the timeline moves to that line, and a playing chain carries on from it.
    public func seek(to line: Int) {
        guard lines.indices.contains(line) else { return }
        position = line
        if line == lines.count - 1 { onReachedEnd?() }
        if isMainPlaying {
            stopCurrent()
            run(from: line)
        }
    }

    /// Plays only this line's clip: pauses the main player and does not resume it afterwards.
    public func playLine(_ index: Int) {
        guard hasPlayButton(index), let clip = lines[index].clip else { return }
        isMainPlaying = false
        stopCurrent()
        let mine = generation
        playingLine = index
        player.play(clip: clip, onEnd: { [weak self] _ in
            guard let self = self, self.generation == mine else { return }
            self.playingLine = nil
        })
    }

    /// Leaving the screen.
    public func stopAll() {
        isMainPlaying = false
        stopCurrent()
    }

    private func stopCurrent() {
        generation += 1
        playingLine = nil
        player.stop()
    }

    private func run(from start: Int) {
        guard let index = nextPlayable(from: start), let clip = lines[index].clip else {
            finish()
            return
        }
        position = index
        if index == lines.count - 1 { onReachedEnd?() }
        generation += 1
        let mine = generation
        player.play(clip: clip, onEnd: { [weak self] end in
            guard let self = self, self.generation == mine, self.isMainPlaying else { return }
            if end == .cutOff { return }
            self.run(from: index + 1)
        })
    }

    private func finish() {
        isMainPlaying = false
        position = lines.count
        onReachedEnd?()
        onFinished?()
    }
}
