import SwiftUI
import QDesign
#if os(iOS)
import UIKit
import SafariServices
#elseif os(macOS)
import AppKit
#endif

/// A URL to show in the in-app browser sheet.
struct BrowserTarget: Identifiable, Equatable {
    let url: URL
    var id: String { url.absoluteString }
}

/// "Look up "<query>" in:" then one full-width button per dictionary (Wiktionary, then Vajehyab), each with the
/// site's bundled icon, its name and an open-externally mark. Nothing is fetched until a button is pressed.
struct DictionaryLookupView: View {
    let query: String
    let links: [DictionaryLink]
    let p: AppPalette
    let onOpen: (URL) -> Void
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dictionaryLookupHeading(query: query))
                .font(.subheadline).foregroundColor(Color(argb: p.textMuted))
            ForEach(links, id: \.site) { link in
                let shape = RoundedRectangle(cornerRadius: Radii.standard.lg)
                Button(action: { onOpen(link.url) }) {
                    HStack(spacing: 12) {
                        DictionaryIcon(site: link.site, size: iconSize)
                        Text(link.site.name).font(.body.weight(.semibold)).foregroundColor(Color(argb: p.text))
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(Color(argb: p.textMuted))
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(argb: p.surface))
                    .clipShape(shape)
                    .overlay(shape.stroke(Color(argb: p.border), lineWidth: 2))
                    .contentShape(shape)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(link.site.name)
                .accessibilityHint("Opens \(link.site.name) in a browser")
                .accessibilityAddTraits(.isLink)
            }
        }
    }
}

/// A dictionary's bundled icon; an empty square of the same size if the resource is missing.
struct DictionaryIcon: View {
    let site: DictionarySite
    let size: CGFloat

    var body: some View {
        Group {
            if let image = dictionaryIconImage(site) {
                image.resizable().interpolation(.high).scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
        .accessibilityHidden(true)
    }
}

func dictionaryIconImage(_ site: DictionarySite) -> Image? {
    guard let url = site.iconURL else { return nil }
    #if os(iOS)
    guard let image = UIImage(contentsOfFile: url.path) else { return nil }
    return Image(uiImage: image)
    #elseif os(macOS)
    guard let image = NSImage(contentsOf: url) else { return nil }
    return Image(nsImage: image)
    #else
    return nil
    #endif
}

#if os(iOS)
/// SFSafariViewController for SwiftUI: the page opens unmodified, in app.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif

extension View {
    /// Presents `target` in the in-app browser (SFSafariViewController); other platforms hand it to the system.
    @ViewBuilder
    func inAppBrowser(_ target: Binding<BrowserTarget?>) -> some View {
        #if os(iOS)
        self.sheet(item: target) { item in
            SafariView(url: item.url).ignoresSafeArea()
        }
        #else
        self.modifier(SystemBrowserOpener(target: target))
        #endif
    }
}

#if !os(iOS)
private struct SystemBrowserOpener: ViewModifier {
    @Binding var target: BrowserTarget?
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content.onChange(of: target) { _, item in
            guard let item = item else { return }
            openURL(item.url)
            target = nil
        }
    }
}
#endif
