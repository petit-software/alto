import XCTest
import Carbon.HIToolbox
@testable import AltoCore

final class HotkeyTests: XCTestCase {
    func testDisableReleasesShortcutAndAllowsReenable() async throws {
        try await MainActor.run {
            let shortcut = GlobalHotkey()
            let competitor = GlobalHotkey()
            defer { shortcut.unregister(); competitor.unregister() }
            let key = UInt32(kVK_F18)
            let flags = UInt32(controlKey | optionKey | shiftKey | cmdKey)
            try shortcut.register(key: key, modifiers: flags)
            XCTAssertThrowsError(try competitor.register(key: key, modifiers: flags))
            shortcut.disable()
            try competitor.register(key: key, modifiers: flags)
            competitor.disable()
            try shortcut.register(key: key, modifiers: flags)
            shortcut.disable()
            try shortcut.register(key: key, modifiers: flags)
        }
    }
}
