import AppKit
import SwiftUI
import AltoCore

final class ReaderTextView: NSTextView {
    override func paste(_ sender: Any?) { pasteCleanText(from: .general) }
    override func pasteAsPlainText(_ sender: Any?) { pasteCleanText(from: .general) }
    override func pasteAsRichText(_ sender: Any?) { pasteCleanText(from: .general) }
    func pasteCleanText(from pasteboard: NSPasteboard) {
        guard isEditable, let source = pasteboard.string(forType: .string) else { return }
        let cleaned = SpeechText.prepare(source, trim: false)
        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        insertText(cleaned, replacementRange: selectedRange())
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            window?.performClose(nil); return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.window?.makeFirstResponder(self)
            }
        }
    }
}

struct ReaderTextEditor: NSViewRepresentable {
    @Binding var text: String
    var editable: Bool
    var pasteRequest: Int
    var bottomInset: CGFloat = 0
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let editor = ReaderTextView(frame: .zero)
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 17)
        editor.textColor = .black
        editor.insertionPointColor = .black
        editor.textContainerInset = NSSize(width: 0, height: 8)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.setAccessibilityLabel("Text to read")
        editor.delegate = context.coordinator
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        // Let the last lines scroll above the overlaid player, without taking
        // a permanent footer out of the editor's viewport.
        if scroll.contentInsets.bottom != bottomInset {
            scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        }
        guard let editor = scroll.documentView as? ReaderTextView else { return }
        editor.isEditable = editable
        if editor.string != text {
            editor.string = text
            editor.undoManager?.removeAllActions()
        }
        if context.coordinator.lastPasteRequest != pasteRequest {
            context.coordinator.lastPasteRequest = pasteRequest
            DispatchQueue.main.async { [weak editor] in
                guard let editor else { return }
                editor.window?.makeFirstResponder(editor)
                editor.paste(nil)
            }
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ReaderTextEditor
        var lastPasteRequest: Int
        init(_ parent: ReaderTextEditor) { self.parent = parent; lastPasteRequest = parent.pasteRequest }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
}
