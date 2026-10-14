// Port of Android ScriptFonts.kt's PersianFace (pure selection logic only).

/// The Persian faces a learner can pick.
public enum PersianFace: CaseIterable, Equatable, Sendable {
    /// Bundled, the default.
    case vazirmatn

    /// The stored pref's family name; nil for the bundled default.
    public var family: String? {
        switch self {
        case .vazirmatn: return nil
        }
    }

    public var label: String {
        switch self {
        case .vazirmatn: return "Vazirmatn"
        }
    }

    /// Whether the font file ships in the app (otherwise it is looked up by name).
    public var isBundled: Bool { return self == .vazirmatn }

    /// The stored family name's face, or the default for none (or one not offered).
    public static func of(_ family: String?) -> PersianFace {
        return allCases.first(where: { $0.family == family }) ?? .vazirmatn
    }
}
