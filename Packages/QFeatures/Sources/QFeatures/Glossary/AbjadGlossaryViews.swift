import SwiftUI
import QDomain
import QDesign

private func persianFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
    ScriptFonts().font(.persian, size: size, weight: weight)
}

private func formLabel(_ form: LetterForm) -> String {
    switch form {
    case .isolated: return "Alone"
    case .initial: return "Start"
    case .medial: return "Middle"
    case .final: return "End"
    }
}

/// The interactive abjad leaf (web AbjadGlossary, Android AbjadGlossaryScreen): every letter as a
/// two-sided tile clustered by sound, or a flashcard deck, driven by one form toggle and one letter search.
struct AbjadGlossaryView: View {
    @StateObject private var model = AbjadGlossaryModel()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        VStack(alignment: .leading, spacing: 12) {
            Picker("View", selection: Binding(get: { model.view }, set: { model.setView($0) })) {
                Text("Letters").tag(AbjadView.letters)
                Text("Flashcards").tag(AbjadView.flashcards)
            }
            .pickerStyle(.segmented)
            Picker("Letter form", selection: Binding(get: { model.form }, set: { model.setForm($0) })) {
                ForEach(LetterForm.allCases, id: \.self) { Text(formLabel($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            AbjadLetterSearch(model: model, p: p)
            if let status = model.status {
                Text(status).font(.footnote).foregroundColor(Color(argb: p.textMuted))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            switch model.view {
            case .letters:
                ForEach(model.groups, id: \.sound) { group in
                    AbjadSoundGroupView(group: group, form: model.form, courseCode: "fa", p: p)
                }
            case .flashcards:
                AbjadFlashcardDeck(model: model, p: p)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AbjadLetterSearch: View {
    @ObservedObject var model: AbjadGlossaryModel
    let p: AppPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.tokens.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.tokens, id: \.key) { token in
                            chip(token)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("Search: type \u{062B}, s, sh\u{2026}", text: Binding(
                    get: { model.pending },
                    set: { model.onSearchInput($0) }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .padding(10)
                .background(Color(argb: p.bg))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(argb: p.border), lineWidth: 2))
                .accessibilityLabel("Search letters by Persian letter or Latin sound")
                Button("Clear") { model.clearSearch() }
                    .buttonStyle(.bordered)
                    .disabled(model.tokens.isEmpty && model.pending.isEmpty)
            }
        }
    }

    private func chip(_ token: LetterSearchToken) -> some View {
        let matches = token.letters.joined(separator: " ")
        let removeLabel = "Remove \(token.label)" + (token.kind == .latin ? " (\(matches))" : "")
        return HStack(spacing: 4) {
            if token.kind == .persian {
                Text(token.label).font(persianFont(18, weight: .bold)).foregroundColor(Color(argb: p.text))
            } else {
                Text(token.label).font(.body.weight(.bold)).foregroundColor(Color(argb: p.text))
                Text(matches).font(persianFont(16)).foregroundColor(Color(argb: p.textMuted))
                    .environment(\.layoutDirection, .rightToLeft)
            }
            Button(action: { model.removeToken(token.key) }) {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundColor(Color(argb: p.textMuted))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(removeLabel)
        }
        .padding(.leading, 10).padding(.trailing, 2).padding(.vertical, 2)
        .background(Color(argb: p.surface))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color(argb: p.current), lineWidth: 1))
    }
}

private struct AbjadSoundGroupView: View {
    let group: ShownSoundGroup
    let form: LetterForm
    let courseCode: String
    let p: AppPalette

    var body: some View {
        let sound = soundOf(group.sound)
        let shared = group.letters.count > 1
        let shape = RoundedRectangle(cornerRadius: 20)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(sound.label).font(.body.weight(.heavy)).foregroundColor(Color(argb: p.text))
                if shared {
                    let count = group.shown.count < group.letters.count
                        ? "\(group.shown.count) of \(group.letters.count)" : "\(group.letters.count)"
                    Text("\(count) letters").font(.caption2.weight(.bold)).foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 1)
                        .background(Color(argb: p.current)).clipShape(Capsule())
                }
            }
            Text(sound.hint).font(.caption).foregroundColor(Color(argb: p.textMuted))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 144), spacing: 8, alignment: .top)], alignment: .leading, spacing: 8) {
                ForEach(group.shown, id: \.letter) { letter in
                    AbjadLetterTile(letter: letter, form: form, p: p)
                }
            }
        }
        .padding(shared ? 8 : 0)
        .background(shared ? Color(argb: p.current).opacity(0.08) : Color.clear)
        .clipShape(shape)
        .overlay(shape.stroke(Color(argb: p.current), lineWidth: shared ? 2 : 0))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sound: \(sound.label)")
    }
}

/// One letter as a two-sided tile: the letter in the chosen form and its name on the front, an
/// example word and the letter's note on the back. The footer strip flips it.
private struct AbjadLetterTile: View {
    let letter: AbjadLetter
    let form: LetterForm
    let p: AppPalette
    @State private var flipped = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radii.standard.lg)
        VStack(spacing: 0) {
            if flipped { back } else { front }
            Rectangle().fill(Color(argb: p.border)).frame(height: 2)
            Button(action: { flipped.toggle() }) {
                Text(flipped ? "Back" : "Learn more").font(.footnote.weight(.bold)).foregroundColor(Color(argb: p.current))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(flipped ? "Back to \(letter.nameRomanized)" : "Learn more about \(letter.nameRomanized)")
        }
        .frame(maxWidth: .infinity, minHeight: 224)
        .background(Color(argb: flipped ? p.surface : p.bg))
        .clipShape(shape)
        .overlay(shape.stroke(Color(argb: p.border), lineWidth: 2))
    }

    private var front: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            Text(letterInForm(letter, form)).font(persianFont(52)).foregroundColor(Color(argb: p.text))
                .environment(\.layoutDirection, .rightToLeft)
                .accessibilityLabel(letter.nameRomanized)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Text(letter.nameRomanized).font(.body.weight(.bold)).foregroundColor(Color(argb: p.text))
                Text(letter.nameNative).font(persianFont(16)).foregroundColor(Color(argb: p.textMuted))
                    .environment(\.layoutDirection, .rightToLeft)
            }
            .padding(.horizontal, 8).padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, minHeight: 176)
    }

    private var back: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(letter.example.word).font(persianFont(22, weight: .bold)).foregroundColor(Color(argb: p.text))
                    .environment(\.layoutDirection, .rightToLeft)
                (Text(letter.example.romanization).italic() + Text(" \u{00B7} \(letter.example.meaning)"))
                    .font(.caption).foregroundColor(Color(argb: p.textMuted)).multilineTextAlignment(.center)
                if !letter.joinsNext {
                    Text("Doesn't connect forward").font(.caption2.weight(.semibold)).foregroundColor(Color(argb: p.textMuted))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color(argb: p.border)).clipShape(Capsule())
                }
                if let note = letter.note {
                    AbjadNoteText(text: note, p: p)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 176)
    }
}

/// A letter's note is English prose quoting Persian: each Persian run gets the Persian face and a bidi isolate.
private struct AbjadNoteText: View {
    let text: String
    let p: AppPalette

    var body: some View {
        Text(attributed).font(.caption).foregroundColor(Color(argb: p.text))
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for segment in splitPersianRuns(text) {
            if segment.isPersian {
                var run = AttributedString("\u{2068}\(segment.text)\u{2069}")
                run.font = persianFont(12)
                result.append(run)
            } else {
                result.append(AttributedString(segment.text))
            }
        }
        return result
    }
}

private struct AbjadFlashcardDeck: View {
    @ObservedObject var model: AbjadGlossaryModel
    let p: AppPalette

    var body: some View {
        VStack(spacing: 12) {
            if let card = model.card {
                let sound = soundOf(card.sound)
                let shape = RoundedRectangle(cornerRadius: Radii.standard.lg)
                Button(action: { model.flipCard() }) {
                    VStack(spacing: 8) {
                        if model.deckState.flipped {
                            Text("SOUND").font(.caption2.weight(.bold)).foregroundColor(Color(argb: p.textMuted))
                            Text(sound.label).font(.system(size: 32, weight: .heavy)).foregroundColor(Color(argb: p.text))
                            Text(sound.hint).font(.footnote).foregroundColor(Color(argb: p.textMuted))
                            HStack(spacing: 12) {
                                Text(card.nameRomanized).font(.headline).foregroundColor(Color(argb: p.text))
                                Text(card.nameNative).font(persianFont(18)).foregroundColor(Color(argb: p.text))
                                    .environment(\.layoutDirection, .rightToLeft)
                            }
                        } else {
                            Text(letterInForm(card, model.form)).font(persianFont(80)).foregroundColor(Color(argb: p.text))
                                .environment(\.layoutDirection, .rightToLeft)
                            Text("What sound, what name?").font(.footnote.weight(.semibold)).foregroundColor(Color(argb: p.current))
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 320, minHeight: 256)
                    .frame(maxWidth: .infinity)
                    .background(Color(argb: model.deckState.flipped ? p.surface : p.bg))
                    .clipShape(shape)
                    .overlay(shape.stroke(Color(argb: p.border), lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.deckState.flipped
                    ? "\(sound.label), \(sound.hint). \(card.nameRomanized)"
                    : "Letter \(card.nameRomanized)")
                .accessibilityHint("Flip card")
            }
            HStack(spacing: 16) {
                Button(action: { model.moveCard(-1) }) { Image(systemName: "chevron.backward") }
                    .buttonStyle(.bordered).accessibilityLabel("Previous card")
                Text("\(model.deck.isEmpty ? 0 : model.deckState.position + 1) / \(model.deck.count)")
                    .font(.body.weight(.semibold)).foregroundColor(Color(argb: p.textMuted))
                Button(action: { model.moveCard(1) }) { Image(systemName: "chevron.forward") }
                    .buttonStyle(.bordered).accessibilityLabel("Next card")
            }
            Button(model.deckState.order != nil ? "Back to alphabet order" : "Shuffle") { model.toggleShuffle() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
    }
}
