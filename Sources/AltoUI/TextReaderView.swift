import AppKit
import SwiftUI

struct TextReaderView: View {
    @Bindable var app: AppModel
    @State private var pasteRequest = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message = app.message {
                Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28).padding(.top, 8)
            }
            if app.selectedModel == nil {
                Button("Download a Voice Model…") { app.showModels?() }
                    .padding(.horizontal, 28).padding(.top, 8)
            }
            ReaderTextEditor(text: $app.draftText, editable: !app.hasReading, pasteRequest: pasteRequest,
                             bottomInset: 52 * app.playerSize.rawValue + 44)
                .padding(.horizontal, 28).padding(.top, 24)
        }
        .frame(minWidth: 480, minHeight: 480)
        .background(.white)
        .overlay(alignment: .bottom) {
            PlayerView(app: app, shown: true, embedded: true, onPaste: { pasteRequest += 1 })
                .padding(.bottom, 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(.black.opacity(0.18), lineWidth: 0.5))
        .environment(\.colorScheme, .light)
        .onExitCommand { app.stopAndDismiss() }
    }
}

private final class TextReaderWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func performClose(_ sender: Any?) { close() }
}

final class TextReaderHostingView: NSHostingView<TextReaderView> {
    override func layout() {
        super.layout()
        Self.configureScrollers(in: self)
    }
    static func configureScrollers(in view: NSView) {
        // TextEditor uses an AppKit scroll view. Hide its scroller when the
        // document fits, including when macOS is set to always show scroll bars.
        if let scroll = view as? NSScrollView, !scroll.autohidesScrollers {
            scroll.autohidesScrollers = true
        }
        for child in view.subviews { configureScrollers(in: child) }
    }
}

@MainActor final class TextReaderController: NSObject, NSWindowDelegate {
    private let app: AppModel
    private let window: NSWindow
    init(app: AppModel) {
        self.app = app
        window = TextReaderWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
                          styleMask: [.borderless, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Read Text"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 480, height: 480)
        window.contentView = TextReaderHostingView(rootView: TextReaderView(app: app))
        window.delegate = self
        window.center()
    }
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
    }
    func hide() { window.orderOut(nil) }
    func windowWillClose(_ notification: Notification) { app.stopAndDismiss() }
}
