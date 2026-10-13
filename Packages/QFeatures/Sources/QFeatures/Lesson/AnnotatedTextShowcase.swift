import SwiftUI
import QDesign
import QDomain
import QModel

public enum AnnotatedTextScenario: Sendable {
    case furiganaWrapping
    case mixedJapaneseLatin
    case persianEzafe
    case persianVowelMarksOff
    case persianVowelMarksOn
}

/// Gallery for snapshot tests: hand-made hints so no course content is needed.
public struct AnnotatedTextShowcase: View {
    private let scenario: AnnotatedTextScenario
    @Environment(\.colorScheme) private var colorScheme

    public init(_ scenario: AnnotatedTextScenario) {
        self.scenario = scenario
    }

    private static let japanese: [String: WordHint] = [
        "私": WordHint(translation: "I", romanization: "watashi", ruby: "わたし"),
        "学校": WordHint(translation: "school", romanization: "gakkou", ruby: "がっこう"),
        "行き": WordHint(translation: "go", romanization: "iki", ruby: "いき"),
        "今日": WordHint(translation: "today", romanization: "kyou", ruby: "きょう"),
        "元気": WordHint(translation: "well", romanization: "genki", ruby: "げんき"),
    ]

    private static let persian: [String: WordHint] = [
        "کتاب": WordHint(translation: "book", romanization: "ketāb", ruby: "ketāb"),
        "من": WordHint(translation: "my, me", romanization: "man", ruby: "man"),
        "سلام": WordHint(translation: "hello", romanization: "salām", ruby: "salām"),
        "خوب": WordHint(translation: "good", romanization: "khub", ruby: "khub"),
    ]

    private func look(display: ScriptDisplay, hints: [String: WordHint], vowelMarks: Bool = true) -> LessonTextLook {
        return LessonTextLook(
            settings: TextDisplaySettings(
                display: display,
                translationEnabled: true,
                romanizationEnabled: true,
                nativeEnabled: true,
                vowelMarks: vowelMarks,
                sentenceRomanization: true
            ),
            courseHints: hints
        )
    }

    private var content: (text: String, look: LessonTextLook) {
        switch scenario {
        case .furiganaWrapping:
            return ("私は学校に行きます。今日は元気です。私は学校に行きます。今日は元気です。", look(display: .both, hints: AnnotatedTextShowcase.japanese))
        case .mixedJapaneseLatin:
            return ("Hello 私は Tokyo の学校に行きます OK", look(display: .both, hints: AnnotatedTextShowcase.japanese))
        case .persianEzafe:
            return ("سلام، کتابِ من خوب است", look(display: .native, hints: AnnotatedTextShowcase.persian))
        case .persianVowelMarksOff:
            return ("سَلام، کِتابِ من خوب است", look(display: .native, hints: AnnotatedTextShowcase.persian, vowelMarks: false))
        case .persianVowelMarksOn:
            return ("سَلام، کِتابِ من خوب است", look(display: .native, hints: AnnotatedTextShowcase.persian, vowelMarks: true))
        }
    }

    public var body: some View {
        let palette = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        let c = content
        VStack(alignment: .leading, spacing: 12) {
            SentenceRomanization(c.text, scriptMode: .native)
            AnnotatedText(c.text, scriptMode: .native, fontSize: 24, onTip: { _ in })
        }
        .environment(\.lessonTextLook, c.look)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(argb: palette.bg))
    }
}
