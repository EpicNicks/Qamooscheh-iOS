import SwiftUI
import QDesign
import QDomain
import QModel

// The exercise's prompt (web ExercisePrompt, matching Android ExercisePrompt in Exercises.kt):
// course-language text through AnnotatedText with its play and play-slowly buttons above it,
// then the sentence romanization; English as plain text. A tapped word's tip shows under the
// prompt until the next tap on the same word.

public struct ExercisePrompt: View {
    private let exercise: ExerciseArtifact
    private let courseCode: String
    private let hasVoice: Bool
    private let onPlay: () -> Void
    private let onInstallVoice: () -> Void
    private let onPlaySlow: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var tip: WordTip?

    public init(
        exercise: ExerciseArtifact,
        courseCode: String,
        hasVoice: Bool,
        onPlay: @escaping () -> Void = {},
        onInstallVoice: @escaping () -> Void = {},
        onPlaySlow: @escaping () -> Void = {}
    ) {
        self.exercise = exercise
        self.courseCode = courseCode
        self.hasVoice = hasVoice
        self.onPlay = onPlay
        self.onInstallVoice = onInstallVoice
        self.onPlaySlow = onPlaySlow
    }

    private var palette: AppPalette {
        return colorScheme == .dark ? AppPalette.dark : AppPalette.light
    }

    private var isNative: Bool {
        return Languages.isNativeText(courseCode, exercise.prompt)
    }

    private var canSpeak: Bool {
        return hasVoice || !(exercise.promptAudio ?? [:]).isEmpty
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isNative {
                audioRow
                SentenceRomanization(exercise.prompt, authored: exercise.promptRomanization, scriptMode: exercise.scriptMode, tags: exercise.tags)
            }
            promptText
            if let shown = tip {
                tipBubble(shown)
            }
            if exercise.scriptMode == .romanized && exercise.type == .typeIn {
                Text("Type this one in Latin letters (romanized), not the native script.")
                    .font(.footnote)
                    .foregroundStyle(Color(argb: palette.textMuted))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var audioRow: some View {
        HStack(spacing: 8) {
            audioButton(size: 48, fill: canSpeak ? palette.current : palette.locked,
                        description: canSpeak ? "Play audio" : "No voice installed for this language. Install one",
                        action: canSpeak ? onPlay : onInstallVoice) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.white)
            }
            if canSpeak {
                audioButton(size: 40, fill: (palette.current & 0x00FFFFFF) | 0xBF000000, description: "Play slowly", action: onPlaySlow) {
                    Text("\u{1F422}").font(.system(size: 20))
                }
            }
        }
    }

    private func audioButton<Content: View>(size: CGFloat, fill: UInt32, description: String, action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color(argb: fill))
                content()
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(description)
    }

    @ViewBuilder
    private var promptText: some View {
        if isNative {
            AnnotatedText(exercise.prompt, scriptMode: exercise.scriptMode, tags: exercise.tags, fontSize: 20, onTip: { tapped in
                // Tapping the open word again closes its tip.
                tip = (tip?.word == tapped.word) ? nil : tapped
            })
        } else {
            Text(exercise.prompt)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(argb: palette.text))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tipBubble(_ shown: WordTip) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(shown.word).font(.system(size: 15, weight: .bold))
            ForEach(Array(shown.lines.enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(size: 14))
            }
        }
        .foregroundStyle(Color(argb: palette.text))
        .padding(8)
        .background(RoundedCornerBox(fill: palette.surface, edge: palette.border, radius: Radii.standard.sm, lineWidth: 1))
        .onTapGesture { tip = nil }
    }
}

/// A rounded box with a fill and an edge, shared by tips and tiles.
struct RoundedCornerBox: View {
    let fill: UInt32
    let edge: UInt32
    let radius: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color(argb: fill))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color(argb: edge), lineWidth: lineWidth)
            )
    }
}
