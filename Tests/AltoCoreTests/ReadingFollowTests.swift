import XCTest
@testable import AltoCore

final class ReadingFollowTests: XCTestCase {
    func testChunksAreLocatedInOrderInsidePreviewText() {
        let text = SpeechText.prepare("First sentence here. Second one follows.\n\nA new paragraph. The end.")
        let chunks = TextChunker.split(text, limit: 24)
        let ranges = ReadingFollow.locate(chunks, in: text)
        XCTAssertEqual(ranges.count, chunks.count)
        for (chunk, range) in zip(chunks, ranges) { XCTAssertEqual(String(text[range]), chunk) }
        XCTAssertEqual(ReadingFollow.locate(["missing"], in: text).first?.isEmpty, true)
    }
    func testFractionSnapsToWholeWords() throws {
        let text = "Intro.\n\nThe quick brown fox jumps.  Done."
        let chunk = try XCTUnwrap(text.range(of: "The quick brown fox jumps."))
        func word(_ fraction: Double) -> String {
            String(text[ReadingFollow.highlight(in: text, chunk: chunk, fraction: fraction)!.word])
        }
        XCTAssertEqual(word(0), "The")
        XCTAssertEqual(word(0.05), "The")
        XCTAssertEqual(word(0.16), "quick")   // lands on the space after "The"
        XCTAssertEqual(word(0.5), "brown")
        XCTAssertEqual(word(0.99), "jumps.")
        XCTAssertEqual(word(1), "jumps.")
        XCTAssertEqual(word(-1), "The")
        XCTAssertEqual(ReadingFollow.highlight(in: text, chunk: chunk, fraction: 0.5)?.chunk, chunk)
        XCTAssertNil(ReadingFollow.highlight(in: text, chunk: text.startIndex..<text.startIndex, fraction: 0.5))
    }
}
