import Foundation

/// The lenient readers for the values feeds get wrong: dates in a dozen forms, durations in
/// four, numbers with stray spaces.
public enum FeedValues {
    /// RFC 822 as feeds actually write it — with or without the weekday or seconds, with named
    /// or numeric zones, single-digit days — and ISO 8601 for Atom and the careless.
    public static func date(_ text: String?) -> Date? {
        guard var text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if let iso = isoDate(text) { return iso }
        // Zone names DateFormatter doesn't know.
        for (name, offset) in [(" UT", " +0000"), (" Z", " +0000"), (" EDT", " -0400"), (" EST", " -0500"), (" CDT", " -0500"), (" CST", " -0600"), (" MDT", " -0600"), (" MST", " -0700"), (" PDT", " -0700"), (" PST", " -0800"), (" CEST", " +0200"), (" CET", " +0100")] where text.hasSuffix(name) {
            text = String(text.dropLast(name.count)) + offset
            break
        }
        for formatter in rfc822 {
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    private static func isoDate(_ text: String) -> Date? {
        guard text.first?.isNumber == true, text.contains("-") else { return nil }
        if text.count == 10 {
            let day = ISO8601DateFormatter()
            day.formatOptions = [.withFullDate]
            return day.date(from: text)
        }
        guard text.contains("T") else { return nil }
        let full = ISO8601DateFormatter()
        if let date = full.date(from: text) { return date }
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return full.date(from: text)
    }

    private static let rfc822: [DateFormatter] = [
        "EEE, d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss zzz", "EEE, d MMM yyyy HH:mm Z",
        "d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm Z", "EEE, d MMM yyyy HH:mm:ss", "EEE, d MMM yyyy",
        "EEE d MMM yyyy HH:mm:ss Z", "EEEE, d MMMM yyyy HH:mm:ss Z", "EEE, d MMMM yyyy HH:mm:ss Z",
        "yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd HH:mm:ss",
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }

    /// `itunes:duration` in every form seen: "1:02:03", "62:03", "3723", "3723.5", "1:2:3".
    /// Nil for zero, junk, or anything over a week.
    public static func durationMs(_ text: String?) -> Int64? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard (1...3).contains(parts.count) else { return nil }
        var seconds = 0.0
        for part in parts {
            guard let value = Double(part), value >= 0 else { return nil }
            seconds = seconds * 60 + value
        }
        guard seconds > 0, seconds < 7 * 86_400 else { return nil }
        return Int64((seconds * 1000).rounded())
    }

    /// Chapter times: "01:02:03.500", "62:03", "3723.5", "3723".
    public static func timeMs(_ text: String?) -> Int64? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text == "0" || text == "00:00:00" || text == "00:00:00.000" { return 0 }
        return durationMs(text)
    }

    public static func int(_ text: String?) -> Int? {
        text.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// "yes", "true", "explicit" are explicit; "no", "false", "clean" are not.
    public static func flag(_ text: String?) -> Bool {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
        return text == "yes" || text == "true" || text == "explicit"
    }

    /// A URL as feeds write them: trimmed, spaces escaped, protocol-relative made https.
    public static func url(_ text: String?) -> URL? {
        guard var text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.hasPrefix("//") { text = "https:" + text }
        text = text.replacingOccurrences(of: " ", with: "%20")
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        return url
    }
}
