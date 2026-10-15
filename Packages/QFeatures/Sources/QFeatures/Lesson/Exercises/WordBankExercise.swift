import SwiftUI
import QDesign
import QDomain
import QModel

// Tap tiles into order (web WordBankExercise, matching Android WordBankExercise in Exercises.kt).
// Tap a placed tile to put it back. The bank is shuffled once per exercise, so its order never
// gives the answer away. On review the placed tiles are colored against the closest correct
// order, and bank tiles that order still needed are outlined. Dragging tiles is not ported yet.

/// Flows its subviews in lines of the proposed width, right to left when `rtl`.
struct TileFlowLayout: Layout {
    var rtl: Bool
    var centered: Bool
    var spacing: CGFloat = 8

    private func frames(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
        return TileFlowGeometry.frames(sizes: sizes, width: width, rtl: rtl, centered: centered, spacing: spacing)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width: CGFloat
        if let w = proposal.width, w.isFinite {
            width = w
        } else {
            width = subviews.reduce(CGFloat(0)) { $0 + $1.sizeThatFits(.unspecified).width } + spacing * CGFloat(max(0, subviews.count - 1))
        }
        return CGSize(width: width, height: TileFlowGeometry.height(of: frames(subviews, width: width)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let list = frames(subviews, width: bounds.width)
        for (i, subview) in subviews.enumerated() {
            let f = list[i]
            subview.place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), anchor: .topLeading, proposal: ProposedViewSize(f.size))
        }
    }
}

/// One tile: the course text in a rounded box colored by its look.
struct ExerciseTile: View {
    let text: String
    let exercise: ExerciseArtifact
    let look: TileLook
    var placed: Bool = false
    var position: Int? = nil
    let enabled: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var colors: (fill: UInt32, edge: UInt32) {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        switch look {
        case .right: return (p.successBg, p.success)
        case .swapped: return (p.warningBg, p.warning)
        case .wrong: return (p.dangerBg, p.danger)
        case .missing: return (p.bg, p.current)
        case .plain: return (p.surface, p.border)
        }
    }

    var body: some View {
        let c = colors
        let a11y = TileAccessibility.make(text: text, placed: placed, position: position, look: look, reviewing: !enabled)
        Button(action: action) {
            AnnotatedText(text, scriptMode: exercise.scriptMode, tags: exercise.tags, fontSize: 18)
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedCornerBox(fill: c.fill, edge: c.edge, radius: Radii.standard.sm, lineWidth: 2))
                .overlay(alignment: .topTrailing) {
                    if let symbol = look.cueSymbol {
                        Image(systemName: symbol)
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(Color(argb: c.edge))
                            .padding(3)
                            .accessibilityHidden(true)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(a11y.label)
        .accessibilityValue(a11y.value)
        .accessibilityHint(a11y.hint)
        .accessibilityAddTraits(a11y.isSelected ? [.isSelected] : [])
    }
}

public struct WordBankExercise: View {
    private let exercise: ExerciseArtifact
    private let courseCode: String
    private let reviewed: ReviewedAnswer?
    private let onTilePicked: (String) -> Void
    private let onAnswerChange: (String?) -> Void

    @State private var state: WordBankState
    @Environment(\.colorScheme) private var colorScheme

    /// `shuffled` is an explicit bank order, for screenshots; nil shuffles at random. Give each
    /// `preplaced` taps those tiles in first, for screenshots. Give each exercise instance its own identity (`.id(instanceKey)`) so its state starts fresh.
    public init(
        exercise: ExerciseArtifact,
        courseCode: String,
        reviewed: ReviewedAnswer? = nil,
        shuffled: [Int]? = nil,
        preplaced: [Int] = [],
        onTilePicked: @escaping (String) -> Void = { _ in },
        onAnswerChange: @escaping (String?) -> Void = { _ in }
    ) {
        self.exercise = exercise
        self.courseCode = courseCode
        self.reviewed = reviewed
        self.onTilePicked = onTilePicked
        self.onAnswerChange = onAnswerChange
        var initial = WordBankState(tileCount: (exercise.tiles ?? []).count, shuffled: shuffled)
        for tile in preplaced { initial.tap(tile) }
        _state = State(initialValue: initial)
    }

    public var body: some View {
        let palette = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        let tiles = exercise.tiles ?? []
        let rtl = wordBankIsRtl(courseCode: courseCode, tiles: tiles)
        let review = reviewed.map { WordBankReview.make(exercise: exercise, shuffled: state.shuffled, reviewed: $0) }
        let placed = review?.placed ?? state.chosen
        let bank = review?.bank ?? state.bankOrder
        VStack(spacing: Spacing.standard.s3) {
            TileFlowLayout(rtl: rtl, centered: false) {
                ForEach(Array(placed.enumerated()), id: \.element) { position, index in
                    ExerciseTile(
                        text: tiles[index], exercise: exercise,
                        look: TileLook.of(mark: markAt(review, position), missing: false),
                        placed: true, position: position,
                        enabled: reviewed == nil
                    ) { tap(index) }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
            .padding(Spacing.standard.s2)
            .background(
                RoundedRectangle(cornerRadius: Radii.standard.md, style: .continuous)
                    .strokeBorder(Color(argb: palette.border), lineWidth: 2)
            )
            TileFlowLayout(rtl: rtl, centered: true) {
                ForEach(bank, id: \.self) { index in
                    ExerciseTile(
                        text: tiles[index], exercise: exercise,
                        look: TileLook.of(mark: nil, missing: review?.missing.contains(index) ?? false),
                        enabled: reviewed == nil
                    ) { tap(index) }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
        }
    }

    private func markAt(_ review: WordBankReview?, _ position: Int) -> TileMark? {
        guard let marks = review?.marks, position < marks.count else { return nil }
        return marks[position]
    }

    private func tap(_ index: Int) {
        let tiles = exercise.tiles ?? []
        let picked = state.tap(index)
        onAnswerChange(state.answer(tiles: tiles))
        if picked { onTilePicked(tiles[index]) }
    }
}
