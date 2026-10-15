import SwiftUI
import QDesign
import QDomain
import QModel

// A story chapter so far (web StoryTranscript, matching Android StoryTranscript.kt): its title, then each line
// before the current one with its correct answer. The mark sits in a fixed gutter outside the right-to-left
// text, so it is easy to scan down.
struct StoryTranscriptView: View {
    let chapter: StoryChapter
    let upTo: Int
    let results: [Int: Bool]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        VStack(alignment: .leading, spacing: Spacing.standard.s2) {
            Text(chapter.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Color(argb: p.text))
                .accessibilityAddTraits(.isHeader)
            ForEach(StoryTranscript.lines(chapter, upTo: upTo, results: results), id: \.ordinal) { line in
                HStack(alignment: .top, spacing: 0) {
                    Text(StoryTranscript.glyph(line.mark))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Color(argb: line.mark == .incorrect ? p.danger : p.success))
                        .frame(width: 24, alignment: .leading)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        AnnotatedText(line.exercise.prompt, scriptMode: line.exercise.scriptMode, tags: line.exercise.tags, fontSize: 18)
                        AnnotatedText(line.answer, scriptMode: line.exercise.scriptMode, tags: line.exercise.tags, fontSize: 15)
                            .opacity(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Spacing.standard.s2)
                .background(RoundedRectangle(cornerRadius: Radii.standard.md, style: .continuous).fill(Color(argb: p.surface)))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(StoryTranscript.accessibilityLabel(line))
            }
        }
    }
}
