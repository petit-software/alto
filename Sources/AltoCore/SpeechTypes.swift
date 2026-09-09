import Foundation

public struct AltoError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct SpeechRequest: Codable, Sendable {
    public var model: String
    public var voice: String
    public var text: String
    public var output: String
    public init(model: String, voice: String, text: String, output: String) {
        self.model = model; self.voice = voice; self.text = text; self.output = output
    }
}

public struct SpeechResponse: Codable, Sendable {
    public var error: String?
    public var samples: Int
    public var seconds: Double
    public init(error: String? = nil, samples: Int = 0, seconds: Double = 0) {
        self.error = error; self.samples = samples; self.seconds = seconds
    }
}

public enum TextChunker {
    /// Keep every non-whitespace character, including the tail of long sentences.
    public static func split(_ text: String, limit: Int = 220) -> [String] {
        guard limit > 0 else { return [] }
        var result: [String] = []
        var rest = text[...]
        while !rest.isEmpty {
            let end = rest.index(rest.startIndex, offsetBy: min(limit, rest.count))
            let prefix = rest[..<end]
            var cut = end
            if end != rest.endIndex {
                let minimum = max(1, prefix.count / 3)
                let candidates = prefix.indices.dropFirst(minimum)
                if let boundary = candidates.last(where: { ".!?\n;".contains(prefix[$0]) }) {
                    cut = rest.index(after: boundary)
                } else if let boundary = candidates.last(where: { prefix[$0].isWhitespace }) {
                    cut = rest.index(after: boundary)
                }
            }
            let part = rest[..<cut].trimmingCharacters(in: .whitespacesAndNewlines)
            if !part.isEmpty { result.append(part) }
            rest = rest[cut...]
        }
        return result
    }
}
