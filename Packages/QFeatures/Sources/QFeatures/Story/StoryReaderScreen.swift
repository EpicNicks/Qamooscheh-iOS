import SwiftUI
import QDesign
import QDomain
import QModel

// The story reader (web StoryReader): the whole chapter, one card per sentence, a segmented timeline with play and
// pause, per-line play, tappable words with a small card, and a button to the chapter's cloze lessons. Thin: the
// state and rules are in StoryReaderModel and QDomain.

private let savedGold = Color(argb: 0xFFFFB800)
private let savedVerbPurple = Color(argb: 0xFF8B5CF6)

public struct StoryReaderScreen: View {
    @ObservedObject private var model: StoryReaderModel
    private let onCloze: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    public init(model: StoryReaderModel, onCloze: @escaping () -> Void) {
        self.model = model
        self.onCloze = onCloze
    }

    public var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        ZStack(alignment: .bottomTrailing) {
            Color(argb: p.bg).ignoresSafeArea()
            switch model.phase {
            case .loading:
                ProgressView().accessibilityLabel("Loading").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unavailable:
                Text("This story is not on this device yet.")
                    .font(.callout)
                    .foregroundColor(Color(argb: p.textMuted))
                    .padding(Spacing.standard.s3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready:
                content(p)
                clozeButton(p)
            }
        }
        .navigationTitle(model.title.isEmpty ? "Story" : model.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Toggle("Follow the playing line", isOn: $model.autoscroll)
                    Toggle("Speak tapped words", isOn: $model.speakHoveredWords)
                } label: {
                    Image(systemName: "ellipsis.circle").accessibilityLabel("Reader options")
                }
            }
        }
        .task { await model.load() }
        .onDisappear { model.stop() }
    }

    private func content(_ p: AppPalette) -> some View {
        VStack(spacing: 0) {
            timeline(p)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Spacing.standard.s2) {
                        ForEach(Array(model.lines.enumerated()), id: \.offset) { index, line in
                            lineCard(index: index, line: line, p: p).id(index)
                        }
                    }
                    .padding(.horizontal, Spacing.standard.s3)
                    .padding(.top, Spacing.standard.s2)
                    .padding(.bottom, 96)
                }
                .onChange(of: model.position) { _, _ in
                    guard let target = model.followedLine else { return }
                    withAnimation { proxy.scrollTo(target, anchor: UnitPoint(x: 0.5, y: 0.3)) }
                }
            }
            if model.tip != nil { tipCard(p) }
        }
    }

    private func timeline(_ p: AppPalette) -> some View {
        HStack(spacing: Spacing.standard.s2) {
            Button(action: { model.toggleMain() }) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color(argb: p.primaryContrast))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color(argb: p.primary)))
            }
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play story")
            HStack(spacing: 3) {
                ForEach(Array(model.segments.enumerated()), id: \.offset) { index, state in
                    Button(action: { model.seek(to: index) }) {
                        Capsule()
                            .fill(segmentColor(state, p))
                            .frame(height: 6)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Sentence \(index + 1)")
                }
            }
        }
        .padding(.horizontal, Spacing.standard.s3)
        .padding(.vertical, Spacing.standard.s2)
    }

    private func segmentColor(_ state: StorySegmentState, _ p: AppPalette) -> Color {
        switch state {
        case .filled: return Color(argb: p.primary)
        case .current: return Color(argb: p.primary).opacity(0.55)
        case .upcoming: return Color(argb: p.border)
        }
    }

    private func lineCard(index: Int, line: StoryReaderLine, p: AppPalette) -> some View {
        let active = model.playingLine == index || (model.isPlaying && model.position == index)
        let rtl = Languages.detectScriptDirection(line.text) == .rtl
        return HStack(alignment: .top, spacing: Spacing.standard.s2) {
            if model.hasPlayButton(index) {
                Button(action: { model.playLine(index) }) {
                    Image(systemName: model.playingLine == index ? "speaker.wave.2.fill" : "play.circle")
                        .font(.system(size: 22))
                        .foregroundColor(Color(argb: p.primary))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Play sentence \(index + 1)")
            }
            VStack(alignment: .leading, spacing: 4) {
                if let speaker = line.speaker, !speaker.isEmpty {
                    Text(speaker).font(.caption).foregroundColor(Color(argb: p.textMuted))
                }
                lineText(index: index, rtl: rtl, p: p)
                if let roman = line.romanization, !roman.isEmpty {
                    Text(roman)
                        .font(.system(size: 14))
                        .foregroundColor(Color(argb: p.textMuted))
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.standard.s2)
        .background(
            RoundedRectangle(cornerRadius: Radii.standard.md, style: .continuous)
                .fill(Color(argb: active ? p.infoBg : p.surface)))
        .overlay(
            RoundedRectangle(cornerRadius: Radii.standard.md, style: .continuous)
                .stroke(Color(argb: active ? p.primary : p.border), lineWidth: active ? 2 : 1))
    }

    // One Text, so Persian letters still join across the tappable words. Saved words sit on gold, saved verbs on purple.
    private func lineText(index: Int, rtl: Bool, p: AppPalette) -> some View {
        let ink = Color(argb: p.text)
        let pieces: [StoryLineWord] = index < model.words.count ? model.words[index] : []
        var attributed = AttributedString()
        for word in pieces {
            var piece = AttributedString(word.text)
            if word.isTappable, let url = URL(string: "qamooscheh-story://word/\(index)/\(word.index)") {
                piece.link = url
                piece.foregroundColor = ink
            }
            switch model.highlight(word) {
            case .saved: piece.backgroundColor = savedGold.opacity(0.45)
            case .savedVerb: piece.backgroundColor = savedVerbPurple.opacity(0.4)
            case .none: break
            }
            attributed.append(piece)
        }
        let words = model.words
        let tap: (StoryLineWord) -> Void = { model.tapWord($0) }
        return Text(attributed)
            .font(DirectionalText.font(size: 22, rtl: rtl, family: nil))
            .foregroundStyle(ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .directionalText(rtl: rtl)
            .environment(\.openURL, OpenURLAction { url in
                let parts = url.pathComponents.filter { $0 != "/" }
                guard url.scheme == "qamooscheh-story", parts.count == 2,
                      let line = Int(parts[0]), let at = Int(parts[1]),
                      line < words.count, let word = words[line].first(where: { $0.index == at }) else { return .discarded }
                tap(word)
                return .handled
            })
    }

    private func tipCard(_ p: AppPalette) -> some View {
        let current = model.tip
        let isSaved = current?.isSaved == true
        let color: Color
        switch current?.highlight ?? .none {
        case .saved: color = savedGold
        case .savedVerb: color = savedVerbPurple
        case .none: color = Color(argb: p.border)
        }
        return HStack(alignment: .center, spacing: Spacing.standard.s2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.tipText).font(.system(size: 20, weight: .semibold)).foregroundColor(Color(argb: p.text))
                Text(current?.hint ?? "").font(.system(size: 16)).foregroundColor(Color(argb: p.textMuted))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let tag = current?.tag, !tag.isEmpty {
                Button(action: { Task { await model.toggleTipSaved() } }) {
                    Image(systemName: isSaved ? "star.fill" : "star")
                        .font(.system(size: 22))
                        .foregroundColor(isSaved ? color : Color(argb: p.textMuted))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(isSaved ? "Remove from saved words" : "Save word")
            }
            Button(action: { model.dismissTip() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(argb: p.textMuted))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
        }
        .padding(Spacing.standard.s3)
        .background(RoundedRectangle(cornerRadius: Radii.standard.lg, style: .continuous).fill(Color(argb: p.surface)))
        .overlay(RoundedRectangle(cornerRadius: Radii.standard.lg, style: .continuous).stroke(color, lineWidth: 2))
        .padding(.horizontal, Spacing.standard.s3)
        .padding(.bottom, Spacing.standard.s2)
    }

    private func clozeButton(_ p: AppPalette) -> some View {
        Button(action: {
            model.stop()
            onCloze()
        }) {
            Label("Practice", systemImage: "square.and.pencil")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color(argb: p.primaryContrast))
                .padding(.horizontal, Spacing.standard.s3)
                .frame(minHeight: 48)
                .background(Capsule().fill(Color(argb: p.primary)))
        }
        .padding(Spacing.standard.s3)
        .padding(.bottom, model.tip == nil ? 0 : 84)
        .accessibilityLabel("Practice this story")
    }
}
