import SwiftUI
import QDesign

/// Help & FAQ (web HelpPage, Android HelpScreen): each entry expands in place.
/// `initialEntryId` opens one up front (the web's /help#id deep link).
public struct HelpView: View {
    @State private var open: Set<String>

    public init(initialEntryId: String? = nil) {
        _open = State(initialValue: initialOpenIds(initialEntryId))
    }

    public var body: some View {
        ScrollView {
            HelpContent(open: $open).padding(16)
        }
        .navigationTitle("Help & FAQ")
    }
}

struct HelpContent: View {
    @Binding var open: Set<String>
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        VStack(alignment: .leading, spacing: 12) {
            ForEach(helpFaq, id: \.id) { entry in
                FaqCard(entry: entry, expanded: open.contains(entry.id), p: p) {
                    open = toggled(open, entry.id)
                }
            }
        }
    }
}

private struct FaqCard: View {
    let entry: FaqEntry
    let expanded: Bool
    let p: AppPalette
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack(alignment: .center, spacing: 8) {
                    Text(entry.question)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(Color(argb: p.text))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(expanded ? "\u{2212}" : "+")
                        .font(.title3)
                        .foregroundColor(Color(argb: p.textMuted))
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(entry.blocks.enumerated()), id: \.offset) { _, block in
                        switch block {
                        case .paragraph(let text):
                            bodyText(text, p)
                        case .bullets(let items):
                            BulletList(items: items, p: p)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(argb: p.surface))
        .overlay(RoundedRectangle(cornerRadius: Radii.standard.md).stroke(Color(argb: p.border), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radii.standard.md))
    }
}

private func bodyText(_ text: String, _ p: AppPalette) -> some View {
    Text(text).font(.body).foregroundColor(Color(argb: p.text)).fixedSize(horizontal: false, vertical: true)
}

private struct BulletList: View {
    let items: [String]
    let p: AppPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    bodyText("\u{2022}", p)
                    bodyText(item, p)
                }
            }
        }
    }
}

/// About ParsLing (web AboutPage, Android AboutScreen) plus the installed app version.
public struct AboutView: View {
    private let version: String?

    /// `version` overrides the line read from the app bundle (tests, previews).
    public init(version: String? = nil) {
        self.version = version ?? AboutContent.bundleVersionLine()
    }

    public var body: some View {
        ScrollView {
            AboutContentView(version: version).padding(16)
        }
        .navigationTitle("About")
    }
}

struct AboutContentView: View {
    let version: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        VStack(alignment: .leading, spacing: 12) {
            Text("ParsLing").font(.largeTitle.weight(.bold)).foregroundColor(Color(argb: p.primary))
            bodyText(AboutContent.tagline, p)
            SettingsCard("What it is", p) { bodyText(AboutContent.whatItIs, p) }
            SettingsCard("How it works", p) { BulletList(items: AboutContent.howItWorks, p: p) }
            SettingsCard("Languages", p) { bodyText(AboutContent.languages, p) }
            SettingsCard("Where it's at", p) { bodyText(AboutContent.whereItsAt, p) }
            if let version = version {
                Text(version).font(.footnote).foregroundColor(Color(argb: p.textMuted))
            }
        }
    }
}

/// Either screen with sample state, for snapshots (Help has three entries open).
public struct HelpAboutShowcase: View {
    private let showAbout: Bool
    @State private var open: Set<String> = ["tts-voice", "saved-words", "review-intensity"]

    public init(showAbout: Bool) {
        self.showAbout = showAbout
    }

    public var body: some View {
        ScrollView {
            if showAbout {
                AboutContentView(version: AboutContent.versionLine(short: "1.0", build: "42")).padding(16)
            } else {
                HelpContent(open: $open).padding(16)
            }
        }
    }
}
