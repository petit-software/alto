import SwiftUI
import AppKit
import AltoCore

// Adapted from Clio's OverlayView and PillSurface: 52pt capsule, 14pt shadow
// allowance, appearance-aware tinted glass, hairline, and two soft shadows.
struct PlayerView: View {
    @Bindable var app: AppModel
    var shown: Bool
    var embedded = false
    var onPaste: (() -> Void)? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var dark: Bool { scheme == .dark }
    private var scale: CGFloat { app.playerSize.rawValue }
    var body: some View {
        VStack(spacing: 10 * scale) {
            if !embedded, app.playerPosition.isTop { pill }
            if !embedded, !app.readingText.isEmpty {
                ReadingPreview(text: app.readingText, scale: scale, highlight: app.readingHighlight,
                               follow: Binding(get: { app.followReading }, set: { app.followReading = $0 }))
            }
            if embedded || !app.playerPosition.isTop { pill }
        }
        .scaleEffect(shown || reduceMotion ? 1 : 0.94)
        .opacity(shown ? 1 : 0)
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.15), value: shown)
        .padding(14).fixedSize()
    }
    private var pill: some View {
        HStack(spacing: 12 * scale) {
            if embedded {
                Button { onPaste?() } label: {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 13 * scale, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28 * scale, height: 28 * scale)
                }.buttonStyle(.plain).disabled(app.hasReading || onPaste == nil)
                    .help("Paste text from clipboard").accessibilityLabel("Paste text from clipboard")
            }
            Button { if embedded { app.playDraft() } else { app.togglePause() } } label: {
                Image(systemName: app.isPaused || !app.hasReading ? "play.fill" : "pause.fill")
                    .font(.system(size: 14 * scale, weight: .bold)).frame(width: 32 * scale, height: 32 * scale)
                    .background(Color.altoAccent.opacity(0.17), in: Circle())
            }.buttonStyle(.plain).disabled(embedded ? (!app.hasReading && !app.canReadDraft) : !app.isActive)
                .help(!app.hasReading ? "Read text" : app.isPaused ? "Resume" : "Pause")
                .accessibilityLabel(!app.hasReading ? "Read text" : app.isPaused ? "Resume reading" : "Pause reading")
            if !embedded {
                VStack(alignment: .leading, spacing: 2 * scale) {
                Text(app.status).font(.system(size: 12 * scale, weight: .semibold)).lineLimit(1)
                Text(app.hasReading ? "Passage \(min(app.currentSentence + 1, app.totalSentences)) of \(app.totalSentences)" : "Paste text, then press play")
                    .font(.system(size: 10 * scale)).foregroundStyle(.secondary).lineLimit(1)
                }.frame(width: 132 * scale, alignment: .leading)
                    .help("Audio is generated on this Mac")
            }
            Button { app.stopAndDismiss() } label: {
                Image(systemName: "xmark").font(.system(size: (embedded ? 13 : 10) * scale, weight: .bold))
                    .foregroundStyle(.secondary).frame(width: 28 * scale, height: 28 * scale)
                    .background {
                        if !embedded { Circle().fill(.primary.opacity(0.07)) }
                    }
            }.buttonStyle(.plain).help("Stop and dismiss").accessibilityLabel("Stop and dismiss player")
        }
        .padding(.horizontal, 14 * scale).frame(height: 52 * scale)
        .modifier(PlayerSurface(opacity: app.playerOpacity, clear: app.playerClearGlass, embedded: embedded))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(dark ? 0.34 : 0.08), radius: 8, x: 0, y: 3)
        .shadow(color: .black.opacity(dark ? 0.24 : 0.08), radius: 2, x: 0, y: 1)
    }
}

struct ReadingPreview: View {
    let text: String
    let scale: CGFloat
    var highlight: ReadingHighlight? = nil
    var follow: Binding<Bool> = .constant(false)
    var body: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            HStack {
                Text("Preview")
                    .font(.system(size: 11 * scale, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Toggle("Follow", isOn: follow)
                    .toggleStyle(.switch).controlSize(.mini)
                    .font(.system(size: 10 * scale)).foregroundStyle(.secondary)
                    .help("Highlight the passage and word being read")
                    .accessibilityLabel("Follow reading")
            }
            .padding(.horizontal, 12 * scale).padding(.top, 12 * scale)
            // The text runs to the panel's bottom edge; its inset keeps glyphs off the corners.
            PreviewTextView(text: text, highlight: highlight, follow: follow.wrappedValue, scale: scale)
                .frame(height: 120 * scale)
        }
        .frame(width: 320 * scale)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14 * scale))
        .clipShape(RoundedRectangle(cornerRadius: 14 * scale))
        .overlay(RoundedRectangle(cornerRadius: 14 * scale).strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }
}

/// Text whose container stops short of the right edge, so lines never run
/// under the overlay scroller.
final class PreviewText: NSTextView {
    var trailingInset: CGFloat = 0 { didSet { setFrameSize(frame.size) } }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        textContainer?.size = NSSize(width: max(1, newSize.width - textContainerInset.width * 2 - trailingInset),
                                     height: CGFloat.greatestFiniteMagnitude)
    }
}

/// Read-only AppKit text so the word being read can be scrolled into view
/// with a minimal move, which SwiftUI's Text cannot do for a substring. The
/// marker is a separate layer behind the text that glides between words;
/// text outside the passage being read is dimmed.
struct PreviewTextView: NSViewRepresentable {
    let text: String
    let highlight: ReadingHighlight?
    let follow: Bool
    let scale: CGFloat
    final class Coordinator {
        var chunk = NSRange(location: 0, length: 0)
        var word = NSRange(location: 0, length: 0)
        var scrolledTo: NSRange?
        let marker = NSView()
        var markerShown = false
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout); layout.addTextContainer(container)
        let view = PreviewText(frame: .zero, textContainer: container)
        view.isEditable = false; view.isSelectable = false
        view.drawsBackground = false
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.setAccessibilityLabel("Text to be read")
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.verticalScroller?.controlSize = .mini
        scroll.borderType = .noBorder
        scroll.documentView = view
        let marker = context.coordinator.marker
        marker.wantsLayer = true
        marker.layer?.backgroundColor = NSColor(Color.altoMarker).cgColor
        marker.isHidden = true
        scroll.contentView.addSubview(marker, positioned: .below, relativeTo: view)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? PreviewText, let storage = view.textStorage else { return }
        let font = NSFont.systemFont(ofSize: 12 * scale)
        view.textContainerInset = NSSize(width: 12 * scale, height: 6 * scale)
        view.trailingInset = 6 * scale
        // A slim overlay scroller, kept clear of the panel's bottom and right edges.
        scroll.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 10 * scale, right: 10 * scale)
        let state = context.coordinator
        state.marker.layer?.cornerRadius = 3 * scale
        if view.string != text || view.font != font {
            storage.setAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
            view.font = font
            state.chunk = NSRange(location: 0, length: 0); state.word = state.chunk; state.scrolledTo = nil
            state.marker.isHidden = true; state.markerShown = false
        }
        let chunk = highlight.map { NSRange($0.chunk, in: text) } ?? NSRange(location: 0, length: 0)
        let word = highlight.map { NSRange($0.word, in: text) } ?? NSRange(location: 0, length: 0)
        guard chunk != state.chunk || word != state.word else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        // Spotlight: the passage being read keeps full contrast, the rest dims.
        storage.addAttribute(.foregroundColor, value: chunk.length > 0 ? NSColor.secondaryLabelColor : NSColor.labelColor, range: full)
        if chunk.length > 0 { storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: chunk) }
        storage.endEditing()
        state.chunk = chunk; state.word = word
        if follow, word.length > 0, state.scrolledTo != word {
            state.scrolledTo = word
            Self.reveal(word, in: view, scroll: scroll)
        }
        Self.moveMarker(to: word, in: view, scroll: scroll, state: state, scale: scale)
    }
    /// Glides the marker from the previous word to the next; the word's dark
    /// text is applied once the marker has arrived, so it never sits unreadable
    /// on the plain background mid-slide.
    static func moveMarker(to word: NSRange, in view: PreviewText, scroll: NSScrollView, state: Coordinator, scale: CGFloat) {
        let marker = state.marker
        guard word.length > 0, let rect = wordRect(word, in: view) else {
            marker.isHidden = true; state.markerShown = false; return
        }
        let target = view.convert(rect, to: scroll.contentView).insetBy(dx: -2 * scale, dy: -1 * scale)
        let settle = {
            guard state.word == word, let storage = view.textStorage else { return }
            storage.addAttribute(.foregroundColor, value: NSColor.black.withAlphaComponent(0.9), range: word)
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !state.markerShown || reduceMotion {
            marker.frame = target; marker.isHidden = false; state.markerShown = true
            settle(); return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            marker.animator().frame = target
        }, completionHandler: settle)
    }
    static func wordRect(_ range: NSRange, in view: NSTextView) -> NSRect? {
        guard let layout = view.layoutManager, let container = view.textContainer else { return nil }
        let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
        rect.origin.x += view.textContainerInset.width
        rect.origin.y += view.textContainerInset.height
        return rect
    }
    /// Scrolls only when the word's line is outside the comfortable band, and
    /// then places it a third of the way down rather than at the very edge.
    static func reveal(_ range: NSRange, in view: NSTextView, scroll: NSScrollView) {
        guard let line = wordRect(range, in: view) else { return }
        let clip = scroll.contentView
        let visible = clip.bounds
        let band = visible.insetBy(dx: 0, dy: min(line.height, visible.height / 4))
        guard line.minY < band.minY || line.maxY > band.maxY else { return }
        let target = max(0, min(line.minY - visible.height / 3, view.frame.height - visible.height))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            clip.animator().setBoundsOrigin(NSPoint(x: visible.minX, y: target))
        }
        scroll.reflectScrolledClipView(clip)
    }
}

private final class PlayerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class PlayerHostingView: NSHostingView<PlayerView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor final class PlayerController: NSObject, NSWindowDelegate {
    private let app: AppModel
    private let panel: NSPanel
    private var host: NSHostingView<PlayerView>
    private var hideTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var cursorAnchor: NSPoint?
    init(app: AppModel) {
        self.app = app
        panel = PlayerPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        host = PlayerHostingView(rootView: PlayerView(app: app, shown: false))
        super.init()
        panel.contentView = host
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in if self?.panel.isVisible == true { self?.show() } }
        }
    }
    func show(keyboard: Bool = false) {
        guard app.hasReading, !app.isTextReaderOpen else { return }
        guard app.playerPosition != .hidden else { hide(); return }
        hideTask?.cancel()
        // Measure a separate hosting view; never force the visible pill's layout
        // during its animation (the Clio overlay's important resize invariant).
        let measuring = NSHostingView(rootView: PlayerView(app: app, shown: true))
        let size = measuring.fittingSize
        if cursorAnchor == nil { cursorAnchor = NSEvent.mouseLocation }
        let mouse = cursorAnchor ?? NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let origin = app.playerPosition.origin(size: size, frame: screen.visibleFrame, cursor: mouse)
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        panel.orderFrontRegardless()
        host.rootView = PlayerView(app: app, shown: true)
        if keyboard { panel.makeKey() }
        if CommandLine.arguments.contains("--diagnose-window") { print("Alto player \(panel.windowNumber)"); fflush(stdout) }
    }
    func hide() {
        cursorAnchor = nil
        host.rootView = PlayerView(app: app, shown: false)
        hideTask?.cancel()
        hideTask = Task { try? await Task.sleep(for: .milliseconds(220)); if !Task.isCancelled { panel.orderOut(nil) } }
    }
}

extension Color {
    static let altoAccent = Color(red: 0.37, green: 0.43, blue: 0.25)
    static let altoMarker = Color(red: 1.0, green: 0.82, blue: 0.2)
}
