import Foundation

/// Date handling for the wire: .NET DateTimeOffset values are ISO-8601 strings
/// with an offset (or Z) and up to seven fractional digits. DateOnly values are
/// modelled as plain yyyy-MM-dd strings, not Date, because they are buckets.
public enum QDates {
    /// Parses an ISO-8601 instant, tolerating any number of fractional digits.
    public static func parse(_ text: String) -> Date? {
        var base = text
        var fraction = 0.0
        if let dot = text.firstIndex(of: ".") {
            var end = text.index(after: dot)
            while end < text.endIndex, text[end] >= "0", text[end] <= "9" {
                end = text.index(after: end)
            }
            let digits = String(text[text.index(after: dot)..<end])
            fraction = Double("0." + digits) ?? 0
            base = String(text[..<dot]) + String(text[end...])
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: base) else { return nil }
        return date.addingTimeInterval(fraction)
    }

    /// Formats as UTC with millisecond precision.
    public static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

/// Coders configured for the Qamooscheh wire format.
public enum QJSON {
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = QDates.parse(text) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Invalid ISO-8601 date: \(text)")
            }
            return date
        }
        return decoder
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(QDates.format(date))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
