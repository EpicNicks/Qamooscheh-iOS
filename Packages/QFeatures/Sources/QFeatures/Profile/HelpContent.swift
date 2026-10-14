import Foundation

/// One FAQ answer: paragraphs, with an optional bullet list shown after the first `bulletsAfter` of them.
struct FaqEntry: Equatable {
    let id: String
    let question: String
    let paragraphs: [String]
    let bullets: [String]
    let bulletsAfter: Int

    init(id: String, question: String, paragraphs: [String], bullets: [String] = [], bulletsAfter: Int? = nil) {
        self.id = id
        self.question = question
        self.paragraphs = paragraphs
        self.bullets = bullets
        self.bulletsAfter = bulletsAfter ?? paragraphs.count
    }

    /// The answer as an ordered list of blocks, bullets spliced in after `bulletsAfter` paragraphs.
    var blocks: [FaqBlock] {
        var out: [FaqBlock] = []
        for (index, paragraph) in paragraphs.enumerated() {
            if index == bulletsAfter && !bullets.isEmpty { out.append(.bullets(bullets)) }
            out.append(.paragraph(paragraph))
        }
        if bulletsAfter >= paragraphs.count && !bullets.isEmpty { out.append(.bullets(bullets)) }
        return out
    }
}

enum FaqBlock: Equatable {
    case paragraph(String)
    case bullets([String])
}

/// Which FAQ entries are open at the start. `initialEntryId` is the web's /help#id deep link.
func initialOpenIds(_ initialEntryId: String?, in entries: [FaqEntry] = helpFaq) -> Set<String> {
    guard let id = initialEntryId, entries.contains(where: { $0.id == id }) else { return [] }
    return [id]
}

func toggled(_ open: Set<String>, _ id: String) -> Set<String> {
    var next = open
    if next.contains(id) { next.remove(id) } else { next.insert(id) }
    return next
}

/// The web HelpPage FAQ in the Android app's wording; device answers are rewritten for iPhone.
let helpFaq: [FaqEntry] = [
    FaqEntry(
        id: "tts-voice",
        question: "Why does some audio sound different, or not play at all?",
        paragraphs: [
            "The Persian course is recorded: words, prompts and answers play real recordings. Anything that hasn't been recorded yet is read aloud by your iPhone's own text-to-speech voice instead, so that audio sounds different and depends on your iPhone.",
            "If you hear nothing, or the play button is greyed out, your iPhone has no voice for that language:",
            "You can choose what plays on its own in Settings: Autoplay audio (each prompt, under Input), and Read word-bank tiles aloud and Read the answer aloud after I answer (under Keyboard). Every play button still works with these off.",
        ],
        bullets: [
            "Open the iOS Settings app, then go to Accessibility \u{203A} Spoken Content \u{203A} Voices.",
            "Choose the language (Persian or Japanese) and download a voice.",
        ],
        bulletsAfter: 2),
    FaqEntry(
        id: "word-hints",
        question: "Can I see what a word means while I'm answering?",
        paragraphs: [
            "Yes. Tap a word to see its translation or romanization. Settings \u{203A} Lesson hints picks which hints show, and can also show vowel marks and a romanized line above each sentence.",
            "Revealing the Persian for an English word marks that exercise as hinted. A hinted answer doesn't count as remembering the word: it earns no XP, and the word comes back for review sooner.",
            "To look words up before a lesson, open its Start popover on the path and choose Review vocabulary.",
        ]),
    FaqEntry(
        id: "passing-a-lesson",
        question: "Why didn't I pass a lesson?",
        paragraphs: [
            "A lesson needs 75% on your first tries to pass and unlock the next one. A wrong answer comes back later in the lesson, but getting it right the second time doesn't add to the score. An answer accepted with a small typo counts as half.",
            "Your answers still count toward your reviews either way, so take it again to pass.",
        ]),
    FaqEntry(
        id: "saved-words",
        question: "How do saved words and flashcards work?",
        paragraphs: [
            "Save a word or expression with its \u{2605}: on the vocabulary list, or in the Save words row that comes up after you answer an exercise. Saved words are listed under the Review tab's Saved filter. The free plan saves up to 100, counted across all your courses.",
            "Flashcards never change your review schedule, and they earn at most 200 XP a day per course.",
        ],
        bullets: [
            "Flashcards: Type the meaning earns 5 XP for each meaning you get right. Flip cards is practice only and earns nothing on its own.",
            "Practise saved words: your most-due saved words as flip cards, then exercises from lessons that use them. The exercises count just like a lesson's, and each flip card you knew earns 5 XP.",
        ],
        bulletsAfter: 1),
    FaqEntry(
        id: "xp",
        question: "Where does XP come from?",
        paragraphs: [
            "Mostly from lessons: every word an exercise tests earns XP when you get it right on the first try. More for a quick answer, less for a slow one or one with a typo, and none for a wrong or hinted answer. Each word counts once per lesson. Flashcards add more (see above).",
            "The XP that pops up after each answer is only an estimate; what you earn is worked out when the lesson is saved. Practising a lesson you've already passed earns none, since it doesn't count toward your reviews. Your daily goal is in Settings \u{203A} Goals, and leagues rank you by the XP you earn.",
        ]),
    FaqEntry(
        id: "review-intensity",
        question: "What does \"Review intensity\" in Settings actually change?",
        paragraphs: [
            "ParsLing schedules your reviews with FSRS (Free Spaced Repetition Scheduler), an algorithm that predicts how likely you are to still remember a card and times your next review around that prediction. Instead of a fixed \"every 3 days\" schedule, cards you find easy drift further apart and ones you miss come back sooner.",
            "\"Review intensity\" sets FSRS's target: how confident it tries to keep you before it's willing to let a review lapse.",
            "Changing it recalculates every card's next review date the moment you save. It isn't retroactive, but it takes effect immediately, not just for cards you review from then on.",
        ],
        bullets: [
            "Relaxed (85%): fewer reviews, and you'll forget a few more cards along the way.",
            "Balanced (90%): FSRS's own recommended default.",
            "Thorough (94%): more frequent reviews, in exchange for forgetting less.",
        ],
        bulletsAfter: 2),
    FaqEntry(
        id: "skip-vs-test-out",
        question: "What's the difference between the red \u{00D7}, \"Test out\" and \"Skip ahead\"?",
        paragraphs: [
            "The red \u{00D7} leaves the lesson. Nothing you've answered so far is saved, and none of it counts toward your progress.",
            "Test out, in a lesson's Start popover, is a short quiz instead of the full lesson: pass it and you move past that lesson. Skip ahead on the path does the same for a bigger jump, if you already know the material up to that point.",
        ]),
    FaqEntry(
        id: "fonts",
        question: "Persian text is hard to read. Can I change the font?",
        paragraphs: [
            "Yes: Settings \u{203A} Appearance lets you pick the Persian font (Vazirmatn) and set its size. These choices are saved on this iPhone only.",
        ]),
]

/// About ParsLing copy (web AboutPage in the Android app's wording).
enum AboutContent {
    static let tagline = "A guided, spaced-repetition way to actually learn Persian or Japanese."
    static let whatItIs = "ParsLing is a Duolingo-style language course: short lessons arranged along a branching skill path, each one a mix of exercise types: word bank, type-in, match, and speak, building toward full sentences, short stories, and conversations, rather than staying at isolated vocabulary."
    static let howItWorks: [String] = [
        "Spaced repetition. Every answer feeds an FSRS-based scheduler that decides what you review and when, instead of a fixed drill order.",
        "Native-script input. On-screen keyboards for Persian and Japanese, with a phonetic (romanized-typing) option for either, so you're never blocked on a layout you don't have installed.",
        "Instant, honest feedback. Typos and near-misses (a missing ZWNJ, an Arabic-vs-Persian character, a spacing variant) are recognized and corrected in place, rather than just marked wrong, though the server always re-grades every answer, so what you see in the moment is never the final word.",
        "Checkpoints. Already know a unit's material? Test out of it instead of taking every lesson in order.",
    ]
    static let languages = "Persian (\u{0641}\u{0627}\u{0631}\u{0633}\u{06CC}) and Japanese (\u{65E5}\u{672C}\u{8A9E}) today, each with its own keyboard, grading rules, and course."
    static let whereItsAt = "ParsLing is in alpha: lessons, checkpoints, streaks, friends, and leagues are built and working, but new accounts are closed for now, while it's tested with a small group before opening more broadly."

    /// "Version 1.2 (34)" (short version, then CFBundleVersion), "Version 1.2", or nil when the bundle has no version.
    static func versionLine(short: String?, build: String?) -> String? {
        let s = (short ?? "").trimmingCharacters(in: .whitespaces)
        let b = (build ?? "").trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return b.isEmpty ? nil : "Version \(b)" }
        return b.isEmpty ? "Version \(s)" : "Version \(s) (\(b))"
    }

    static func bundleVersionLine(_ bundle: Bundle = .main) -> String? {
        return versionLine(short: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                           build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
    }
}
