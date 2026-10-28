import SwiftUI
import QDesign
import QDomain

/// Wording of the listening prompt, kept out of the view so swift test covers it.
public enum ListenPromptCopy {
    public static let instruction = "Type what you hear. Every play after the first is worth less XP."
    public static let playFailed = "Couldn't play the recording. A play that doesn't finish isn't counted."
    public static let playSlowLabel = "Play slowly"

    public static func playsLeftText(_ left: Int) -> String {
        if left <= 0 { return "No plays left" }
        return "\(left) \(left == 1 ? "play" : "plays") left"
    }

    public static func playLabel(playsLeft left: Int) -> String {
        if left <= 0 { return "No plays left" }
        return "Play audio, " + playsLeftText(left)
    }
}

/// A listening exercise's prompt (Backend#44): no text, only the play buttons and how many of the three plays are left;
/// the text shows once the answer is in. Both buttons stay locked while a take plays. Thin: the rules live in `ListeningPlays`.
public struct ListenPrompt: View {
    private let playsLeft: Int
    private let locked: Bool
    private let failed: Bool
    private let onPlay: () -> Void
    private let onPlaySlow: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    public init(playsLeft: Int, locked: Bool, failed: Bool, onPlay: @escaping () -> Void, onPlaySlow: @escaping () -> Void) {
        self.playsLeft = playsLeft
        self.locked = locked
        self.failed = failed
        self.onPlay = onPlay
        self.onPlaySlow = onPlaySlow
    }

    public var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        let canPlay = playsLeft > 0 && !locked
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RoundAudioButton(size: 64, fill: Color(argb: canPlay ? p.current : p.locked), label: ListenPromptCopy.playLabel(playsLeft: playsLeft), action: { if canPlay { onPlay() } }) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(.white)
                }
                if playsLeft > 0 {
                    RoundAudioButton(size: 40, fill: Color(argb: canPlay ? p.current : p.locked).opacity(0.75), label: ListenPromptCopy.playSlowLabel, action: { if canPlay { onPlaySlow() } }) {
                        Text("\u{1F422}").font(.system(size: 20))
                    }
                }
                Text(ListenPromptCopy.playsLeftText(playsLeft))
                    .font(.subheadline)
                    .foregroundColor(Color(argb: p.textMuted))
            }
            Text(ListenPromptCopy.instruction)
                .font(.footnote)
                .foregroundColor(Color(argb: p.textMuted))
            if failed {
                Text(ListenPromptCopy.playFailed)
                    .font(.footnote)
                    .foregroundColor(Color(argb: p.danger))
            }
        }
    }
}
