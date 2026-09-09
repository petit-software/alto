import AppKit
import XCTest
@testable import AltoCore

final class ClipboardTests: XCTestCase {
    @MainActor func testDelayedCopyWaitsPastEmptyStateAndRestores() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("original", forType: .string)
        let snapshot = try ClipboardSnapshot.capture(pasteboard)
        pasteboard.clearContents()
        let writer = Task { @MainActor in
            try await Task.sleep(for: .milliseconds(100))
            pasteboard.setString("selected text", forType: .string)
        }
        let text = try await SelectionReader.finishCopy(on: pasteboard, original: snapshot, isSourceFocused: { true })
        try await writer.value
        XCTAssertEqual(text, "selected text")
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }

    @MainActor func testCancelledCopyStillWaitsAndRestores() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("original", forType: .string)
        let snapshot = try ClipboardSnapshot.capture(pasteboard)
        pasteboard.clearContents()
        let capture = Task { @MainActor in
            try await SelectionReader.finishCopy(on: pasteboard, original: snapshot, isSourceFocused: { true })
        }
        capture.cancel()
        try await Task.sleep(for: .milliseconds(100))
        pasteboard.setString("late selected text", forType: .string)
        do { _ = try await capture.value; XCTFail("Cancelled copy must not return text") }
        catch is CancellationError { }
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }

    func testRestoresEveryItemAndType() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let first = NSPasteboardItem()
        first.setString("original", forType: .string)
        let richText = try NSAttributedString(string: "original").data(from: NSRange(location: 0, length: 8), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        first.setData(richText, forType: .rtf)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32)!
        let png = bitmap.representation(using: .png, properties: [:])!
        let second = NSPasteboardItem(); second.setData(png, forType: .png)
        pasteboard.writeObjects([first, second])
        let snapshot = try ClipboardSnapshot.capture(pasteboard)
        pasteboard.clearContents(); pasteboard.setString("selected", forType: .string)
        XCTAssertTrue(snapshot.restore(pasteboard, ifUnchangedSince: pasteboard.changeCount))
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 2)
        XCTAssertEqual(pasteboard.pasteboardItems?[0].data(forType: .rtf), richText)
        XCTAssertEqual(pasteboard.pasteboardItems?[1].data(forType: .png), png)
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }
    func testInterveningWriteWins() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("original", forType: .string)
        let snapshot = try ClipboardSnapshot.capture(pasteboard)
        pasteboard.clearContents(); pasteboard.setString("selection", forType: .string)
        let expected = pasteboard.changeCount
        pasteboard.clearContents(); pasteboard.setString("newer user copy", forType: .string)
        XCTAssertFalse(snapshot.restore(pasteboard, ifUnchangedSince: expected))
        XCTAssertEqual(pasteboard.string(forType: .string), "newer user copy")
    }
    func testEmptyClipboardRestoresEmpty() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let snapshot = try ClipboardSnapshot.capture(pasteboard)
        pasteboard.setString("selection", forType: .string)
        XCTAssertTrue(snapshot.restore(pasteboard, ifUnchangedSince: pasteboard.changeCount))
        XCTAssertNil(pasteboard.string(forType: .string))
    }
}
