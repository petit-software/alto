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
    private var paragraphs: [(id: Int, range: Range<String.Index>)] {
        var result: [(id: Int, range: Range<String.Index>)] = []
        var start = text.startIndex
        while true {
            let end = text[start...].firstIndex(of: "\n") ?? text.endIndex
            result.append((result.count, start..<end))
            if end == text.endIndex { break }
            start = text.index(after: end)
        }
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            HStack {
                Label("Developer preview · Captured text", systemImage: "text.alignleft")
                    .font(.system(size: 10 * scale, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Toggle("Follow reading", isOn: follow)
                    .toggleStyle(.switch).controlSize(.mini)
                    .font(.system(size: 10 * scale)).foregroundStyle(.secondary)
                    .help("Highlight the passage and word being read")
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(paragraphs, id: \.id) { paragraph in
                            Text(attributed(paragraph.range))
                                .font(.system(size: 12 * scale))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .id(paragraph.id)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Text to be read")
                    .accessibilityValue(text)
                }.frame(height: 120 * scale)
                    .onChange(of: highlight?.word.lowerBound) { _, position in
                        guard follow.wrappedValue, let position,
                              let paragraph = paragraphs.first(where: { $0.range.contains(position) || $0.range.upperBound == position }) else { return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(paragraph.id, anchor: .center) }
                    }
            }
        }
        .padding(12 * scale)
        .frame(width: 320 * scale)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14 * scale))
        .overlay(RoundedRectangle(cornerRadius: 14 * scale).strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }
    private func attributed(_ range: Range<String.Index>) -> AttributedString {
        var attributed = AttributedString(text[range])
        guard let highlight else { return attributed }
        func apply(_ target: Range<String.Index>, _ color: Color) {
            let lower = max(target.lowerBound, range.lowerBound), upper = min(target.upperBound, range.upperBound)
            guard lower < upper else { return }
            let start = attributed.index(attributed.startIndex, offsetByCharacters: text.distance(from: range.lowerBound, to: lower))
            let end = attributed.index(attributed.startIndex, offsetByCharacters: text.distance(from: range.lowerBound, to: upper))
            attributed[start..<end].backgroundColor = color
        }
        apply(highlight.chunk, Color.altoAccent.opacity(0.14))
        apply(highlight.word, Color.altoAccent.opacity(0.5))
        return attributed
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
}
