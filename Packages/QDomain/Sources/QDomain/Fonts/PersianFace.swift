// Port of Android ScriptFonts.kt's PersianFace (pure selection logic only).

/// The Persian faces a learner can pick.
public enum PersianFace: CaseIterable, Equatable, Sendable {
    /// Bundled, the default.
    case vazirmatn
    /// The system's traditional Naskh face.
    case notoNaskh

    /// The stored pref's family name; nil for the bundled default.
    public var family: String? {
        switch self {
        case .vazirmatn: return nil
        case .notoNaskh: return "Noto Naskh Arabic"
        }
    }

    public var label: String {
        switch self {
        case .vazirmatn: return "Vazirmatn"
        case .notoNaskh: return "Noto Naskh"
        }
    }

    /// Whether the font file ships in the app (otherwise it is looked up by name).
    public var isBundled: Bool { return self == .vazirmatn }

    /// The stored family name's face, or the default for none (or one not offered).
    public static func of(_ family: String?) -> PersianFace {
        return allCases.first(where: { $0.family == family }) ?? .vazirmatn
    }
}
