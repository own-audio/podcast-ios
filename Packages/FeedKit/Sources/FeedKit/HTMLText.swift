import Foundation

/// Show notes come as HTML (often inside CDATA). The app shows them as text with paragraphs,
/// so this turns markup into lines without a web view and without UIKit, which wants the main
/// thread for HTML. Links are kept as text; the episode page finds them again.
public enum HTMLText {
    public static func plain(_ html: String) -> String {
        guard html.contains("<") || html.contains("&") else { return collapse(html) }
        var text = html
        // Blocks become line breaks, list items get a bullet.
        for (pattern, replacement) in [
            ("(?i)<br\\s*/?>", "\n"), ("(?i)</p\\s*>", "\n\n"), ("(?i)</div\\s*>", "\n"), ("(?i)</h[1-6]\\s*>", "\n\n"),
            ("(?i)<li[^>]*>", "\n• "), ("(?i)</li\\s*>", ""), ("(?i)</(ul|ol)\\s*>", "\n\n"),
            ("(?is)<(script|style)[^>]*>.*?</\\1\\s*>", ""), ("(?s)<!--.*?-->", ""), ("(?s)<[^>]+>", ""),
        ] {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return collapse(decodeEntities(text))
    }

    /// The named entities feeds use, and every numeric one.
    public static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        out.reserveCapacity(text.count)
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            guard character == "&", let semicolon = text[index...].prefix(12).firstIndex(of: ";") else {
                out.append(character)
                index = text.index(after: index)
                continue
            }
            let name = String(text[text.index(after: index)..<semicolon])
            if let decoded = entity(name) {
                out.append(decoded)
                index = text.index(after: semicolon)
            } else {
                out.append(character)
                index = text.index(after: index)
            }
        }
        return out
    }

    private static func entity(_ name: String) -> String? {
        if name.hasPrefix("#") {
            let digits = name.dropFirst()
            let value = digits.first == "x" || digits.first == "X" ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
            return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        return named[name]
    }

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "ndash": "–", "mdash": "—",
        "hellip": "…", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "laquo": "«", "raquo": "»",
        "bdquo": "„", "copy": "©", "reg": "®", "trade": "™", "euro": "€", "middot": "·", "bull": "•", "deg": "°",
    ]

    /// Runs of spaces become one, three or more line breaks become two, ends are trimmed.
    private static func collapse(_ text: String) -> String {
        var text = text.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "[ \t\u{00A0}]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: " *\n *", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
