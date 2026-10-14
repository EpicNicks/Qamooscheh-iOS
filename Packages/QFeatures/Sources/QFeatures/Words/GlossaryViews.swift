import SwiftUI
import QDomain
import QDesign

/// The course glossary (web GlossaryPage/GlossaryEntryPage, Android GlossaryScreen): an accordion
/// tree whose leaves open a term table. The abjad leaf's interactive view is a follow-up; it shows
/// its note only. On a leaf the back button steps to the tree before the glossary is left.
public struct GlossaryScreen: View {
    @ObservedObject private var model: GlossaryModel

    public init(model: GlossaryModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            GlossaryContent(model: model).padding(16)
        }
        .navigationTitle("Glossary")
        .navigationBarBackButtonHidden(model.isOnLeaf)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if model.isOnLeaf {
                    Button(action: { model.up() }) { Label("Glossary", systemImage: "chevron.backward") }
                }
            }
        }
    }
}

struct GlossaryContent: View {
    @ObservedObject var model: GlossaryModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        VStack(alignment: .leading, spacing: 12) {
            switch model.page {
            case .notFound:
                Text("This glossary entry doesn't exist.").font(.callout).foregroundColor(Color(argb: p.danger))
            case .tree(let entries):
                if entries.isEmpty {
                    Text("Nothing here yet.").font(.callout).foregroundColor(Color(argb: p.textMuted))
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(entries, id: \.id) { entry in
                            GlossaryNodeView(model: model, entry: entry, parentPath: [], p: p)
                        }
                    }
                }
            case .leaf(_, let entry):
                Text(entry.title).font(.title2.weight(.bold)).foregroundColor(Color(argb: p.text))
                    .accessibilityAddTraits(.isHeader)
                if let note = entry.note {
                    Text(note).font(.body).foregroundColor(Color(argb: p.textMuted))
                }
                if entry.view == nil {
                    TermTable(terms: entry.terms, model: model, p: p)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GlossaryNodeView: View {
    @ObservedObject var model: GlossaryModel
    let entry: GlossaryEntry
    let parentPath: [String]
    let p: AppPalette

    var body: some View {
        let path = parentPath + [entry.id]
        let shape = RoundedRectangle(cornerRadius: Radii.standard.md)
        if !entry.isFolder {
            Button(action: { model.open(path) }) {
                Text(entry.title).font(.body.weight(.semibold)).foregroundColor(Color(argb: p.text))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(Color(argb: p.surface))
                    .clipShape(shape)
                    .overlay(shape.stroke(Color(argb: p.border), lineWidth: 1))
            }
            .buttonStyle(.plain)
        } else {
            let open = model.isOpen(path)
            VStack(alignment: .leading, spacing: 0) {
                Button(action: { model.toggle(path) }) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right").font(.body.weight(.bold))
                            .rotationEffect(.degrees(open ? 90 : 0))
                        Text(entry.title).font(.body.weight(.bold)).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(Color(argb: p.text))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(Color(argb: p.surface))
                }
                .buttonStyle(.plain)
                .accessibilityValue(open ? "Expanded" : "Collapsed")
                if open {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(entry.children, id: \.id) { child in
                            GlossaryNodeView(model: model, entry: child, parentPath: path, p: p)
                        }
                    }
                    .padding(.leading, 28).padding(.trailing, 12).padding(.vertical, 8)
                }
            }
            .clipShape(shape)
            .overlay(shape.stroke(Color(argb: p.border), lineWidth: 1))
        }
    }
}

/// A leaf's terms (web table). At normal sizes the three columns share the width; at
/// accessibility Dynamic Type sizes each term stacks its fields instead.
private struct TermTable: View {
    let terms: [GlossaryTerm]
    @ObservedObject var model: GlossaryModel
    let p: AppPalette
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var termSize: CGFloat = 18
    @State private var tableWidth: CGFloat = 0
    private let columnSpacing: CGFloat = 12
    @State private var tableWidth: CGFloat = 0
    private let columnSpacing: CGFloat = 12

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: 0) {
            if !stacked {
                HStack(alignment: .firstTextBaseline, spacing: columnSpacing) {
                    header("Term", width: columns[0])
                    header("Romanization", width: columns[1])
                    header("Meaning", width: columns[2])
                }
                .padding(.vertical, 8)
                Rectangle().fill(Color(argb: p.border)).frame(height: 2)
            }
            ForEach(Array(terms.enumerated()), id: \.offset) { _, term in
                row(term, stacked: stacked)
                Rectangle().fill(Color(argb: p.border)).frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { tableWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { newWidth in tableWidth = newWidth }
        })
    }

    private var columns: [CGFloat] {
        GlossaryColumns.widths(available: Double(tableWidth), spacing: Double(columnSpacing)).map { CGFloat($0) }
    }

    private func header(_ text: String, width: CGFloat) -> some View {
        Text(text).font(.footnote.weight(.semibold)).foregroundColor(Color(argb: p.textMuted))
            .frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private func row(_ term: GlossaryTerm, stacked: Bool) -> some View {
        let roman = Text(term.romanization ?? "").font(.body.italic()).foregroundColor(Color(argb: p.textMuted))
        let meaning = Text(term.definition).font(.body).foregroundColor(Color(argb: p.textMuted))
        if stacked {
            VStack(alignment: .leading, spacing: 2) {
                termText(term.term)
                if term.romanization != nil { roman }
                meaning
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: columnSpacing) {
                termText(term.term).frame(width: columns[0], alignment: .leading)
                roman.frame(width: columns[1], alignment: .leading)
                meaning.frame(width: columns[2], alignment: .leading)
            }
            .padding(.vertical, 8)
        }
    }

    private func termText(_ text: String) -> some View {
        let rtl = model.isRtl(text)
        let native = Languages.isNativeText(model.courseCode, text)
        let script: ScriptKind = Languages.isPersian(model.courseCode) ? .persian : .japanese
        let font: Font = native
            ? ScriptFonts().font(script, size: termSize, weight: .bold)
            : Font.system(size: termSize, weight: .bold)
        return Text(text)
            .font(font)
            .foregroundColor(Color(argb: p.text))
            .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
            .multilineTextAlignment(rtl ? .trailing : .leading)
    }
}

/// Fixed-content glossary screens for snapshot tests. `large` renders at an accessibility Dynamic Type size.
public struct GlossaryShowcase: View {
    private let large: Bool
    @StateObject private var tree: GlossaryModel
    @StateObject private var leaf: GlossaryModel
    @Environment(\.colorScheme) private var colorScheme

    public init(large: Bool = false) {
        self.large = large
        let greet = GlossaryEntry(id: "greet", title: "Greetings", terms: [
            GlossaryTerm(term: "\u{0633}\u{0644}\u{0627}\u{0645}", romanization: "salam", definition: "hello"),
            GlossaryTerm(term: "\u{062E}\u{062F}\u{0627}\u{062D}\u{0627}\u{0641}\u{0638}", romanization: "khodahafez", definition: "goodbye"),
        ], note: "Everyday greetings.")
        let basics = GlossaryEntry(id: "basics", title: "Basics", children: [greet, GlossaryEntry(id: "num", title: "Numbers")])
        let g = Glossary(courses: ["fa": [basics, GlossaryEntry(id: "abjad", title: "Abjad", view: .abjad)]])
        _tree = StateObject(wrappedValue: GlossaryModel(courseCode: "fa", glossary: g))
        _leaf = StateObject(wrappedValue: GlossaryModel(courseCode: "fa", glossary: g, path: ["basics", "greet"]))
    }

    public var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        VStack(alignment: .leading, spacing: 24) {
            GlossaryContent(model: tree)
            Divider()
            GlossaryContent(model: leaf)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(argb: p.bg))
        .environment(\.dynamicTypeSize, large ? .accessibility2 : .large)
    }
}
