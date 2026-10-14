import Foundation
import CoreGraphics
import ImageIO

/// What a share card shows. Ported from Android `ShareCardContent` (ShareCard.kt), which has only the
/// lesson-complete card; `.streak` is the iOS plan's second card. Deliberately carries no name, id,
/// token or URL: the card is an image plus the headline text, nothing else leaves the device.
///
/// Defined here as a minimal input struct because the lesson engine (M5) is not merged yet; the lesson
/// result screen builds one from its own state later.
public struct ShareCardContent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case lessonComplete
        case streak
    }

    public static let maxHeadline = 60
    public static let maxWord = 40
    public static let maxLine = 60
    public static let maxXP = 99_999
    public static let maxStreakDays = 99_999

    public let kind: Kind
    public let headline: String
    /// Hidden on the streak card and when zero.
    public let xp: Int
    /// Hidden when nil or not positive.
    public let streakDays: Int?
    /// Native script word.
    public let word: String?
    /// Romanization of `word`.
    public let reading: String?
    public let gloss: String?

    /// Normalizes every field: blanks become nil, lengths and numbers are capped, control characters dropped.
    public init(kind: Kind = .lessonComplete, headline: String? = nil, xp: Int = 0, streakDays: Int? = nil,
                word: String? = nil, reading: String? = nil, gloss: String? = nil) {
        self.kind = kind
        let fallback = kind == .streak ? "Keep it going!" : "Lesson complete!"
        self.headline = ShareCardContent.clean(headline, limit: ShareCardContent.maxHeadline) ?? fallback
        self.xp = kind == .streak ? 0 : min(max(xp, 0), ShareCardContent.maxXP)
        if let days = streakDays, days > 0 {
            self.streakDays = min(days, ShareCardContent.maxStreakDays)
        } else {
            self.streakDays = nil
        }
        self.word = ShareCardContent.clean(word, limit: ShareCardContent.maxWord)
        self.reading = ShareCardContent.clean(reading, limit: ShareCardContent.maxLine)
        self.gloss = ShareCardContent.clean(gloss, limit: ShareCardContent.maxLine)
    }

    /// A streak card for `days` (nil when the streak is not positive, so there is nothing to share).
    public static func streak(days: Int, word: String? = nil, reading: String? = nil, gloss: String? = nil) -> ShareCardContent? {
        guard days > 0 else { return nil }
        return ShareCardContent(kind: .streak, headline: nil, xp: 0, streakDays: days, word: word, reading: reading, gloss: gloss)
    }

    public var xpLine: String? { xp > 0 ? "+\(xp) XP" : nil }
    public var streakLine: String? { streakDays.map { "\($0)-day streak" } }
    public var glossLine: String? { gloss.map { "\u{201C}" + $0 + "\u{201D}" } }

    /// The text sent with the image: the headline only (Android sends the headline as EXTRA_TEXT).
    public var shareText: String { headline }
    public var fileName: String { "parsling-card.png" }

    /// Spoken description of the card (the image itself is not readable by VoiceOver).
    public var accessibilityText: String {
        var parts = [headline]
        if let line = xpLine { parts.append(line) }
        if let line = streakLine { parts.append(line) }
        if let word = word { parts.append(word) }
        if let reading = reading { parts.append(reading) }
        if let gloss = gloss { parts.append(gloss) }
        return parts.joined(separator: ", ")
    }

    static func clean(_ value: String?, limit: Int) -> String? {
        guard let value = value else { return nil }
        let kept = value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let text = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        return String(text.prefix(limit))
    }
}

public enum ShareCardPNG {
    public enum EncodeError: Error, Equatable {
        case destinationUnavailable
        case finalizeFailed
    }

    /// PNG bytes for `image`, or a thrown error (never an empty Data).
    public static func encode(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            throw EncodeError.destinationUnavailable
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw EncodeError.finalizeFailed }
        return data as Data
    }
}
