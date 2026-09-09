import Foundation

/// Speech-only cleanup. Never changes the source selection or clipboard.
public enum SpeechText {
    public static func prepare(_ text: String, trim: Bool = true) -> String {
        var text = text.replacingOccurrences(of: #"(?s)<!--.*?-->"#, with: "", options: .regularExpression)
        let tags = try! NSRegularExpression(pattern: #"</?([A-Za-z][A-Za-z0-9:_-]*)(?:\s+[A-Za-z_:][A-Za-z0-9:_.-]*(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?)*\s*/?>"#)
        let blocks: Set<String> = ["p", "div", "br", "hr", "li", "ul", "ol", "h1", "h2", "h3", "h4", "h5", "h6", "section", "article", "tr", "td", "th", "blockquote", "pre"]
        for match in tags.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: text), let nameRange = Range(match.range(at: 1), in: text) else { continue }
            let separator = blocks.contains(text[nameRange].lowercased()) ? "\n" : ""
            text.replaceSubrange(range, with: separator)
        }
        text = text.map { character -> String in
            let scalars = character.unicodeScalars
            let emoji = scalars.contains { scalar in
                scalar.properties.isEmojiPresentation ||
                (scalar.properties.isEmoji && scalar.value > 0x7F && ![0xA9, 0xAE, 0x2122].contains(scalar.value))
            } || (scalars.contains { $0.value == 0xFE0F || $0.value == 0x20E3 } && scalars.contains { $0.properties.isEmoji })
            // Work on whole grapheme clusters, including flags, skin tones and
            // joined families; leave a separator so adjacent words don't fuse.
            return emoji ? " " : String(character)
        }.joined()
        let cleaned = text.replacingOccurrences(of: #"[^\S\n]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n(?: *\n)+"#, with: "\n\n", options: .regularExpression)
        return trim ? cleaned.trimmingCharacters(in: .whitespacesAndNewlines) : cleaned
    }
}
