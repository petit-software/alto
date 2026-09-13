import AppKit

/// Drops page clutter (navigation, share prompts, captions, forms, legal
/// footers) from text captured through Services, Read Clipboard or Paste,
/// keeping the article prose and its headings. Deterministic and host-neutral:
/// works on plain text, and uses link density and attachments when rich text
/// is available. Falls back to the unchanged text when it cannot find prose.
public enum PageText {
    public struct Block: Equatable {
        public var text: String
        public var linkDensity: Double
        public init(_ text: String, linkDensity: Double = 0) { self.text = text; self.linkDensity = linkDensity }
        var words: Int { text.split(whereSeparator: \.isWhitespace).filter { $0.contains(where: \.isLetter) || $0.contains(where: \.isNumber) }.count }
    }
    enum Kind { case prose, short, clutter }

    /// Prefers rich text so link-heavy paragraphs and images are recognised.
    public static func clean(from pasteboard: NSPasteboard) -> String {
        let plain = pasteboard.string(forType: .string)
        if let data = pasteboard.data(forType: .rtf), let rich = NSAttributedString(rtf: data, documentAttributes: nil) {
            return clean(blocks: blocks(from: rich), fallback: plain ?? rich.string)
        }
        return clean(plain ?? "")
    }
    public static func clean(_ text: String) -> String { clean(blocks: blocks(from: text), fallback: text) }

    static func blocks(from text: String) -> [Block] {
        SpeechText.prepare(text, trim: false).components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : Block(trimmed)
        }
    }
    static func blocks(from rich: NSAttributedString) -> [Block] {
        var result: [Block] = []
        let string = rich.string as NSString
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byParagraphs) { _, range, _, _ in
            var linked = 0, visible = 0
            rich.enumerateAttributes(in: range, options: []) { attributes, sub, _ in
                guard attributes[.attachment] == nil else { return }
                let count = string.substring(with: sub).filter { !$0.isWhitespace }.count
                visible += count
                if attributes[.link] != nil { linked += count }
            }
            let density = visible > 0 ? Double(linked) / Double(visible) : 0
            let paragraph = string.substring(with: range).replacingOccurrences(of: "\u{FFFC}", with: "")
            for block in blocks(from: paragraph) { result.append(Block(block.text, linkDensity: density)) }
        }
        return result
    }

    static func clean(blocks: [Block], fallback: String) -> String {
        let kinds = blocks.map(kind(of:))
        var kept = [Bool](repeating: true, count: blocks.count)
        // Navigation and footer menus: runs of three or more non-prose blocks.
        // A run may end with the article title, so heading-like blocks that
        // directly precede prose survive.
        var index = 0
        while index < blocks.count {
            guard kinds[index] != .prose else { index += 1; continue }
            var end = index
            while end < blocks.count, kinds[end] != .prose { end += 1 }
            var stop = end
            if end - index >= 3 {
                if end < blocks.count {
                    var peeled = 0
                    while peeled < 2, stop > index, isHeading(blocks[stop - 1], kinds[stop - 1]), blocks[stop - 1].words >= 3 { stop -= 1; peeled += 1 }
                }
                for i in index..<stop { kept[i] = false }
            }
            for i in index..<end where kinds[i] == .clutter { kept[i] = false }
            index = end
        }
        // Head: only heading-like blocks immediately before the first prose survive.
        if let first = kinds.indices.first(where: { kinds[$0] == .prose && kept[$0] }) {
            var headings = 0
            for i in stride(from: first - 1, through: 0, by: -1) where kept[i] {
                if headings < 2, isHeading(blocks[i], kinds[i]) { headings += 1 } else { kept[i] = false }
            }
        }
        if let last = kinds.indices.last(where: { kinds[$0] == .prose && kept[$0] }) {
            for i in (last + 1)..<blocks.count { kept[i] = false }
        }
        var seen = Set<String>()
        for i in blocks.indices where kept[i] {
            let key = blocks[i].text.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if !seen.insert(key).inserted { kept[i] = false }
        }
        let survivors = blocks.indices.filter { kept[$0] }
        let keptWords = survivors.reduce(0) { $0 + blocks[$1].words }
        let totalWords = blocks.reduce(0) { $0 + $1.words }
        guard survivors.contains(where: { kinds[$0] == .prose }), keptWords >= max(50, totalWords / 4) else {
            return SpeechText.prepare(fallback)
        }
        return survivors.map { blocks[$0].text }.joined(separator: "\n\n")
    }

    static func isHeading(_ block: Block, _ kind: Kind) -> Bool { kind == .short && block.linkDensity < 0.6 }
    static func kind(of block: Block) -> Kind {
        let text = block.text, words = block.words
        let lower = text.lowercased()
        guard words > 0, text.contains(where: \.isLetter) else { return .clutter }
        if words <= 8 {
            if lower.contains("©") { return .clutter }
            for pattern in [urlPattern, emailPattern, datePattern, readTimePattern] where pattern.firstMatch(in: lower) != nil { return .clutter }
            let bare = lower.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
            if phrases.contains(where: { bare == $0 || bare.hasPrefix($0 + " ") }) { return .clutter }
        }
        if words <= 60 {
            if lower.contains("cookie"), ["accept", "consent", "we use"].contains(where: lower.contains) { return .clutter }
            if legal.contains(where: lower.contains) { return .clutter }
        }
        if words <= 40, captionPattern.firstMatch(in: lower) != nil { return .clutter }
        if block.linkDensity >= 0.6 { return .short }
        if listPattern.firstMatch(in: text) != nil, words >= 4 { return .prose }
        let terminal = text.last.map { ".!?…\"”’')".contains($0) } ?? false
        if words >= 12 || (words >= 6 && terminal) { return .prose }
        return .short
    }

    private static let phrases = ["skip to content", "skip to main content", "sign in", "log in", "login", "sign up", "register",
        "subscribe", "share", "menu", "search", "cookie", "accept all", "privacy policy", "terms of service", "terms of use",
        "all rights reserved", "read more", "back to top", "follow us", "advertisement", "sponsored", "newsletter",
        "leave a comment", "comments", "related", "related posts", "you might also like", "next", "previous", "home"]
    private static let legal = ["all rights reserved", "creative commons", "cookie policy", "privacy policy", "terms of service",
        "terms of use", "powered by"]
    private static let urlPattern = try! NSRegularExpression(pattern: #"^(?:https?://|www\.)\S+$"#)
    private static let emailPattern = try! NSRegularExpression(pattern: #"\S+@\S+\.\S+"#)
    private static let datePattern = try! NSRegularExpression(pattern:
        #"^(?:(?:mon|tues?|wed(?:nes)?|thu(?:rs)?|fri|sat(?:ur)?|sun)(?:day)?,?\s+)?(?:(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+\d{1,2},?\s+\d{4}|\d{1,2}\s+(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+\d{4}|\d{4}-\d{2}-\d{2})$"#)
    private static let readTimePattern = try! NSRegularExpression(pattern: #"^\d+\s*(?:min(?:ute)?s?|hours?)\s+read$"#)
    private static let captionPattern = try! NSRegularExpression(pattern:
        #"^(?:photo|photograph|image|illustration|screenshot|credit|source|caption)\b|photo by|image credit|image sourced|image courtesy|credit:|getty images|shutterstock|unsplash|wikimedia"#)
    private static let listPattern = try! NSRegularExpression(pattern: #"^(?:[•\-–—*·]|\d{1,3}[.)])\s"#)
}

private extension NSRegularExpression {
    func firstMatch(in text: String) -> NSTextCheckingResult? {
        firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }
}
