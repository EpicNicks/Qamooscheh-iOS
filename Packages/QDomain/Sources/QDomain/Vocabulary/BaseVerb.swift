import Foundation
import QModel

// A verb's base form (its infinitive) as a word to save (API_SPEC 2.4 and 2.8, Qamooscheh-Backend#102).
// Every verb lemma has an infinitive entry in lexemes.json; saving it practises every form of the verb.

/// Whether `entry` is a verb's base form: saving it pulls in sentences with any of its forms.
public func isBaseVerb(_ entry: LexemeIndexEntry?) -> Bool {
    return entry?.pos == "verb" && entry?.verbForm == "infinitive"
}

/// Each lemma's infinitive tag. A lemma with two infinitive entries keeps the first by tag, so the pick never
/// depends on dictionary order.
public func baseVerbIndex(_ lexemes: [String: LexemeIndexEntry]) -> [String: String] {
    var index: [String: String] = [:]
    for (tag, entry) in lexemes where isBaseVerb(entry) {
        guard let lemma = entry.lemma, !lemma.isEmpty else { continue }
        if let kept = index[lemma], kept < tag { continue }
        index[lemma] = tag
    }
    return index
}

/// The infinitive a verb form offers to save beside itself: the entry with verbForm "infinitive" and the same
/// `lemma`. Nil for a word that isn't a verb, has no lemma, is that infinitive itself, or whose infinitive isn't there.
public func baseVerbTag(of tag: String, lexemes: [String: LexemeIndexEntry], index: [String: String]) -> String? {
    guard let entry = lexemes[tag], entry.pos == "verb", let lemma = entry.lemma, !lemma.isEmpty,
          let base = index[lemma], base != tag else { return nil }
    return base
}
