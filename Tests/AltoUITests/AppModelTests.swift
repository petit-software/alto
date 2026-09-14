import XCTest
import AppKit
import SwiftUI
import Carbon.HIToolbox
import AltoCore
@testable import AltoUI

final class AppModelTests: XCTestCase {
    @MainActor func testEditorAppearanceChangesPreserveTextAndUseSystemColors() {
        let editor = ReaderTextView()
        editor.string = "Keep the draft."
        var brightness: [CGFloat] = []
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = NSAppearance(named: name)!
            editor.appearance = appearance
            editor.updateAppearanceColors()
            appearance.performAsCurrentDrawingAppearance {
                let color = editor.textColor!.usingColorSpace(.deviceRGB)!
                brightness.append((color.redComponent + color.greenComponent + color.blueComponent) / 3)
                XCTAssertEqual(editor.insertionPointColor, NSColor.textColor)
            }
            XCTAssertEqual(editor.string, "Keep the draft.")
        }
        XCTAssertGreaterThan(brightness[1], brightness[0])
    }

    func testPlayerPositionsUseClioEdgeGapAndClampCursor() {
        let frame = NSRect(x: -1600, y: 100, width: 1600, height: 900)
        let size = NSSize(width: 300, height: 240)
        let cursor = NSPoint(x: -1599, y: 101)
        for position in PlayerPosition.allCases where position != .hidden {
            let origin = position.origin(size: size, frame: frame, cursor: cursor)
            XCTAssertTrue(frame.contains(NSRect(origin: origin, size: size)))
        }
        XCTAssertEqual(PlayerPosition.bottomLeft.origin(size: size, frame: frame, cursor: cursor), NSPoint(x: -1550, y: 150))
        XCTAssertEqual(PlayerPosition.topRight.origin(size: size, frame: frame, cursor: cursor), NSPoint(x: -350, y: 710))
        XCTAssertEqual(PlayerPosition.bottomCenter.origin(size: size, frame: frame, cursor: cursor).x, -950)
        let tiny = NSRect(x: 0, y: 0, width: 200, height: 100)
        let clamped = PlayerPosition.nearCursor.origin(size: size, frame: tiny, cursor: .zero)
        XCTAssertGreaterThanOrEqual(clamped.x, 0)
        XCTAssertGreaterThanOrEqual(clamped.y, 0)
    }

    @MainActor func testPlayerAppearancePersistsAndHiddenDoesNotStopReading() throws {
        try withModel { app, preferences in
            XCTAssertEqual(app.playerPosition, .bottomCenter)
            XCTAssertEqual(app.playerOpacity, 0.45)
            XCTAssertFalse(app.playerClearGlass)
            app.generation = .loading
            var hidden = 0
            app.hidePlayer = { hidden += 1 }
            app.playerPosition = .hidden
            XCTAssertEqual(hidden, 1)
            XCTAssertTrue(app.isActive)
            app.playerPosition = .topRight
            app.playerOpacity = 0.18
            app.playerClearGlass = true
            let reopened = AppModel(modelStore: app.models, preferences: preferences, registerHotkey: false)
            XCTAssertEqual(reopened.playerPosition, .topRight)
            XCTAssertEqual(reopened.playerOpacity, 0.18)
            XCTAssertTrue(reopened.playerClearGlass)
            reopened.shutdown()
        }
    }

    @MainActor func testEditorPasteCleansTextWithoutChangingClipboard() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let source = " <b>world</b> 😀 "
        pasteboard.setString(source, forType: .string)
        let count = pasteboard.changeCount
        let editor = ReaderTextView()
        editor.isRichText = false
        editor.string = "Hello!"
        editor.setSelectedRange(NSRange(location: 5, length: 0))
        editor.pasteCleanText(from: pasteboard)
        XCTAssertEqual(editor.string, "Hello world !")
        XCTAssertEqual(pasteboard.string(forType: .string), source)
        XCTAssertEqual(pasteboard.changeCount, count)
        editor.isEditable = false
        editor.pasteCleanText(from: pasteboard)
        XCTAssertEqual(editor.string, "Hello world !")
    }

    @MainActor func testEmbeddedPlayerOmitsStatusColumnAtEverySize() throws {
        try withModel { app, _ in
            for size in PlayerSize.allCases {
                app.playerSize = size
                let view = NSHostingView(rootView: PlayerView(app: app, shown: true, embedded: true))
                XCTAssertEqual(view.fittingSize.width, 140 * size.rawValue + 28, accuracy: 1)
                XCTAssertEqual(view.fittingSize.height, 52 * size.rawValue + 28, accuracy: 1)
            }
        }
    }

    @MainActor func testReaderScrollerOnlyShowsForOverflow() {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .legacy
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 50))
        scroll.documentView = document
        TextReaderHostingView.configureScrollers(in: scroll)
        scroll.tile()
        XCTAssertTrue(scroll.autohidesScrollers)
        XCTAssertTrue(scroll.verticalScroller?.isHidden == true)
        document.setFrameSize(NSSize(width: 280, height: 1000))
        scroll.tile()
        XCTAssertFalse(scroll.verticalScroller?.isHidden ?? true)
        document.setFrameSize(NSSize(width: 280, height: 50))
        scroll.tile()
        XCTAssertTrue(scroll.verticalScroller?.isHidden == true)
    }

    @MainActor func testTextReaderOpenErrorAndCloseLifecycle() throws {
        try withModel { app, _ in
            var opens = 0
            var closes = 0
            app.presentTextReader = { opens += 1 }
            app.closeTextReader = { closes += 1 }
            app.showWindow = { XCTFail("Draft errors must stay in the reader window") }
            app.generation = .loading
            app.openTextReader()
            XCTAssertTrue(app.isTextReaderOpen)
            XCTAssertFalse(app.isActive)
            XCTAssertEqual(opens, 1)
            app.draftText = "Keep this draft when reopening the visible window."
            app.openTextReader()
            XCTAssertFalse(app.draftText.isEmpty)
            XCTAssertEqual(opens, 2)
            app.read("")
            XCTAssertNotNil(app.message)
            XCTAssertTrue(app.isTextReaderOpen)
            XCTAssertEqual(closes, 0)
            app.stopAndDismiss()
            XCTAssertFalse(app.isTextReaderOpen)
            XCTAssertTrue(app.draftText.isEmpty)
            XCTAssertFalse(app.hasReading)
            XCTAssertEqual(closes, 1)
            app.stopAndDismiss()
            XCTAssertEqual(closes, 1)
        }
    }

    @MainActor func testDeveloperPreviewKeepsLongTextInBoundedScrollableLayout() {
        for size in PlayerSize.allCases {
            let scale = size.rawValue
            let short = NSHostingView(rootView: ReadingPreview(text: "Selected text.", scale: scale)).fittingSize
            let long = NSHostingView(rootView: ReadingPreview(text: String(repeating: "Selected text.\n", count: 1000), scale: scale)).fittingSize
            XCTAssertEqual(short.width, 320 * scale, accuracy: 1)
            XCTAssertEqual(long.width, short.width, accuracy: 1)
            XCTAssertEqual(long.height, short.height, accuracy: 1)
            XCTAssertGreaterThan(short.height, 120 * scale)
        }
    }

    @MainActor func testPlayerSizePersistsAndResizesLayoutWithoutOpeningIdlePlayer() throws {
        try withModel { app, preferences in
            XCTAssertEqual(app.playerSize, .standard)
            var presentations = 0
            app.showPlayer = { presentations += 1 }
            for size in PlayerSize.allCases {
                app.playerSize = size
                XCTAssertEqual(preferences.double(forKey: "playerSize"), size.rawValue)
                let view = NSHostingView(rootView: PlayerView(app: app, shown: true))
                XCTAssertEqual(view.fittingSize.height, 52 * size.rawValue + 28, accuracy: 1)
                XCTAssertEqual(view.fittingSize.width, 244 * size.rawValue + 28, accuracy: 1)
                let reopened = AppModel(modelStore: app.models, preferences: preferences, registerHotkey: false)
                XCTAssertEqual(reopened.playerSize, size)
                reopened.shutdown()
            }
            XCTAssertEqual(presentations, 0)
            preferences.set(9, forKey: "playerSize")
            let invalid = AppModel(modelStore: app.models, preferences: preferences, registerHotkey: false)
            XCTAssertEqual(invalid.playerSize, .standard)
            invalid.shutdown()
        }
    }

    @MainActor func testCaptureFailureNeverShowsPlayer() async throws {
        let suite = "software.petit.alto.tests." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("alto-ui-test-" + UUID().uuidString)
        let failed = expectation(description: "Capture failure is shown in settings")
        let app = AppModel(modelStore: ModelStore(root: root), preferences: preferences, registerHotkey: false,
            selectionReader: { _, _ in throw AltoError("No selected text was copied.") })
        defer {
            app.shutdown(); preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        var presentations = 0
        app.showPlayer = { presentations += 1 }
        app.showWindow = { failed.fulfill() }
        app.readSelection(from: 123)
        XCTAssertEqual(presentations, 0)
        XCTAssertFalse(app.hasReading)
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertEqual(presentations, 0)
        XCTAssertFalse(app.isActive)
        XCTAssertNotNil(app.message)
    }

    @MainActor func testDismissCancelsCaptureAndIgnoresLateResult() async throws {
        let suite = "software.petit.alto.tests." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("alto-ui-test-" + UUID().uuidString)
        let started = expectation(description: "Capture started")
        var resume: CheckedContinuation<String, Never>?
        var captureWasCancelled = false
        let app = AppModel(modelStore: ModelStore(root: root), preferences: preferences, registerHotkey: false,
            selectionReader: { _, _ in
                let text = await withCheckedContinuation { continuation in
                    resume = continuation; started.fulfill()
                }
                captureWasCancelled = Task.isCancelled
                return text
            })
        defer {
            app.shutdown(); preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        var presentations = 0
        app.showPlayer = { presentations += 1 }
        app.showWindow = { XCTFail("Cancelled capture must not open settings") }
        app.readSelection(from: 123)
        await fulfillment(of: [started], timeout: 2)
        app.stopAndDismiss()
        resume?.resume(returning: "Late selection must never start reading.")
        await app.finishCaptureBeforeQuitting()
        XCTAssertTrue(captureWasCancelled)
        XCTAssertFalse(app.hasPendingCapture)
        XCTAssertFalse(app.isActive)
        XCTAssertFalse(app.hasReading)
        XCTAssertNil(app.message)
        XCTAssertEqual(presentations, 0)
    }

    @MainActor private func withModel(_ body: (AppModel, UserDefaults) throws -> Void) throws {
        let suite = "software.petit.alto.tests." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        preferences.set(false, forKey: "shortcutEnabled")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("alto-ui-test-" + UUID().uuidString)
        let app = AppModel(modelStore: ModelStore(root: root), preferences: preferences, registerHotkey: false)
        defer {
            app.shutdown()
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        try body(app, preferences)
    }

    func testExplicitStopDismissesButInternalStopDoesNot() async throws {
        try await MainActor.run {
            try withModel { app, _ in
                var dismissals = 0
                app.hidePlayer = { dismissals += 1 }
                app.generation = .loading
                app.playback = .paused
                app.stop()
                XCTAssertFalse(app.isActive)
                XCTAssertEqual(dismissals, 0)
                app.stopAndDismiss()
                XCTAssertEqual(dismissals, 1)
                XCTAssertFalse(app.isPaused)
            }
        }
    }

    func testDisabledShortcutCanBeEditedWithoutClaimingKeys() async throws {
        try await MainActor.run {
            try withModel { app, preferences in
                let owner = GlobalHotkey()
                defer { owner.unregister() }
                let flags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
                try owner.register(key: UInt32(kVK_F19), modifiers: GlobalHotkey.carbonFlags(flags))
                let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                    timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                    isARepeat: false, keyCode: UInt16(kVK_F19))!
                try app.recordShortcut(event)
                XCTAssertFalse(app.shortcutEnabled)
                XCTAssertEqual(preferences.integer(forKey: "keyCode"), kVK_F19)
                app.setShortcutEnabled(true)
                XCTAssertFalse(app.shortcutEnabled)
                XCTAssertNotNil(app.message)
                owner.disable()
                app.setShortcutEnabled(true)
                XCTAssertTrue(app.shortcutEnabled)
                app.setShortcutEnabled(false)
                XCTAssertFalse(preferences.bool(forKey: "shortcutEnabled"))
                try owner.register(key: UInt32(kVK_F19), modifiers: GlobalHotkey.carbonFlags(flags))
            }
        }
    }

    func testAllDestinationsUseSettingsTabs() {
        XCTAssertEqual(SettingsTab.allCases, [.general, .models, .reading, .about])
    }

    func testSetupRoutesToPermissionsThenModels() async throws {
        try await MainActor.run {
            try withModel { app, _ in
                app.permissionGranted = false
                XCTAssertEqual(app.setupTab, .general)
                app.permissionGranted = true
                XCTAssertEqual(app.setupTab, .models)
                app.settingsTab = .models
                XCTAssertEqual(app.settingsTab, .models)
            }
        }
    }
}

final class ServiceTests: XCTestCase {
    @MainActor func testServiceReadsPrivatePasteboardWithoutTouchingClipboard() throws {
        let suite = "software.petit.alto.tests." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        preferences.set(false, forKey: "shortcutEnabled")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("alto-service-test-" + UUID().uuidString)
        let app = AppModel(modelStore: ModelStore(root: root), preferences: preferences, registerHotkey: false)
        defer { app.shutdown(); preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(app.skipPageClutter)
        let general = NSPasteboard.general.changeCount
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString(PageTextFixture.page, forType: .string)
        var received: NSPasteboard?
        let provider = ServiceProvider { received = $0 }
        var error: NSString?
        provider.listenWithAlto(pasteboard, userData: nil, error: &error)
        XCTAssertTrue(received === pasteboard)
        var opened = 0
        app.showWindow = { opened += 1 }
        app.readService(pasteboard)
        // No voice model is installed in the test store: the cleaned text reached the reading path and stopped there.
        XCTAssertEqual(app.message, "Download and select a voice model in Models to start listening.")
        XCTAssertEqual(opened, 1)
        XCTAssertEqual(NSPasteboard.general.changeCount, general)
        app.skipPageClutter = false
        XCTAssertFalse(AppModel(modelStore: app.models, preferences: preferences, registerHotkey: false).skipPageClutter)
    }
}

enum PageTextFixture {
    static let page = """
    About
    Articles
    Sign in
    Subscribe
    Lifted AF ⊗ Cyborgs, centaurs and cyberpunks
    In e-flux Journal, McKenzie Wark reviews Exocapitalism: Economies with Absolutely No Limits by Marek Poliks and Roberto Alonso Trillo. The authors start from the premise that the critical tradition gets capitalism wrong and needs a new vocabulary to describe it.
    The book’s central idea is “Lift.” Physical production comes with workers, fixed costs, and problems of scale, and companies would rather avoid all of it. A hotel company stops running hotels and becomes a brand, a financing arm, and a data business.
    Back issues
    Membership
    Sign up
    """
}

final class StatusIconTests: XCTestCase {
    @MainActor func testMenuBarGlyphIsTemplateWithWavesAndDot() throws {
        let image = StatusIcon.image()
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 25, height: 15))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 250, pixelsHigh: 150, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: 250, height: 150))
        NSGraphicsContext.restoreGraphicsState()
        func alpha(_ x: Int, _ yFromTop: Int) -> CGFloat { bitmap.colorAt(x: x, y: yFromTop)?.alphaComponent ?? 0 }
        XCTAssertGreaterThan(alpha(123, 73), 0.9, "centre dot is solid")
        XCTAssertGreaterThan(alpha(64, 73), 0.9, "inner left wave")
        XCTAssertGreaterThan(alpha(183, 73), 0.9, "inner right wave")
        XCTAssertGreaterThan(alpha(13, 73), 0.9, "outer left wave")
        XCTAssertGreaterThan(alpha(233, 73), 0.9, "outer right wave")
        XCTAssertLessThan(alpha(88, 73), 0.1, "gap between wave and dot")
        XCTAssertLessThan(alpha(5, 5), 0.1, "corner is clear")
    }
}

final class FollowReadingTests: XCTestCase {
    @MainActor func testPreviewWithHighlightAndToggleKeepsLayoutAndPersistsSetting() throws {
        let text = String(repeating: "Selected text to read.\n", count: 40)
        let chunk = try XCTUnwrap(text.range(of: "Selected text to read."))
        let highlight = ReadingHighlight(chunk: chunk, word: chunk.lowerBound..<text.index(chunk.lowerBound, offsetBy: 8))
        for size in PlayerSize.allCases {
            let plain = NSHostingView(rootView: ReadingPreview(text: text, scale: size.rawValue)).fittingSize
            let highlighted = NSHostingView(rootView: ReadingPreview(text: text, scale: size.rawValue, highlight: highlight, follow: .constant(true))).fittingSize
            XCTAssertEqual(plain, highlighted)
            XCTAssertEqual(highlighted.width, 320 * size.rawValue, accuracy: 1)
        }
        let suite = "software.petit.alto.tests." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        preferences.set(false, forKey: "shortcutEnabled")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("alto-follow-test-" + UUID().uuidString)
        let app = AppModel(modelStore: ModelStore(root: root), preferences: preferences, registerHotkey: false)
        defer { app.shutdown(); preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(app.followReading)
        XCTAssertNil(app.readingHighlight)
        app.followReading = false
        XCTAssertFalse(AppModel(modelStore: app.models, preferences: preferences, registerHotkey: false).followReading)
        XCTAssertNil(app.audio.playingProgress())
    }
}
