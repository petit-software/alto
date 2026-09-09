import XCTest
@testable import AltoCore

final class ChunkerTests: XCTestCase {
    func testLongTailAndUnicodeArePreserved() {
        let text = String(repeating: "Hello 👩🏽‍💻! 123.45 and a very long sentence.\n", count: 100) + "TAIL"
        let chunks = TextChunker.split(text)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 220 })
        XCTAssertEqual(chunks.joined().filter { !$0.isWhitespace }, text.filter { !$0.isWhitespace })
        XCTAssertTrue(chunks.last!.hasSuffix("TAIL"))
    }
    func testEmptyAndUnbrokenText() {
        XCTAssertEqual(TextChunker.split(" \n"), [])
        XCTAssertEqual(TextChunker.split(String(repeating: "a", count: 501)).map(\.count), [220, 220, 61])
    }
}
