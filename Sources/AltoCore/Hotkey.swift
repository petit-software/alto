import AppKit
import Carbon.HIToolbox

private func altoHotkeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?) -> OSStatus {
    guard let context else { return OSStatus(eventNotHandledErr) }
    let owner = Unmanaged<GlobalHotkey>.fromOpaque(context).takeUnretainedValue()
    Task { @MainActor in owner.onPress?() }
    return noErr
}

@MainActor public final class GlobalHotkey {
    public var onPress: (() -> Void)?
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    public init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), altoHotkeyHandler, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    public func register(key: UInt32, modifiers: UInt32) throws {
        // Register the replacement first, so a conflict doesn't remove the old shortcut.
        var replacement: EventHotKeyRef?
        let result = RegisterEventHotKey(key, modifiers, EventHotKeyID(signature: 0x414C544F, id: 1),
                                        GetApplicationEventTarget(), 0, &replacement)
        guard result == noErr else { throw AltoError("That shortcut is already in use. Choose another combination.") }
        if let reference { UnregisterEventHotKey(reference) }
        reference = replacement
    }
    public func disable() {
        if let reference { UnregisterEventHotKey(reference) }; reference = nil
    }
    public func unregister() {
        disable()
        if let handler { RemoveEventHandler(handler) }; handler = nil
    }
    public static func carbonFlags(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}
