import CoreGraphics

/// Sizes shared by the keyboard views (Android `ScriptKeyboard.kt`).
public enum KeyboardMetrics {
    public static let keyHeight: CGFloat = 46
    public static let candidateWidth: CGFloat = 48
    public static let candidateHeight: CGFloat = 48
    public static let stripGap: CGFloat = 6
    public static let rowSpacing: CGFloat = 6
    public static let keySpacing: CGFloat = 4
    public static let sidePadding: CGFloat = 4
    public static let bottomPadding: CGFloat = 6
    public static let maxLabelScale: CGFloat = 1.3

    /// Space kept above the first key row: the candidate band, or the header when it is taller.
    public static var bandHeight: CGFloat { candidateHeight + stripGap }

    public static func keysTop(headerHeight: CGFloat) -> CGFloat {
        max(bandHeight, headerHeight)
    }

    /// Key label size under Dynamic Type: grows with the text size up to 1.3x, never shrinks.
    public static func labelSize(base: CGFloat, scale: CGFloat) -> CGFloat {
        base * min(max(scale, 1), maxLabelScale)
    }
}

/// Where the candidate cells sit: a strip centered over the pressed key, clamped to the keyboard.
public enum CandidateStripGeometry {
    public static func cellRects(anchor: CGRect, count: Int, rtl: Bool, containerWidth: CGFloat) -> [CGRect] {
        guard count > 0 else { return [] }
        let cell = KeyboardMetrics.candidateWidth
        let height = KeyboardMetrics.candidateHeight
        let stripWidth = cell * CGFloat(count)
        let maxLeft = max(containerWidth - stripWidth, 0)
        let left = min(max(anchor.midX - stripWidth / 2, 0), maxLeft)
        let top = anchor.minY - height - KeyboardMetrics.stripGap
        var rects: [CGRect] = []
        for i in 0..<count {
            // Persian candidates read right to left: the first (already typed) one sits rightmost.
            let slot = rtl ? count - 1 - i : i
            rects.append(CGRect(x: left + CGFloat(slot) * cell, y: top, width: cell, height: height))
        }
        return rects
    }

    public static func hitIndex(at point: CGPoint, in rects: [CGRect]) -> Int? {
        rects.firstIndex(where: { $0.contains(point) })
    }

    /// Width of each key in a row after spacing, split by weight.
    public static func keyWidths(weights: [Double], total: CGFloat, spacing: CGFloat) -> [CGFloat] {
        guard !weights.isEmpty else { return [] }
        let sum = weights.reduce(0, +)
        let avail = max(total - spacing * CGFloat(weights.count - 1), 0)
        guard sum > 0 else { return weights.map { _ in 0 } }
        return weights.map { avail * CGFloat($0 / sum) }
    }
}
