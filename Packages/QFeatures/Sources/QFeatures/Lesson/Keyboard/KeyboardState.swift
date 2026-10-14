import SwiftUI
import QKeyboard

/// One keyboard's engine plus the transient UI state around it: which key the candidates hang
/// from and which candidate a drag is over (Android `KeyboardState`).
public final class KeyboardState: ObservableObject {
    @Published public private(set) var engine: any ScriptKeyboardEngine
    @Published public internal(set) var anchorKeyId: String?
    @Published public internal(set) var hovered: Int?
    @Published var activeKeyId: String?

    var keyFrames: [String: CGRect] = [:]
    var width: CGFloat = 0

    public init(method: InputMethod) {
        self.engine = method.makeEngine()
    }

    public var layout: KeyboardLayout { engine.layout }
    public var candidates: [String]? { engine.candidates }
    public var pending: String? { engine.pending }

    public static func keyId(row: Int, index: Int) -> String { "\(row):\(index)" }

    /// Commits anything pending; call before submitting the answer or switching engines.
    public func finalize() -> Edit {
        let edit = engine.finalize()
        anchorKeyId = nil
        hovered = nil
        return edit
    }

    public func switchTo(_ method: InputMethod) {
        engine = method.makeEngine()
        anchorKeyId = nil
        hovered = nil
        activeKeyId = nil
    }

    /// A finger went down on a key. False when that key's touch is already live (repeat events).
    func beginTouch(keyId: String) -> Bool {
        if activeKeyId == keyId { return false }
        activeKeyId = keyId
        return true
    }

    /// The finger lifted: returns the candidate it was over, if any.
    func endTouch() -> Int? {
        let over = hovered
        activeKeyId = nil
        hovered = nil
        return over
    }

    /// The gesture was cancelled (no end event): clear the pressed state so the next tap registers.
    func cancelTouch() {
        activeKeyId = nil
        hovered = nil
    }

    public func press(_ action: KeyAction, keyId: String, textBefore: String) -> Edit {
        let edit = engine.press(action, textBefore: textBefore)
        anchorKeyId = engine.candidates != nil ? keyId : nil
        hovered = nil
        return edit
    }

    public func pick(_ index: Int) -> Edit {
        let edit = engine.pick(index)
        anchorKeyId = nil
        hovered = nil
        return edit
    }

    /// The cells of the open candidate strip, in keyboard coordinates. Without a key to hang
    /// from (a hardware key) they sit centered over the keys.
    func stripRects(reserve: CGFloat) -> [CGRect] {
        guard let list = engine.candidates else { return [] }
        let fallback = CGRect(x: width / 2 - 1, y: reserve, width: 2, height: 1)
        let anchor = anchorKeyId.flatMap { keyFrames[$0] } ?? fallback
        return CandidateStripGeometry.cellRects(anchor: anchor, count: list.count, rtl: engine.layout.rtlCandidates, containerWidth: width)
    }
}
