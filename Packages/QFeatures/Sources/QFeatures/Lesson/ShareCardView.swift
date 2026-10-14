import SwiftUI
import CoreGraphics
import QDesign
import UniformTypeIdentifiers

/// The share card, drawn at a fixed 360 x 360 pt (rendered at 3x = Android's 1080 x 1080 px).
/// Fixed sizes and colors on purpose: it is an image, so it ignores Dynamic Type and dark mode and
/// looks the same wherever it is shared (Android draws it the same way).
public struct ShareCardView: View {
    public static let side: CGFloat = 360
    public static let renderScale: CGFloat = 3

    private let content: ShareCardContent
    private let fonts: ScriptFonts

    public init(content: ShareCardContent, fonts: ScriptFonts = ScriptFonts()) {
        self.content = content
        self.fonts = fonts
    }

    private static let green = Color(argb: 0xFF58CC02)
    private static let greenDeep = Color(argb: 0xFF3E9A00)
    private static let ink = Color(argb: 0xFF1F1F2E)
    private static let muted = Color(argb: 0xFF6B6B80)
    private static let fireStart = Color(argb: 0xFFFF9600)
    private static let fireEnd = Color(argb: 0xFFE5381E)

    public var body: some View {
        ZStack {
            LinearGradient(colors: [Self.green, Self.greenDeep], startPoint: .top, endPoint: .bottom)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .padding(20)
            VStack(spacing: 0) {
                line(content.headline, size: 24, color: Self.ink)
                    .padding(.top, 34)
                if let xp = content.xpLine {
                    line(xp, size: 37, color: Self.green).padding(.top, 14)
                }
                if let streak = content.streakLine {
                    Text(streak)
                        .font(.system(size: 26, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .foregroundStyle(LinearGradient(colors: [Self.fireStart, Self.fireEnd], startPoint: .leading, endPoint: .trailing))
                        .padding(.top, 14)
                }
                Spacer(minLength: 8)
                if let word = content.word {
                    Text(word)
                        .font(fonts.font(.persian, size: 44, weight: .bold))
                        .foregroundColor(Self.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                }
                if let reading = content.reading {
                    line(reading, size: 17, color: Self.muted, weight: .regular).padding(.top, 6)
                }
                if let gloss = content.glossLine {
                    line(gloss, size: 17, color: Self.muted, weight: .regular).padding(.top, 6)
                }
                Spacer(minLength: 8)
                line("ParsLing", size: 16, color: Self.green)
                    .padding(.bottom, 34)
            }
            .padding(.horizontal, 40)
        }
        .frame(width: Self.side, height: Self.side)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(content.accessibilityText))
    }

    private func line(_ text: String, size: CGFloat, color: Color, weight: Font.Weight = .bold) -> some View {
        Text(text)
            .font(.system(size: size, weight: weight))
            .foregroundColor(color)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
    }
}

/// Renders the card to an image. Throws instead of returning nothing so the caller can show the failure.
@MainActor
public enum ShareCardRenderer {
    public enum RenderError: Error, Equatable {
        case renderFailed
    }

    public static func cgImage(for content: ShareCardContent, fonts: ScriptFonts = ScriptFonts()) throws -> CGImage {
        try Task.checkCancellation()
        let renderer = ImageRenderer(content: ShareCardView(content: content, fonts: fonts))
        renderer.scale = ShareCardView.renderScale
        guard let image = renderer.cgImage else { throw RenderError.renderFailed }
        return image
    }
}

/// The rendered card as a shareable file (a named PNG in the temp directory, so receivers see a sensible name).
public struct ShareCardImage: Transferable {
    public let png: Data
    public let fileName: String

    public init(png: Data, fileName: String) {
        self.png = png
        self.fileName = fileName
    }

    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { item in
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(item.fileName)
            try item.png.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

/// Preview of the card with the system share button. Renders in `.task(id:)`, so it re-renders when the
/// content changes, is cancelled with the view, keeps a finished render across reappearance, and offers a
/// retry on failure.
public struct ShareCardPreview: View {
    enum Phase {
        case loading
        case ready(ShareCardContent, ShareCardImage, Image)
        case failed
    }

    private struct TaskKey: Equatable {
        let content: ShareCardContent
        let attempt: Int
    }

    private let content: ShareCardContent
    @State private var phase: Phase = .loading
    @State private var attempt = 0

    public init(content: ShareCardContent) {
        self.content = content
    }

    public var body: some View {
        VStack(spacing: 16) {
            switch phase {
            case .loading:
                ProgressView("Preparing card")
            case .failed:
                Text("Could not prepare the card.")
                    .foregroundStyle(.red)
                Button("Try again") {
                    phase = .loading
                    attempt += 1
                }
            case .ready(_, let item, let preview):
                preview
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel(Text(content.accessibilityText))
                ShareLink(item: item, message: Text(content.shareText),
                          preview: SharePreview(content.headline, image: preview)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .task(id: TaskKey(content: content, attempt: attempt)) {
            await load()
        }
    }

    private func load() async {
        if case .ready(let done, _, _) = phase, done == content { return }
        do {
            let cg = try ShareCardRenderer.cgImage(for: content)
            let data = try ShareCardPNG.encode(cg)
            try Task.checkCancellation()
            phase = .ready(content, ShareCardImage(png: data, fileName: content.fileName),
                           Image(decorative: cg, scale: ShareCardView.renderScale))
        } catch is CancellationError {
            // Cancelled with the view; the next appearance renders again.
        } catch {
            phase = .failed
        }
    }
}
