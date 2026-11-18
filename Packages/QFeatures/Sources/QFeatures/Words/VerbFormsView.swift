import SwiftUI
import QModel
import QDomain
import QDesign

/// One verb's forms (vocab-search-verbs, web VerbFormsTable): the infinitive and its gloss, the principal parts, a
/// tense picker, a negative switch and the person table. Written and Spoken columns always show together, as on the
/// web (Android picks one by the register pref). Tense and negative are view state, so they survive a re-render.
struct VerbFormsView: View {
    let entry: VerbIndexEntry
    let courseCode: String?
    let vowelMarks: Bool
    @State private var tense: String?
    @State private var negative = false
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .title) private var infinitiveSize: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var partSize: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var cellSize: CGFloat = 17

    init(entry: VerbIndexEntry, courseCode: String?, vowelMarks: Bool, tense: String? = nil, negative: Bool = false) {
        self.entry = entry
        self.courseCode = courseCode
        self.vowelMarks = vowelMarks
        _tense = State(initialValue: tense)
        _negative = State(initialValue: negative)
    }

    var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        let table = VerbFormsTable(entry: entry, requestedTense: tense, negative: negative, vowelMarks: vowelMarks)
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                vocabCourseText(table.infinitive, courseCode: courseCode, size: infinitiveSize, weight: .bold, color: Color(argb: p.text))
                    .accessibilityAddTraits(.isHeader)
                if let gloss = table.gloss {
                    Text(gloss).font(.headline).foregroundColor(Color(argb: p.text))
                }
            }
            if !table.principalParts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Principal parts").font(.caption.weight(.semibold)).foregroundColor(Color(argb: p.textMuted))
                    vocabCourseText(
                        table.principalParts.joined(separator: " \u{00B7} "), courseCode: courseCode,
                        size: partSize, weight: .semibold, color: Color(argb: p.text))
                }
            }
            if let selected = table.tense {
                Picker("Tense", selection: Binding(get: { selected }, set: { tense = $0 })) {
                    ForEach(table.tenses, id: \.tense) { option in
                        Text(option.label).tag(option.tense)
                    }
                }
                .pickerStyle(.menu)
                Toggle("Negative", isOn: $negative)
                formsTable(table, p)
            } else {
                Text("No forms for this verb yet.").font(.subheadline).foregroundColor(Color(argb: p.textMuted))
            }
        }
        .frame(maxWidth: vocabColumnWidth, alignment: .leading)
    }

    private func formsTable(_ table: VerbFormsTable, _ p: AppPalette) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                header("Person", p)
                header("Written", p)
                if table.showsSpoken { header("Spoken", p) }
            }
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(table.rows, id: \.person) { row in
                GridRow(alignment: .top) {
                    Text(row.label).font(.subheadline).foregroundColor(Color(argb: p.textMuted))
                    formCell(row.written, row.writtenRomanization, p)
                    if table.showsSpoken {
                        if let spoken = row.spoken {
                            formCell(spoken, row.spokenRomanization, p)
                        } else {
                            Text("\u{2014}").foregroundColor(Color(argb: p.textMuted)).accessibilityLabel("None")
                        }
                    }
                }
            }
        }
    }

    private func header(_ text: String, _ p: AppPalette) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundColor(Color(argb: p.textMuted))
    }

    private func formCell(_ form: String, _ romanization: String?, _ p: AppPalette) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            vocabCourseText(form, courseCode: courseCode, size: cellSize, weight: .regular, color: Color(argb: p.text))
            if let roman = romanization, !roman.isEmpty {
                Text(roman).font(.caption.italic()).foregroundColor(Color(argb: p.textMuted))
            }
        }
    }
}

/// The forms view in its own sheet, with a Done button.
struct VerbFormsSheet: View {
    let entry: VerbIndexEntry
    let courseCode: String?
    let vowelMarks: Bool
    let onDone: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        NavigationStack {
            ScrollView {
                VerbFormsView(entry: entry, courseCode: courseCode, vowelMarks: vowelMarks)
                    .padding(16)
                    .frame(maxWidth: .infinity)
            }
            .background(Color(argb: p.bg))
            .navigationTitle("Verb forms")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }
}

/// Fixed verbs.json entry for previews and snapshots: kharidan ("to buy"), present and simple past, with spoken forms.
enum VerbFormsSample {
    static let infinitive = "\u{062E}\u{0631}\u{06CC}\u{062F}\u{0646}"

    static var entry: VerbIndexEntry {
        let persons = ["1s", "2s", "3s", "1p", "2p", "3p"]
        let written = ["\u{0645}", "\u{06CC}", "\u{062F}", "\u{06CC}\u{0645}", "\u{06CC}\u{062F}", "\u{0646}\u{062F}"]
        let spoken = ["\u{0645}", "\u{06CC}", "\u{0647}", "\u{06CC}\u{0645}", "\u{06CC}\u{0646}", "\u{0646}"]
        let writtenRoman = ["am", "i", "ad", "im", "id", "and"]
        let spokenRoman = ["am", "i", "e", "im", "in", "an"]
        let present = "\u{0645}\u{06CC}\u{200C}\u{062E}\u{064E}\u{0631}"
        let past = "\u{062E}\u{064E}\u{0631}\u{06CC}\u{062F}"
        let pastWritten = ["\u{0645}", "\u{06CC}", "", "\u{06CC}\u{0645}", "\u{06CC}\u{062F}", "\u{0646}\u{062F}"]
        let pastRoman = ["am", "i", "", "im", "id", "and"]
        var presentCells: [String: VerbFormCell] = [:]
        var pastCells: [String: VerbFormCell] = [:]
        for i in 0..<persons.count {
            presentCells[persons[i]] = VerbFormCell(
                written: present + written[i], spoken: present + spoken[i],
                negative: "\u{0646}" + present + written[i], negativeSpoken: "\u{0646}" + present + spoken[i],
                writtenRomanization: "mikhar" + writtenRoman[i], spokenRomanization: "mikhar" + spokenRoman[i],
                negativeRomanization: "nemikhar" + writtenRoman[i], negativeSpokenRomanization: "nemikhar" + spokenRoman[i])
            pastCells[persons[i]] = VerbFormCell(
                written: past + pastWritten[i], negative: "\u{0646}" + past + pastWritten[i],
                writtenRomanization: "kharid" + pastRoman[i], negativeRomanization: "nakharid" + pastRoman[i])
        }
        return VerbIndexEntry(
            infinitive: infinitive, presentStem: "\u{062E}\u{0631}", pastStem: "\u{062E}\u{0631}\u{06CC}\u{062F}",
            principalParts: [infinitive, "\u{062E}\u{0631}\u{06CC}\u{062F}", "\u{0645}\u{06CC}\u{200C}\u{062E}\u{0631}\u{062F}"],
            table: ["present": presentCells, "simplePast": pastCells], gloss: "to buy")
    }
}
