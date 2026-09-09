import XCTest
@testable import AltoCore

final class SpeechTextTests: XCTestCase {
    func testTagsPreserveContentAndParagraphBoundaries() {
        XCTAssertEqual(SpeechText.prepare("<p>Hello <b>world</b>.</p><p>Next.</p>"), "Hello world.\n\nNext.")
        XCTAssertEqual(SpeechText.prepare(#"<span title="a > b">Hello</span><!-- hidden -->!"#), "Hello!")
        XCTAssertEqual(SpeechText.prepare("<voice name='heart'>Hello</voice>"), "Hello")
    }
    func testEmojiClustersDoNotRemoveOrdinaryNumbersAndSymbols() {
        XCTAssertEqual(SpeechText.prepare("Hello👩🏽‍💻world 🇨🇭 👨‍👩‍👧‍👦 👍🏾 ❤️ 1️⃣"), "Hello world")
        XCTAssertEqual(SpeechText.prepare("123.45 #topic * 2 < 3 and 5 > 4 © ® ™"), "123.45 #topic * 2 < 3 and 5 > 4 © ® ™")
    }
    func testEmojiOrTagsOnlyBecomesEmpty() {
        XCTAssertEqual(SpeechText.prepare("<p>🎉😀</p>"), "")
        XCTAssertEqual(SpeechText.prepare("<br/><div></div>"), "")
    }
}
