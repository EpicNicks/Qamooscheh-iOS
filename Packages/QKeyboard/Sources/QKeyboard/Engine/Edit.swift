import Foundation

/// A change to the text being typed: delete `delete` Unicode scalars before the
/// cursor, then insert `insert`. Counts are scalars (not grapheme clusters) so
/// a letter followed by a ZWNJ is two deletions, as on Android.
public struct Edit: Equatable, Sendable {
    public var delete: Int
    public var insert: String

    public init(delete: Int, insert: String) {
        self.delete = delete
        self.insert = insert
    }

    public static let none = Edit(delete: 0, insert: "")

    public func applyTo(_ text: String) -> String {
        var scalars = Array(text.unicodeScalars)
        scalars.removeLast(min(max(delete, 0), scalars.count))
        scalars.append(contentsOf: insert.unicodeScalars)
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    /// Applies at `caret` (a scalar offset) instead of the end: engines only edit the end of
    /// what they are handed, so they get the text before the caret and what follows stays put.
    /// Returns the new text and the new caret offset (in scalars).
    public func applyAt(_ text: String, caret: Int) -> (text: String, caret: Int) {
        let scalars = Array(text.unicodeScalars)
        let at = min(max(caret, 0), scalars.count)
        var headView = String.UnicodeScalarView()
        headView.append(contentsOf: scalars[0..<at])
        let head = applyTo(String(headView))
        var tailView = String.UnicodeScalarView()
        tailView.append(contentsOf: scalars[at...])
        return (head + String(tailView), head.unicodeScalars.count)
    }
}
