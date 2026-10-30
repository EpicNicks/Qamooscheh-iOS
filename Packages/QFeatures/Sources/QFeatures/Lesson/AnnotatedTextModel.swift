import Foundation
import CoreGraphics
import QModel
import QDomain

// What AnnotatedText renders, decided without any UI so swift test proves it.
// Port of web AnnotatedText.tsx, matching Android AnnotatedText.kt where they differ.

/// How a lesson's course-language text looks (web TextDisplaySettings plus the
/// device's alignment and text-size prefs), provided once per lesson screen.
/// `courseHints` is the whole course's map; each exercise gates it.
public struct LessonTextLook: Equatable, Sendable {
    public var settings: TextDisplaySettings
    public var courseHints: [String: WordHint]
    /// Native-script lines centered instead of starting at the reading edge.
    public var centerNative: Bool
    /// The native script's text-size pref, 1 = 100%.
    public var nativeScale: CGFloat

    public init(settings: TextDisplaySettings, courseHints: [String: WordHint] = emptyHintMap, centerNative: Bool = false, nativeScale: CGFloat = 1) {
        self.settings = settings
        self.courseHints = courseHints
        self.centerNative = centerNative
        self.nativeScale = nativeScale
    }

    /// Everything on, native display: what previews and snapshots see.
    public static let standard = LessonTextLook(
        settings: TextDisplaySettings(
            display: .native,
            translationEnabled: true,
            romanizationEnabled: true,
            nativeEnabled: true,
            vowelMarks: true,
            sentenceRomanization: true
        )
    )
}

/// A tapped word, the lines its tip shows, and where the word sits on screen (global coordinates; zero when unknown).
public struct WordTip: Equatable {
    public var word: String
    public var lines: [String]
    public var anchor: CGRect

    public init(word: String, lines: [String], anchor: CGRect = .zero) {
        self.word = word
        self.lines = lines
        self.anchor = anchor
    }
}

/// The tip's lines from independent parts (web assembleTooltipLines): the
/// translation when that toggle is on, the romanization when its toggle is on
/// and it isn't already on screen (only in native display), bracketed unless
/// it's the only line, and the ezafe when the translation isn't there to carry it.
public func tipLines(_ hint: WordHint, settings: TextDisplaySettings) -> [String] {
    let ezafe = hint.ezafe?.text
    var translation: String?
    if settings.translationEnabled {
        var line = hint.translation
        if let label = registerLabel(hint.register) { line += " [\(label)]" }
        if let e = ezafe { line += "  \(e)" }
        translation = line
    }
    var romanization: String?
    if settings.romanizationEnabled && settings.display == .native, let r = hint.romanization {
        romanization = r + (ezafe ?? "")
    }
    var lines: [String] = []
    if let t = translation { lines.append(t) }
    if let r = romanization { lines.append(lines.isEmpty ? r : "[\(r)]") }
    if let e = ezafe, !settings.translationEnabled { lines.append("\(e) ezafe") }
    return lines
}

public enum AnnotatedLayoutKind: Equatable, Sendable {
    /// One flowing Text (letters still join across words); tappable words are underlined links.
    case inline
    /// A reading printed above every word, laid out word by word.
    case ruby
}

public struct AnnotatedRun: Equatable {
    public var index: Int
    /// What the base line shows for this run.
    public var text: String
    /// The segment as written, handed back with a tap.
    public var source: String
    public var isWord: Bool
    /// Only whitespace: dropped at a line start when wrapping.
    public var isGap: Bool
    /// The reading above the word (ruby kind only); "" is a blank one so lines don't jump, nil is not a word.
    public var reading: String?
    public var tip: [String]
    /// The word saved-words practice is drilling here (the exercise's `focusTag`): drawn highlighted.
    public var isFocus: Bool = false
    /// A word this lesson introduces (`newLexemes`): drawn highlighted, and tappable even with hints off.
    public var isNew: Bool = false

    public var isTappable: Bool { return !tip.isEmpty }
}

public struct AnnotatedPlan: Equatable {
    public var kind: AnnotatedLayoutKind
    public var rtl: Bool
    public var centered: Bool
    /// Multiplier on the caller's font size (the native script's size pref).
    public var fontScale: CGFloat
    public var runs: [AnnotatedRun]
}

/// The hints this exercise's text may use (web gateLexemeHintMap).
public func gatedHints(_ look: LessonTextLook, scriptMode: ExerciseScriptMode) -> [String: WordHint] {
    return gateLexemeHintMap(look.courseHints, settings: look.settings, exerciseScriptMode: scriptMode)
}

private func isBlank(_ s: String) -> Bool {
    return !s.isEmpty && s.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
}

/// Whether a word written with `hint` is one of `newLexemes`: of its senses, the ones the exercise is tagged with
/// when it names any (so a homograph's other lexeme doesn't count), else all of them.
public func isNewWord(_ hint: WordHint?, tags: [String], newLexemes: Set<String>) -> Bool {
    guard !newLexemes.isEmpty, let senses = hint?.senses, !senses.isEmpty else { return false }
    let tagged = senses.filter { tags.contains($0.tag) }
    return (tagged.isEmpty ? senses : tagged).contains { newLexemes.contains($0.tag) }
}

/// The settings a new word's tip is read with: translation and romanization on, whatever the learner chose.
private func revealing(_ settings: TextDisplaySettings) -> TextDisplaySettings {
    var on = settings
    on.translationEnabled = true
    on.romanizationEnabled = true
    return on
}

public func planAnnotatedText(_ text: String, scriptMode: ExerciseScriptMode, tags: [String], look: LessonTextLook, focusTag: String? = nil, newLexemes: Set<String> = []) -> AnnotatedPlan {
    let settings = look.settings
    let hints = gatedHints(look, scriptMode: scriptMode)
    // With hints gated off, new words are still looked up in the whole course map; every other word stays bare.
    let lookupAll = hints.isEmpty && !newLexemes.isEmpty
    let segments = segmentAnnotatedText(text, lookupAll ? look.courseHints : hints, tags: tags)
    let rtl = displayDirection(text, display: settings.display) == .rtl
    let native = rtl || (settings.display != .romanized && !hints.isEmpty)
    let ruby = settings.display == .both && !hints.isEmpty

    func plain(_ s: String) -> String {
        return settings.vowelMarks ? s : PersianNormalize.stripReadingAids(s)
    }

    var runs: [AnnotatedRun] = []
    for (index, segment) in segments.enumerated() {
        let new = segment.isWord && isNewWord(segment.hint, tags: tags, newLexemes: newLexemes)
        // A new word's hint only serves its tip when the gate would have dropped it.
        let hint = lookupAll ? nil : segment.hint
        var tip: [String] = []
        if segment.isWord, let h = hint { tip = tipLines(h, settings: settings) }
        if new && tip.isEmpty, let h = segment.hint { tip = tipLines(h, settings: revealing(settings)) }
        let gap = !segment.isWord && isBlank(segment.text)
        let focus = segment.isWord && focusTag != nil && (hint?.senses ?? []).contains { $0.tag == focusTag }
        if ruby {
            var reading: String?
            if segment.isWord {
                if let h = hint, let r = h.ruby {
                    reading = r + (h.ezafe?.text ?? "")
                } else {
                    reading = ""
                }
            }
            runs.append(AnnotatedRun(index: index, text: plain(segment.text), source: segment.text, isWord: segment.isWord, isGap: gap, reading: reading, tip: tip, isFocus: focus, isNew: new))
        } else {
            var base = plain(segment.text)
            if settings.display == .romanized, let h = hint, let r = h.romanization {
                base = r + (h.ezafe?.text ?? "")
            }
            runs.append(AnnotatedRun(index: index, text: base, source: segment.text, isWord: segment.isWord, isGap: gap, reading: nil, tip: tip, isFocus: focus, isNew: new))
        }
    }
    return AnnotatedPlan(
        kind: ruby ? .ruby : .inline,
        rtl: rtl,
        centered: native && look.centerNative,
        fontScale: native ? look.nativeScale : 1,
        runs: runs
    )
}

/// The whole sentence romanized above it (web SentenceRomanization): authored
/// when there is one, else built from the hints; nil when it shouldn't show.
public func sentenceRomanizationLine(_ text: String, authored: String?, scriptMode: ExerciseScriptMode, tags: [String], look: LessonTextLook) -> String? {
    guard look.settings.sentenceRomanization, look.settings.display != .romanized else { return nil }
    if let authored = authored { return authored }
    let hints = gatedHints(look, scriptMode: scriptMode)
    if hints.isEmpty { return nil }
    return romanizeSentence(text, hints, tags: tags)
}

/// Where each item of a flowing line goes: wrapped to `width`, bottom-aligned within its row
/// (so a word without a reading doesn't jump), a gap dropped at a row's start, mirrored when `rtl`.
public enum WordFlowGeometry {
    public struct Item: Equatable {
        public var size: CGSize
        public var isGap: Bool
        public init(size: CGSize, isGap: Bool) {
            self.size = size
            self.isGap = isGap
        }
    }

    public static func frames(items: [Item], width: CGFloat, rtl: Bool, centered: Bool, lineSpacing: CGFloat) -> [CGRect] {
        var rows: [[Int]] = [[]]
        var rowWidths: [CGFloat] = [0]
        for (i, item) in items.enumerated() {
            let last = rows.count - 1
            if rows[last].isEmpty && item.isGap { continue }
            if !rows[last].isEmpty && !item.isGap && rowWidths[last] + item.size.width > width + 0.01 {
                rows.append([])
                rowWidths.append(0)
            }
            let current = rows.count - 1
            rows[current].append(i)
            rowWidths[current] += item.size.width
        }
        var frames = [CGRect](repeating: .zero, count: items.count)
        var y: CGFloat = 0
        for (r, row) in rows.enumerated() {
            if row.isEmpty { continue }
            let height = row.map { items[$0].size.height }.max() ?? 0
            var offset: CGFloat = centered ? max(0, (width - rowWidths[r]) / 2) : 0
            for i in row {
                let size = items[i].size
                let x = rtl ? width - offset - size.width : offset
                frames[i] = CGRect(x: x, y: y + height - size.height, width: size.width, height: size.height)
                offset += size.width
            }
            y += height + lineSpacing
        }
        return frames
    }

    /// The height the frames occupy.
    public static func height(of frames: [CGRect]) -> CGFloat {
        return frames.map { $0.maxY }.max() ?? 0
    }
}
