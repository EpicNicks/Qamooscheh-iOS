import SwiftUI
import QModel
import QDomain
import QDesign

/// Lists keep a phone-like column on wide screens, like the path (Android VocabColumnWidth).
let vocabColumnWidth: CGFloat = 560

/// The web's starred gold, which has no palette token of its own.
private let starGold = Color(argb: 0xFFFFB800)

/// Whether text reads right to left in this course (native Persian does; romanized never does).
func vocabIsRtl(_ courseCode: String?, _ text: String) -> Bool {
    Languages.writingDirection(courseCode) == .rtl && Languages.isNativeText(courseCode, text)
}

/// Course text of `size`, in the course's script face when it is native text.
func vocabCourseText(_ text: String, courseCode: String?, size: CGFloat, weight: Font.Weight, color: Color) -> some View {
    let rtl = vocabIsRtl(courseCode, text)
    let native = Languages.isNativeText(courseCode, text)
    let script: ScriptKind = Languages.isPersian(courseCode) ? .persian : .japanese
    let font: Font = native ? ScriptFonts().font(script, size: size, weight: weight) : Font.system(size: size, weight: weight)
    return Text(text)
        .font(font)
        .foregroundColor(color)
        .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
        .multilineTextAlignment(rtl ? .trailing : .leading)
}

/// Grey outline star to gold fill (web StarButton). A saved base verb fills in the info colour instead, since its
/// practice brings in every form of the verb.
struct StarButton: View {
    let starred: Bool
    let p: AppPalette
    var baseVerb = false
    var label: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: starred ? "star.fill" : "star")
                .font(.title2)
                .foregroundColor(starred ? (baseVerb ? Color(argb: p.info) : starGold) : Color(argb: p.border))
                .frame(minWidth: 48, minHeight: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? (starred ? "Unstar this word" : "Star this word for review"))
        .accessibilityAddTraits(starred ? .isSelected : [])
    }
}

/// A verb form's infinitive with its own star (verb-base-form-saveable): saving it practises every form of the verb.
struct BaseVerbRow: View {
    let verb: BaseVerbTerm
    let courseCode: String?
    let p: AppPalette
    let onToggleStar: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Verb").font(.caption.weight(.semibold)).foregroundColor(Color(argb: p.textMuted))
                    vocabCourseText(verb.surface, courseCode: courseCode, size: 15, weight: .semibold, color: Color(argb: p.text))
                }
                Text(verb.starred ? "Saved \u{2014} practice uses every form" : verb.gloss)
                    .font(.caption)
                    .foregroundColor(Color(argb: verb.starred ? p.info : p.textMuted))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            StarButton(
                starred: verb.starred, p: p, baseVerb: true,
                label: verb.starred ? "Unsave the verb \(verb.surface)" : "Save the verb \(verb.surface) to practise all its forms",
                action: onToggleStar)
        }
        .padding(.leading, 10)
        .background(RoundedRectangle(cornerRadius: Radii.standard.md).fill(Color(argb: verb.starred ? p.infoBg : p.bg)))
    }
}

/// How well the word is known: four bars filled by FSRS stability, and a "Due" pill once its
/// review date has passed. A word never graded on this device says "New" instead.
struct StrengthMeter: View {
    let strength: VocabStrength
    let p: AppPalette

    var body: some View {
        switch strength {
        case .new:
            Text("New").font(.caption.weight(.semibold)).foregroundColor(Color(argb: p.textMuted))
        case .practiced(let level, let due):
            HStack(spacing: 6) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<VocabStrength.maxLevel, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(argb: i < level ? p.primary : p.border))
                            .frame(width: 5, height: CGFloat(6 + i * 3))
                    }
                }
                if due {
                    Text("Due").font(.caption2.weight(.bold)).foregroundColor(Color(argb: p.warning))
                        .padding(.horizontal, 8).padding(.vertical, 1)
                        .background(Capsule().fill(Color(argb: p.warningBg)))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Strength \(level) of \(VocabStrength.maxLevel)" + (due ? ", due for review" : ""))
        }
    }
}

/// One rounded box in a vocabulary list (web VocabTermCard): the word, its gloss and romanization,
/// its strength and a star toggle; a verb form also offers its base verb to save (`onToggleBaseStar`), and a saved
/// base verb is outlined in the info colour (verb-base-form-highlight). Playing the word is a follow-up.
struct VocabTermCard: View {
    let term: VocabTerm
    let courseCode: String?
    let p: AppPalette
    let onToggleStar: () -> Void
    var onToggleBaseStar: (String) -> Void = { _ in }
    @ScaledMetric(relativeTo: .body) private var surfaceSize: CGFloat = 18

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radii.standard.lg)
        let savedVerb = term.isBaseVerb && term.starred
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    vocabCourseText(term.surface, courseCode: courseCode, size: surfaceSize, weight: .bold, color: Color(argb: p.text))
                    Text(term.gloss).font(.subheadline).foregroundColor(Color(argb: p.text))
                    if let roman = term.romanization {
                        Text(roman).font(.footnote.italic()).foregroundColor(Color(argb: p.textMuted))
                    }
                    if savedVerb {
                        Text("Saved verb \u{2014} practice uses every form")
                            .font(.caption.weight(.semibold)).foregroundColor(Color(argb: p.info))
                    }
                    StrengthMeter(strength: term.strength, p: p).padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StarButton(starred: term.starred, p: p, baseVerb: term.isBaseVerb, action: onToggleStar)
            }
            if let verb = term.baseVerb {
                BaseVerbRow(verb: verb, courseCode: courseCode, p: p) { onToggleBaseStar(verb.tag) }
            }
        }
        .padding(.leading, 24).padding(.trailing, 8).padding(.vertical, 16)
        .background(Color(argb: savedVerb ? p.infoBg : p.surface))
        .clipShape(shape)
        .overlay(shape.stroke(Color(argb: savedVerb ? p.info : p.border), lineWidth: 2))
    }
}

/// The not-ready states every vocabulary screen shares; draws nothing once ready.
struct VocabStatusView: View {
    let status: VocabStatus
    let p: AppPalette
    let onRetry: () -> Void

    var body: some View {
        switch status {
        case .loading, .noCourse:
            ProgressView("Loading vocabulary\u{2026}").frame(maxWidth: .infinity)
        case .notDownloaded:
            VStack(alignment: .leading, spacing: 16) {
                Text("Your course is still downloading. Its words will be here once it's on this device.")
                    .font(.subheadline).foregroundColor(Color(argb: p.textMuted))
                Button("Try again", action: onRetry).buttonStyle(.bordered)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 16) {
                Text(message).font(.callout).foregroundColor(Color(argb: p.danger))
                Button("Try again", action: onRetry).buttonStyle(.bordered)
            }
        case .ready:
            EmptyView()
        }
    }
}

/// The words one lesson introduces, widenable to its unit or the whole course.
public struct SkillVocabularyScreen: View {
    @ObservedObject private var model: SkillVocabularyModel

    public init(model: SkillVocabularyModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            SkillVocabularyContent(model: model).padding(16).frame(maxWidth: .infinity)
        }
        .navigationTitle("Vocabulary")
        .task { await model.refresh() }
    }
}

struct SkillVocabularyContent: View {
    @ObservedObject var model: SkillVocabularyModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        let status = model.store.status
        LazyVStack(alignment: .leading, spacing: 12) {
            Text("Vocabulary").font(.title2.weight(.bold)).foregroundColor(Color(argb: p.text))
                .accessibilityAddTraits(.isHeader)
            if status == .ready {
                Picker("Scope", selection: Binding(get: { model.scope }, set: { model.setScope($0) })) {
                    ForEach(model.scopes, id: \.scope) { option in
                        Text(scopeLabel(option.label)).tag(option.scope)
                    }
                }
                .pickerStyle(.segmented)
                TextField("Search words", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .searchLikeInput()
                if let message = model.store.starMessage {
                    Text(message).font(.callout).foregroundColor(Color(argb: p.danger))
                }
                let terms = model.terms
                if terms.isEmpty {
                    Text(model.emptyText).font(.subheadline).foregroundColor(Color(argb: p.textMuted))
                }
                ForEach(terms, id: \.tag) { term in
                    VocabTermCard(
                        term: term, courseCode: model.store.content?.courseCode, p: p,
                        onToggleStar: { Task { await model.store.toggleStar(term.tag) } },
                        onToggleBaseStar: { tag in Task { await model.store.toggleStar(tag) } })
                }
            } else {
                VocabStatusView(status: status, p: p) { Task { await model.refresh() } }
            }
        }
        .frame(maxWidth: vocabColumnWidth, alignment: .leading)
    }
}

extension View {
    /// Search and answer boxes: no autocorrect, no capitalization (the capitalization modifier is iOS only).
    @ViewBuilder
    func searchLikeInput() -> some View {
        #if os(iOS)
        self.autocorrectionDisabled().textInputAutocapitalization(.never)
        #else
        self.autocorrectionDisabled()
        #endif
    }
}
