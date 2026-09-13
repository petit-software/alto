import AppKit

/// Receives “Listen with Alto” from the Services submenu of other apps. macOS
/// hands over a private pasteboard holding the host's selection, launching Alto
/// first when needed. The selector name must match `NSMessage` in Info.plist.
@MainActor final class ServiceProvider: NSObject {
    static let menuTitle = "Listen with Alto"
    private let handler: (NSPasteboard) -> Void
    init(handler: @escaping (NSPasteboard) -> Void) { self.handler = handler }
    @objc func listenWithAlto(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        handler(pasteboard)
    }
}
