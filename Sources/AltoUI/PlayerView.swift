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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var dark: Bool { scheme == .dark }
    private var scale: CGFloat { app.playerSize.rawValue }
    private var tint: Color { dark ? Color(white: 0.03) : Color(red: 0.98, green: 0.98, blue: 0.97) }
    var body: some View {
        VStack(spacing: 10 * scale) {
            if !embedded, !app.readingText.isEmpty {
                ReadingPreview(text: app.readingText, scale: scale)
            }
            pill
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
                        .font(.system(size: 17 * scale, weight: .bold))
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
                Image(systemName: "xmark").font(.system(size: (embedded ? 17 : 10) * scale, weight: .bold))
                    .foregroundStyle(.secondary).frame(width: 28 * scale, height: 28 * scale)
                    .background {
                        if !embedded { Circle().fill(.primary.opacity(0.07)) }
                    }
            }.buttonStyle(.plain).help("Stop and dismiss").accessibilityLabel("Stop and dismiss player")
        }
        .padding(.horizontal, 14 * scale).frame(height: 52 * scale)
        .background {
            if embedded {
                if reduceTransparency {
                    Capsule().fill(Color(white: 0.96))
                } else if #available(macOS 26, *) {
                    // Let native glass sample the text underneath, without the
                    // opaque white tint used by the standalone floating player.
                    Capsule().fill(.clear).glassEffect(.regular, in: Capsule())
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            } else if #available(macOS 26, *), !reduceTransparency {
                Capsule().fill(tint.opacity(0.45))
                    .glassEffect(.regular.tint(dark ? .black.opacity(0.82) : .white.opacity(0.84)), in: Capsule())
            } else {
                Capsule().fill(tint.opacity(reduceTransparency ? 1 : 0.65))
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .overlay {
            if !embedded {
                Capsule().strokeBorder(dark ? .white.opacity(0.24) : .black.opacity(0.42), lineWidth: 0.5)
            }
        }
        .clipShape(Capsule())
        .shadow(color: .black.opacity(dark ? 0.34 : 0.08), radius: 8, x: 0, y: 3)
        .shadow(color: .black.opacity(dark ? 0.24 : 0.08), radius: 2, x: 0, y: 1)
    }
}

struct ReadingPreview: View {
    let text: String
    let scale: CGFloat
    var body: some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            Label("Developer preview · Captured text", systemImage: "text.alignleft")
                .font(.system(size: 10 * scale, weight: .semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(verbatim: text)
                    .font(.system(size: 12 * scale))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Text to be read")
                    .accessibilityValue(text)
            }.frame(height: 120 * scale)
        }
        .padding(12 * scale)
        .frame(width: 320 * scale)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14 * scale))
        .overlay(RoundedRectangle(cornerRadius: 14 * scale).strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
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
        hideTask?.cancel()
        // Measure a separate hosting view; never force the visible pill's layout
        // during its animation (the Clio overlay's important resize invariant).
        let measuring = NSHostingView(rootView: PlayerView(app: app, shown: true))
        let size = measuring.fittingSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!
        var origin = panel.isVisible ? NSPoint(x: panel.frame.midX - size.width / 2, y: panel.frame.minY) : NSPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 28)
        if !panel.isVisible, let saved = UserDefaults.standard.array(forKey: "playerPosition") as? [Double], saved.count == 2 {
            origin = NSPoint(x: saved[0], y: saved[1])
        }
        let display = NSScreen.screens.first { $0.visibleFrame.contains(origin) } ?? screen
        origin.x = min(max(origin.x, display.visibleFrame.minX), display.visibleFrame.maxX - size.width)
        origin.y = min(max(origin.y, display.visibleFrame.minY), display.visibleFrame.maxY - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        panel.orderFrontRegardless()
        host.rootView = PlayerView(app: app, shown: true)
        if keyboard { panel.makeKey() }
        if CommandLine.arguments.contains("--diagnose-window") { print("Alto player \(panel.windowNumber)"); fflush(stdout) }
    }
    func hide() {
        host.rootView = PlayerView(app: app, shown: false)
        hideTask?.cancel()
        hideTask = Task { try? await Task.sleep(for: .milliseconds(220)); if !Task.isCancelled { panel.orderOut(nil) } }
    }
    func windowDidMove(_ notification: Notification) {
        UserDefaults.standard.set([panel.frame.minX, panel.frame.minY], forKey: "playerPosition")
    }
}

extension Color {
    static let altoAccent = Color(red: 0.37, green: 0.43, blue: 0.25)
}
