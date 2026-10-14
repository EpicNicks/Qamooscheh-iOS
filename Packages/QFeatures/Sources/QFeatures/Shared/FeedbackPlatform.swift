import Foundation

#if canImport(UIKit) && !os(watchOS)
import UIKit

public final class SystemHaptics: HapticsPlaying {
    public init() {}

    public func play(_ kind: HapticKind) {
        DispatchQueue.main.async {
            switch kind {
            case .success:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .error:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            case .tick:
                UISelectionFeedbackGenerator().selectionChanged()
            case .celebrate:
                let gen = UINotificationFeedbackGenerator()
                gen.notificationOccurred(.success)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                }
            }
        }
    }
}
#else
public final class SystemHaptics: HapticsPlaying {
    public init() {}
    public func play(_ kind: HapticKind) {}
}
#endif

#if canImport(AVFoundation)
import AVFoundation

/// AVAudioPlayer with the ambient session category, so the silent switch is respected
/// and other audio keeps playing. A missing asset is a no-op.
public final class SystemSfx: SfxPlaying {
    private let bundle: Bundle
    private var players: [String: AVAudioPlayer] = [:]
    private let extensions = ["caf", "wav", "m4a", "mp3"]

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    public func play(fileName: String, volume: Float) {
        guard let player = player(for: fileName) else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        #endif
        player.volume = volume
        player.currentTime = 0
        player.play()
    }

    private func player(for fileName: String) -> AVAudioPlayer? {
        if let cached = players[fileName] { return cached }
        for ext in extensions {
            if let url = bundle.url(forResource: fileName, withExtension: ext),
               let p = try? AVAudioPlayer(contentsOf: url) {
                p.prepareToPlay()
                players[fileName] = p
                return p
            }
        }
        return nil
    }
}
#else
public final class SystemSfx: SfxPlaying {
    public init(bundle: Bundle = .main) {}
    public func play(fileName: String, volume: Float) {}
}
#endif
