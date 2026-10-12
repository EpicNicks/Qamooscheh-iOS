import Foundation

// Hover hints for a word written with endings attached (مادرم "my mother",
// خسته‌ام "I'm tired", کتاب‌ها "books") that has no lexeme of its own. The
// lexeme index already lists the endings themselves, tagged with a leading
// tatweel: "ـم<poss>" (my), "ـم<v><spoken>" (am), "ـها<pl>" (plural), with
// any other spelling in `forms` (ـم is written ‌ام after a vowel). So a word
// that misses the hint map is split into a stem the map knows plus up to
// maxEndings known endings. Nothing new has to be authored per word.
//
// The written word doesn't say where its stem ends (سَرَم is one word), but
// the exercise's `tags` say which pieces it's made of (سر<n>, ـم<poss>). A
// split built only from those is trusted outright, whatever the stem's
// length, and names just the tagged senses: "head + -am (my)". Failing that
// (a decoy tile, or text with no tags) any split the course-wide map allows
// is used, guarded against false splits, and an ending gets its GENERAL
// meaning, every sense it has: "mother + -am (am / my)".
// Port of web attachedEndings.ts. Words are handled as Unicode scalars, as the
// JS does on UTF-16 units: Swift's String suffix tests are grapheme based.

/// How an ending is written in a lexeme tag: attached to nothing, after a tatweel.
private let attachMark: Unicode.Scalar = "\u{0640}"
private let maxEndings = 3

/// Without tags to go on, a stem an ending is written straight onto (no
/// half-space) has to be at least this long, unless it ends in a consonant:
/// shorter vowel-final ones find false splits among ordinary words (نون,
/// bread, is not نو "new" + ن "are (they)"; ماست, yogurt, is not ما + ست),
/// while a short consonant-final one is a real word taking it (سرم, my head).
private let minJoinedStem = 3

private let letterAlef: Unicode.Scalar = "\u{0627}"
private let letterWaw: Unicode.Scalar = "\u{0648}"
private let letterYeh: Unicode.Scalar = "\u{06CC}"
private let letterHeh: Unicode.Scalar = "\u{0647}"
private let halfSpace: Unicode.Scalar = "\u{200C}"

/// Letters a Persian word can end in with a vowel sound written out.
private func endsOnVowel(_ text: [Unicode.Scalar]) -> Bool {
    guard let last = text.last else { return false }
    return last == letterAlef || last == letterWaw || last == letterYeh
}

/// endsOnVowel plus the silent heh (خسته), which takes endings behind a half-space too.
private func endsOnVowelOrHeh(_ text: [Unicode.Scalar]) -> Bool {
    return endsOnVowel(text) || text.last == letterHeh
}

private func scalarsEndWith(_ text: [Unicode.Scalar], _ suffix: [Unicode.Scalar]) -> Bool {
    if suffix.count > text.count { return false }
    return Array(text[(text.count - suffix.count)...]) == suffix
}

private func scalarsLess(_ a: String, _ b: String) -> Bool {
    return a.unicodeScalars.lexicographicallyPrecedes(b.unicodeScalars) { $0.value < $1.value }
}

/// Every ending the map knows (without its tatweel), longest first so ـمون wins over ـن.
/// Ties are ordered by code point: a Swift Dictionary has no insertion order to lean on.
private func endingsOf(_ hintMap: [String: WordHint]) -> [String] {
    var endings: [String] = []
    for key in hintMap.keys {
        let scalars = Array(key.unicodeScalars)
        if scalars.count > 1 && scalars[0] == attachMark {
            endings.append(scalarString(Array(scalars.dropFirst())))
        }
    }
    return endings.sorted { a, b in
        let la = a.unicodeScalars.count
        let lb = b.unicodeScalars.count
        if la != lb { return la > lb }
        return scalarsLess(a, b)
    }
}

/// A stem or ending of a split, with the senses it's read in.
private struct Piece {
    var hint: WordHint
    var senses: [WordSense]
}

/// A written stem or ending (an ending with its tatweel) as a piece, or nil when it can't be one.
private typealias PieceReader = (_ written: String) -> Piece?

private func sensesOf(_ hint: WordHint) -> [WordSense] {
    return hint.senses ?? [WordSense(tag: "", pos: "", translation: hint.translation, romanization: hint.romanization)]
}

/// Anything the map knows, in every sense.
private func anyLexeme(_ hintMap: [String: WordHint]) -> PieceReader {
    return { written in
        guard let hint = hintMap[written] else { return nil }
        return Piece(hint: hint, senses: sensesOf(hint))
    }
}

/// Only this exercise's lexemes, in only their tagged senses.
private func taggedLexeme(_ hintMap: [String: WordHint], _ tags: Set<String>) -> PieceReader {
    return { written in
        guard let hint = hintMap[written] else { return nil }
        let senses = sensesOf(hint).filter { tags.contains($0.tag) }
        return senses.isEmpty ? nil : Piece(hint: hint, senses: senses)
    }
}

/// An ending as written without its tatweel, and whether it's written straight on (no half-space).
private struct SplitEnding {
    var written: String
    var piece: Piece
    var joined: Bool
}

/// `endings` run stem outward.
private struct Split {
    var stem: Piece
    var endings: [SplitEnding]
}

/// Every way `word` reads as a stem plus endings `read` accepts. `tagged`
/// lifts the short-stem guard: a split the exercise's tags spell out is no guess.
private func splits(_ word: [Unicode.Scalar], _ read: PieceReader, _ endings: [String], _ depth: Int, _ tagged: Bool) -> [Split] {
    var found: [Split] = []
    if depth > 0, let stem = read(scalarString(word)) {
        found.append(Split(stem: stem, endings: []))
    }
    if depth == maxEndings { return found }
    for ending in endings {
        guard let piece = read(String(attachMark) + ending) else { continue }
        let endingScalars = Array(ending.unicodeScalars)
        for separator in [[halfSpace], []] as [[Unicode.Scalar]] {
            let written = separator + endingScalars
            if !scalarsEndWith(word, written) { continue }
            let rest = Array(word[0..<(word.count - written.count)])
            if rest.isEmpty { continue }
            if !tagged && separator.isEmpty && rest.count < minJoinedStem && endsOnVowelOrHeh(rest) { continue }
            // A ی written straight onto a vowel is the ezafe ("of": عموی من, my
            // uncle; see Ezafe.swift), not an ending; "you are" is spelled ‌ای there.
            if separator.isEmpty && endingScalars == [letterYeh] && endsOnVowel(rest) { continue }
            for inner in splits(rest, read, endings, depth + 1, tagged) {
                found.append(Split(
                    stem: inner.stem,
                    endings: inner.endings + [SplitEnding(written: ending, piece: piece, joined: separator.isEmpty)]
                ))
            }
        }
    }
    return found
}

/// The most plausible split: fewest endings, then the longest ending next to
/// the stem. کتاب‌هام is کتاب + ها + م (books + my), not کتاب + ه + ام.
/// The first of equally good candidates wins.
private func bestSplit(_ candidates: [Split]) -> Split? {
    var best: Split?
    for candidate in candidates {
        if let current = best {
            if isBetter(candidate, current) { best = candidate }
        } else {
            best = candidate
        }
    }
    return best
}

private func isBetter(_ a: Split, _ b: Split) -> Bool {
    if a.endings.count != b.endings.count { return a.endings.count < b.endings.count }
    for i in 0..<a.endings.count {
        let la = a.endings[i].written.unicodeScalars.count
        let lb = b.endings[i].written.unicodeScalars.count
        if la != lb { return la > lb }
    }
    return false
}

private let attachedNotePattern = try! NSRegularExpression(pattern: ", attached[^()]*")
// JS `\s`, spelled out (see Android PortableRegex.kt JS_SPACE): ICU's own \s differs.
private let parentheticalPattern = try! NSRegularExpression(
    pattern: #"[\t\n\u000B\f\r    -     　﻿]*\(([^()]*)\)"#
)
private let authoringNotePattern = try! NSRegularExpression(pattern: #"attached|[:=]|\p{Script=Arabic}"#)

private func matches(_ regex: NSRegularExpression, _ s: String) -> Bool {
    return regex.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
}

/// A gloss trimmed of its authoring notes, keeping what tells senses apart:
/// "are (you; attached to a predicate)" -> "are (you)", "my (attached to a
/// noun: سرم = my head)" -> "my", "mom (everyday word: …)" -> "mom", while
/// "uncle (father's brother)" stays whole. A parenthetical part goes when it
/// explains attachment, gives an example (":", "=", Persian script), or both.
public func tidyGloss(_ gloss: String) -> String {
    var text = gloss as NSString
    if let note = attachedNotePattern.firstMatch(in: gloss, range: NSRange(location: 0, length: text.length)) {
        text = text.replacingCharacters(in: note.range, with: "") as NSString
    }
    let source = text
    var out = ""
    var cursor = 0
    for match in parentheticalPattern.matches(in: source as String, range: NSRange(location: 0, length: source.length)) {
        out += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
        let inner = source.substring(with: match.range(at: 1))
        let kept = inner
            .components(separatedBy: ";")
            .map { jsTrim($0) }
            .filter { !$0.isEmpty && !matches(authoringNotePattern, $0) }
        if !kept.isEmpty { out += " (\(kept.joined(separator: "; ")))" }
        cursor = match.range.location + match.range.length
    }
    out += source.substring(from: cursor)
    return jsTrim(out)
}

/// An ending's meaning in the senses it's read in: each one's gloss, trimmed,
/// with a meaning two senses share said once. ـش is "his / her" (a possessive)
/// and "him / her / it" (an object), so "his / her / him / it". A sense whose
/// gloss is nothing but an authoring note (the relative ـی's) contributes nothing.
private func meaningOf(_ ending: Piece) -> String {
    var meanings: [String] = []
    for sense in ending.senses {
        for meaning in tidyGloss(sense.translation).components(separatedBy: " / ") {
            let trimmed = jsTrim(meaning)
            if !trimmed.isEmpty && !meanings.contains(trimmed) { meanings.append(trimmed) }
        }
    }
    return meanings.joined(separator: " / ")
}

private func romanizationOf(_ piece: Piece) -> String? {
    for sense in piece.senses {
        if let r = sense.romanization { return r }
    }
    return nil
}

/// a e i o u ā ī ū ō
private let romanVowels: Set<Unicode.Scalar> = ["a", "e", "i", "o", "u", "\u{0101}", "\u{012B}", "\u{016B}", "\u{014D}"]

/// JS's `.`: anything but a line terminator.
private func isJsLineTerminator(_ s: Unicode.Scalar) -> Bool {
    return s == "\n" || s == "\r" || s == "\u{2028}" || s == "\u{2029}"
}

/// An ending's romanization added on. Written straight onto a vowel, its own
/// leading vowel isn't said: پام is pā + -am = pām, پاش pāsh. A lone vowel
/// (-e, "is") stays, and so does one behind a half-space (خسته‌ام, khasteam).
private func appendEnding(_ stem: String, _ ending: String, _ joined: Bool) -> String {
    var suffix = Array(ending.unicodeScalars)
    if suffix.first == "-" { suffix.removeFirst() }
    let stemEndsOnVowel = Array(stem.unicodeScalars).last.map { romanVowels.contains($0) } ?? false
    let suffixVowelThenMore = suffix.count >= 2 && romanVowels.contains(suffix[0]) && !isJsLineTerminator(suffix[1])
    let added = joined && stemEndsOnVowel && suffixVowelThenMore ? Array(suffix.dropFirst()) : suffix
    return stem + scalarString(added)
}

/// The hint for `word` read as a known stem plus attached endings, or nil
/// when it doesn't split that way. Only ever consulted for a word the map has
/// no entry for. `tags` are the exercise's own lexeme tags, tried first.
public func attachedEndingsHint(_ word: String, _ hintMap: [String: WordHint], tags: Set<String>? = nil) -> WordHint? {
    let endings = endingsOf(hintMap)
    if endings.isEmpty { return nil }
    let scalars = Array(word.unicodeScalars)
    var parts: Split?
    if let tags = tags, !tags.isEmpty {
        parts = bestSplit(splits(scalars, taggedLexeme(hintMap, tags), endings, 0, true))
    }
    if parts == nil {
        parts = bestSplit(splits(scalars, anyLexeme(hintMap), endings, 0, false))
    }
    guard let split = parts, let stemSense = split.stem.senses.first else { return nil }

    var glosses = [tidyGloss(stemSense.translation)]
    var romanization = romanizationOf(split.stem)
    for ending in split.endings {
        let endingRomanization = romanizationOf(ending.piece)
        let label = endingRomanization ?? "-\(ending.written)"
        let meaning = meaningOf(ending.piece)
        glosses.append(meaning.isEmpty ? label : "\(label) (\(meaning))")
        if let stemRomanization = romanization, let endingRomanization = endingRomanization {
            romanization = appendEnding(stemRomanization, endingRomanization, ending.joined)
        } else {
            romanization = nil
        }
    }

    return WordHint(
        translation: glosses.joined(separator: " + "),
        romanization: romanization,
        ruby: romanization,
        register: split.stem.hint.register
    )
}
