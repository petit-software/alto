import Foundation

/// Where reading currently is inside the preview text: the passage being
/// played and the word estimated from playback progress through it.
public struct ReadingHighlight: Equatable, Sendable {
    public let chunk: Range<String.Index>
    public let word: Range<String.Index>
    public init(chunk: Range<String.Index>, word: Range<String.Index>) { self.chunk = chunk; self.word = word }
}

/// The speech model gives no word timestamps, so the position inside a
/// passage is estimated from the fraction of its audio already rendered,
/// mapped proportionally onto its characters and snapped to a word.
public enum ReadingFollow {
    /// Ranges of each chunk in `text`, in order. Chunks are trimmed substrings
    /// of the text; one that cannot be found gets an empty range.
    public static func locate(_ chunks: [String], in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var cursor = text.startIndex
        for chunk in chunks {
            if let range = text.range(of: chunk, range: cursor..<text.endIndex) {
                ranges.append(range); cursor = range.upperBound
            } else {
                ranges.append(cursor..<cursor)
            }
        }
        return ranges
    }
    public static func highlight(in text: String, chunk: Range<String.Index>, fraction: Double) -> ReadingHighlight? {
        guard !chunk.isEmpty, chunk.upperBound <= text.endIndex else { return nil }
        let count = text.distance(from: chunk.lowerBound, to: chunk.upperBound)
        let offset = min(count - 1, max(0, Int((Double(count) * fraction).rounded(.down))))
        var index = text.index(chunk.lowerBound, offsetBy: offset)
        while index < chunk.upperBound, text[index].isWhitespace { index = text.index(after: index) }
        if index == chunk.upperBound {
            index = text.index(before: chunk.upperBound)
            while index > chunk.lowerBound, text[index].isWhitespace { index = text.index(before: index) }
        }
        var start = index
        while start > chunk.lowerBound, !text[text.index(before: start)].isWhitespace { start = text.index(before: start) }
        var end = index
        while end < chunk.upperBound, !text[end].isWhitespace { end = text.index(after: end) }
        return ReadingHighlight(chunk: chunk, word: start..<end)
    }
}
