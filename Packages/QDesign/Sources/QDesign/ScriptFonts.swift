import SwiftUI
import CoreText
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The scripts course content is set in.
public enum ScriptKind: CaseIterable, Equatable, Sendable {
    case persian
    case japanese
    case latin
}

/// Text roles for native-script content, with a fixed point size each.
public enum ScriptTextStyle: CaseIterable, Equatable, Sendable {
    case caption
    case body
    case prompt
    case display

    public var size: CGFloat {
        switch self {
        case .caption: return 13
        case .body: return 17
        case .prompt: return 22
        case .display: return 34
        }
    }
}

/// Font names and registration, the SwiftUI side of Android ScriptFonts.kt.
/// Vazirmatn (OFL) is the bundled Persian default; "Noto Naskh Arabic" is an optional Persian
/// choice used only when installed; Japanese and Latin use the system face (Android uses the
/// system Noto Sans CJK). Anything not installed falls back to the system face.
public struct ScriptFonts {
    public static let vazirmatnFamily = "Vazirmatn"
    public static let notoNaskhFamily = "Noto Naskh Arabic"

    /// Font file names looked up in the bundle, without directory.
    public static let bundledFileNames: [String] = ["Vazirmatn[wght].ttf", "Vazirmatn-VariableFont_wght.ttf", "Vazirmatn.ttf"]

    /// The learner's stored Persian family (nil for the bundled default).
    public let persianFamily: String?
    private let isAvailable: (String) -> Bool

    public init(persianFamily: String? = nil, isAvailable: @escaping (String) -> Bool = ScriptFonts.systemHasFamily) {
        self.persianFamily = persianFamily
        self.isAvailable = isAvailable
    }

    /// The custom family used for `script`, or nil when the system face is used.
    public func resolvedFamily(for script: ScriptKind) -> String? {
        guard let wanted = requestedFamily(for: script) else { return nil }
        return isAvailable(wanted) ? wanted : nil
    }

    /// The family `script` would use if installed, ignoring availability.
    public func requestedFamily(for script: ScriptKind) -> String? {
        switch script {
        case .japanese, .latin:
            return nil
        case .persian:
            return persianFamily == ScriptFonts.notoNaskhFamily ? ScriptFonts.notoNaskhFamily : ScriptFonts.vazirmatnFamily
        }
    }

    public func font(_ script: ScriptKind, size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let family = resolvedFamily(for: script) {
            return Font.custom(family, size: size).weight(weight)
        }
        return Font.system(size: size, weight: weight)
    }

    public func font(_ script: ScriptKind, style: ScriptTextStyle, weight: Font.Weight = .regular) -> Font {
        return font(script, size: style.size, weight: weight)
    }

    /// Whether a font family is installed (registered or built in).
    public static func systemHasFamily(_ name: String) -> Bool {
        #if canImport(UIKit)
        return UIFont.familyNames.contains(name) || UIFont(name: name, size: 12) != nil
        #elseif canImport(AppKit)
        return NSFontManager.shared.availableFontFamilies.contains(name) || NSFont(name: name, size: 12) != nil
        #else
        return false
        #endif
    }

    /// Registers any bundled font files for this process; returns how many registered.
    /// Returns 0 when the files are absent, so callers fall back to the system face.
    @discardableResult
    public static func registerBundledFonts(in bundles: [Bundle] = [Bundle.main]) -> Int {
        var count = 0
        for bundle in bundles {
            for file in bundledFileNames {
                let ns = file as NSString
                let name = ns.deletingPathExtension
                let ext = ns.pathExtension
                let url = bundle.url(forResource: name, withExtension: ext) ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "Fonts")
                guard let fileURL = url else { continue }
                var error: Unmanaged<CFError>?
                if CTFontManagerRegisterFontsForURL(fileURL as CFURL, .process, &error) {
                    count += 1
                }
            }
        }
        return count
    }
}

/// A specimen of each script at each style, for snapshotting and eyeballing the bundled faces.
public struct ScriptSpecimenSheet: View {
    private let fonts: ScriptFonts

    public init(fonts: ScriptFonts = ScriptFonts()) {
        self.fonts = fonts
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(ScriptTextStyle.allCases, id: \.self) { style in
                VStack(alignment: .leading, spacing: 2) {
                    Text("Persian \(String(describing: style))")
                        .font(.caption2)
                    Text("سلام، حال شما چطور است؟ ۱۲۳")
                        .font(fonts.font(.persian, style: style))
                        .environment(\.layoutDirection, .rightToLeft)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Japanese \(String(describing: style))")
                        .font(.caption2)
                    Text("こんにちは、お元気ですか。漢字")
                        .font(fonts.font(.japanese, style: style))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .foregroundColor(.black)
    }
}
