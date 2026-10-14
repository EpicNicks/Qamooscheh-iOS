import SwiftUI
import QDesign
import QData

/// A round audio button (Android `AudioButton`): `fill` behind a glyph, labelled for VoiceOver.
struct RoundAudioButton<Content: View>: View {
    let size: CGFloat
    let fill: Color
    let label: String
    let action: () -> Void
    let content: Content

    init(size: CGFloat, fill: Color, label: String, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.size = size
        self.fill = fill
        self.label = label
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(fill)
                content
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Plays the prompt aloud (web PlayAudioButton): the big speaker, or with `slow` the smaller turtle that replays at SpeechService.slowRate.
public struct PlayAudioButton: View {
    private let slow: Bool
    private let palette: AppPalette?
    private let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    public init(slow: Bool = false, palette: AppPalette? = nil, action: @escaping () -> Void) {
        self.slow = slow
        self.palette = palette
        self.action = action
    }

    public var body: some View {
        let p = palette ?? (colorScheme == .dark ? AppPalette.dark : AppPalette.light)
        if slow {
            RoundAudioButton(size: 40, fill: Color(argb: p.current).opacity(0.75), label: TypeInModel.playSlowLabel, action: action) {
                Text("\u{1F422}").font(.system(size: 20))
            }
        } else {
            RoundAudioButton(size: 48, fill: Color(argb: p.current), label: TypeInModel.playLabel, action: action) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
    }
}

/// Stands in for the play button when the device has no voice for the language and the exercise has no recording (web NoVoiceButton): grey, and tapping it points the learner at installing one.
public struct NoVoiceButton: View {
    private let palette: AppPalette?
    private let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    public init(palette: AppPalette? = nil, action: @escaping () -> Void) {
        self.palette = palette
        self.action = action
    }

    public var body: some View {
        let p = palette ?? (colorScheme == .dark ? AppPalette.dark : AppPalette.light)
        RoundAudioButton(size: 48, fill: Color(argb: p.locked), label: TypeInModel.noVoiceLabel, action: action) {
            Image(systemName: "speaker.slash.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}

/// The audio row above a native-script prompt: play and play-slowly, or the no-voice button when neither a voice nor a recording exists. Voice availability comes from `speech`.
public struct PromptAudioControls: View {
    private let speech: SpeechService
    private let languageTag: String
    private let hasRecording: Bool
    private let palette: AppPalette?
    private let onPlay: () -> Void
    private let onPlaySlow: () -> Void
    private let onInstallVoice: () -> Void

    public init(
        speech: SpeechService,
        languageTag: String,
        hasRecording: Bool,
        palette: AppPalette? = nil,
        onPlay: @escaping () -> Void,
        onPlaySlow: @escaping () -> Void,
        onInstallVoice: @escaping () -> Void
    ) {
        self.speech = speech
        self.languageTag = languageTag
        self.hasRecording = hasRecording
        self.palette = palette
        self.onPlay = onPlay
        self.onPlaySlow = onPlaySlow
        self.onInstallVoice = onInstallVoice
    }

    public var body: some View {
        let canSpeak = TypeInModel.canSpeak(hasVoice: speech.hasVoice(languageTag), hasPromptAudio: hasRecording)
        HStack(spacing: Spacing.standard.s2) {
            if canSpeak {
                PlayAudioButton(palette: palette, action: onPlay)
                PlayAudioButton(slow: true, palette: palette, action: onPlaySlow)
            } else {
                NoVoiceButton(palette: palette, action: onInstallVoice)
            }
        }
    }
}
