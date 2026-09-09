import AppKit
import ApplicationServices
import Carbon.HIToolbox

public struct ClipboardSnapshot {
    public let items: [[NSPasteboard.PasteboardType: Data]]
    public let changeCount: Int
    public static func capture(_ pasteboard: NSPasteboard) throws -> ClipboardSnapshot {
        let count = pasteboard.changeCount
        var total = 0
        let items = try (pasteboard.pasteboardItems ?? []).map { item in
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard !type.rawValue.localizedCaseInsensitiveContains("promise") else {
                    throw AltoError("Your clipboard contains promised files that cannot be restored. Copy the text manually and use Read Clipboard.")
                }
                guard let value = item.data(forType: type) else { throw AltoError("Your clipboard cannot be safely restored. Copy the selection yourself and use Read Clipboard.") }
                total += value.count
                guard total <= 64_000_000 else { throw AltoError("Your clipboard is too large to safely borrow. Use Read Clipboard after copying the selection.") }
                data[type] = value
            }
            return data
        }
        guard pasteboard.changeCount == count else { throw AltoError("The clipboard changed. Please try again.") }
        return ClipboardSnapshot(items: items, changeCount: count)
    }
    @discardableResult public func restore(_ pasteboard: NSPasteboard, ifUnchangedSince expected: Int) -> Bool {
        guard pasteboard.changeCount == expected else { return false }
        let restored = items.map { contents -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, value) in contents { item.setData(value, forType: type) }
            return item
        }
        pasteboard.clearContents()
        if !restored.isEmpty { return pasteboard.writeObjects(restored) }
        return true
    }
}

public enum SelectionReader {
    public static var hasPermission: Bool { AXIsProcessTrusted() }
    public static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    public static func openPermissionSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @MainActor public static func read(from pid: pid_t, allowClipboard: Bool) async throws -> String {
        guard hasPermission else { throw AltoError("macOS hasn't granted this copy of Alto Accessibility access. Open Alto Settings → General to enable it, or copy the text and use Read Clipboard.") }
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        let isChrome = bundleID == "com.google.Chrome" || bundleID.hasPrefix("com.google.Chrome.")
        let result = await Task.detached(priority: .userInitiated) { () async -> (String?, Bool) in
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.5)
            // Chromium exposes its complete accessibility tree on demand.
            // https://www.chromium.org/developers/design-documents/accessibility/
            if isChrome {
                let attribute = "AXEnhancedUserInterface" as CFString
                var enabled: CFTypeRef?
                AXUIElementCopyAttributeValue(app, attribute, &enabled)
                if enabled as? Bool != true,
                   AXUIElementSetAttributeValue(app, attribute, kCFBooleanTrue) == .success {
                    try? await Task.sleep(for: .milliseconds(150))
                }
            }
            var focused: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
                  let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return (nil, false) }
            let element = focused as! AXUIElement
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &role)
            if role as? String == kAXSecureTextFieldSubrole { return (nil, true) }
            var selected: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
               let text = selected as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return (text, false) }
            var range: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
               let range, CFGetTypeID(range) == AXValueGetTypeID() {
                var bounds = CFRange()
                if AXValueGetValue(range as! AXValue, .cfRange, &bounds), bounds.length > 0, bounds.length < 100_001 {
                    var string: CFTypeRef?
                    if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, range, &string) == .success,
                       let text = string as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return (text, false) }
                }
            }
            return (nil, false)
        }.value
        try Task.checkCancellation()
        if result.1 || IsSecureEventInputEnabled() { throw AltoError("Alto does not read protected fields or copy while secure input is enabled.") }
        if let text = result.0 { return try checked(text) }
        guard allowClipboard else { throw AltoError("This app doesn't expose selected text. Enable clipboard fallback, or copy and use Read Clipboard.") }
        for _ in 0..<30 {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        guard CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            throw AltoError("The focused app or shortcut modifiers changed. Select your text and try again.")
        }
        let pasteboard = NSPasteboard.general
        let original = try ClipboardSnapshot.capture(pasteboard)
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false) else {
            throw AltoError("Could not copy the selection.")
        }
        down.flags = .maskCommand; up.flags = .maskCommand
        try Task.checkCancellation()
        down.postToPid(pid); up.postToPid(pid)
        return try await finishCopy(on: pasteboard, original: original) {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        }
    }
    @MainActor static func finishCopy(on pasteboard: NSPasteboard, original: ClipboardSnapshot,
                                     isSourceFocused: () -> Bool) async throws -> String {
        // Finish this short clipboard transaction even if the reading is cancelled.
        // Never clear the original clipboard to detect a copy; changeCount suffices.
        var pendingCopyCount: Int?
        for _ in 0..<40 {
            // Cancellation must not turn the restore window into a busy loop
            // that ends before the source app finishes handling Copy.
            await Task.detached { try? await Task.sleep(for: .milliseconds(25)) }.value
            if pasteboard.changeCount != original.changeCount {
                let copiedCount = pasteboard.changeCount
                let text = pasteboard.string(forType: .string)
                // Copy can clear the pasteboard before supplying its text. Do
                // not restore during that intermediate empty state.
                pendingCopyCount = copiedCount
                guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let stillFocused = isSourceFocused()
                let restored = original.restore(pasteboard, ifUnchangedSince: copiedCount)
                try Task.checkCancellation()
                guard stillFocused, restored else { throw AltoError("The copy was ambiguous or contained no text. Please copy manually and use Read Clipboard.") }
                return try checked(text)
            }
        }
        if let pendingCopyCount { _ = original.restore(pasteboard, ifUnchangedSince: pendingCopyCount) }
        try Task.checkCancellation()
        throw AltoError("No selected text was copied. Try selecting text again, or use Read Clipboard.")
    }
    public static func checked(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AltoError("Select some text first.") }
        guard trimmed.count <= 100_000 else { throw AltoError("Select fewer than 100,000 characters at a time.") }
        return trimmed
    }
}
