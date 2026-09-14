import AppKit
import SwiftUI
import AltoCore
import Darwin

public struct AltoSettingsRoot: View {
    @ObservedObject private var delegate: AppDelegate
    public init(delegate: AppDelegate) { self.delegate = delegate }
    public var body: some View { delegate.settingsContent }
}

@MainActor public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, ObservableObject {
    @Published private var app: AppModel!
    private var player: PlayerController!
    private var textReader: TextReaderController!
    private var services: ServiceProvider!
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?
    @ViewBuilder public var settingsContent: some View {
        if let app { SettingsView(app: app) }
    }
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        signal(SIGPIPE, SIG_IGN) // A crashed worker must produce an error, not kill the UI on its next pipe write.
        if let index = CommandLine.arguments.firstIndex(of: "--audio-regression"), CommandLine.arguments.count > index + 1 {
            let root = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            Task {
                do { try await AudioRegressionCheck.run(at: root); exit(0) }
                catch { fputs("Audio regression failed: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--integration-test"), CommandLine.arguments.count > index + 1 {
            let root = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            Task {
                do {
                    try await IntegrationCheck.run(at: root, offline: CommandLine.arguments.contains("--offline"),
                        audiblePlayback: CommandLine.arguments.contains("--audible-playback"))
                    exit(0)
                } catch { fputs("Integration failed: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            return
        }
        app = AppModel()
        player = PlayerController(app: app)
        textReader = TextReaderController(app: app)
        app.presentTextReader = { [weak self] in self?.textReader.show() }
        app.closeTextReader = { [weak self] in self?.textReader.hide() }
        app.showWindow = { [weak self] in self?.app.settingsTab = .general; self?.showSettings() }
        app.showModels = { [weak self] in self?.showModels() }
        app.showSettings = { [weak self] in self?.showSettings() }
        app.showPlayer = { [weak self] in self?.player.show() }
        app.hidePlayer = { [weak self] in self?.player.hide() }
        services = ServiceProvider { [weak self] pasteboard in self?.app.readService(pasteboard) }
        NSApp.servicesProvider = services
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = StatusIcon.image()
        statusItem.button?.toolTip = "Alto · \(app.shortcutLabel)"
        let menu = NSMenu(); menu.delegate = self; menu.autoenablesItems = false; statusItem.menu = menu
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.app.permissionGranted = SelectionReader.hasPermission }
        }
        if CommandLine.arguments.contains("--show-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.showSettings() }
        }
        else if CommandLine.arguments.contains("--show-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.statusItem.button?.performClick(nil) }
        }
        else if CommandLine.arguments.contains("--show-player") { player.show() }
        else if CommandLine.arguments.contains("--show-models") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.showModels() }
        }
        else if CommandLine.arguments.contains("--show-reading") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.showReading() }
        }
        else if !UserDefaults.standard.bool(forKey: "hasOpened") || app.selectedModel == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.finishSetup() }
        }
        UserDefaults.standard.set(true, forKey: "hasOpened")
    }
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        statusItem.button?.toolTip = "Alto · \(app.shortcutLabel)"
        let header = NSHostingView(rootView: ShortcutMenuRow(app: app))
        header.frame.size = header.fittingSize
        header.autoresizingMask = [.width]
        let title = NSMenuItem(); title.view = header; menu.addItem(title)
        if !app.permissionGranted || app.selectedModel == nil {
            menu.addItem(.separator())
            add("Finish Setup…", action: #selector(finishSetup), to: menu)
        }
        menu.addItem(.separator())
        add(app.isActive ? "Stop Reading" : "Read Selected Text", action: app.isActive ? #selector(stop) : #selector(readSelection), to: menu)
        add("Read Clipboard", action: #selector(readClipboard), to: menu)
        add("Read Text…", action: #selector(showReading), to: menu)
        if app.isActive {
            add(app.isPaused ? "Resume" : "Pause", action: #selector(togglePause), to: menu)
        }
        if app.hasReading { add("Show Player", action: #selector(showPlayer), to: menu) }
        menu.addItem(.separator())
        let voices = NSMenu(title: "Voice"); voices.autoenablesItems = false
        for voice in app.voices {
            let item = NSMenuItem(title: ModelDescriptor.voiceName(voice.path), action: #selector(selectVoice(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = voice.path
            item.state = voice.path == app.voicePath ? .on : .off
            voices.addItem(item)
        }
        let voiceItem = NSMenuItem(title: "Voice", action: nil, keyEquivalent: "")
        voiceItem.submenu = voices; voiceItem.isEnabled = !app.voices.isEmpty; menu.addItem(voiceItem)
        add("Models…", action: #selector(showModels), to: menu)
        menu.addItem(.separator())
        add("Settings…", action: #selector(showSettings), to: menu)
        add("Quit Alto", action: #selector(quit), key: "q", to: menu)
        menu.addItem(.separator())
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unbundled build"
        let build = (info?["CFBundleVersion"] as? String).map { " (\($0))" } ?? ""
        let footer = NSMenuItem(title: "Alto \(version)\(build)", action: nil, keyEquivalent: "")
        footer.isEnabled = false; menu.addItem(footer)
    }
    private func add(_ title: String, action: Selector, key: String = "", to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item)
    }
    @objc private func selectVoice(_ sender: NSMenuItem) {
        if let path = sender.representedObject as? String { app.changeVoice(path) }
    }
    @objc private func readSelection() { app.readSelection() }
    @objc private func readClipboard() { app.readClipboard() }
    @objc private func togglePause() { app.togglePause() }
    @objc private func stop() { app.stopAndDismiss() }
    @objc private func showPlayer() {
        if app.isTextReaderOpen { textReader.show() } else { player.show(keyboard: true) }
    }
    @objc private func showModels() { app.settingsTab = .models; showSettings() }
    @objc private func showReading() { app.openTextReader() }
    @objc private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        let item = NSApp.mainMenu?.items.first?.submenu?.items.first { $0.keyEquivalent == "," }
        if let item, let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
        if CommandLine.arguments.contains("--diagnose-window") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                for window in NSApp.windows where window.isVisible {
                    print("Alto window \(window.windowNumber): \(window.title)"); fflush(stdout)
                }
            }
        }
    }
    @objc private func finishSetup() { app.settingsTab = app.setupTab; showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard app?.hasPendingCapture == true else { return .terminateNow }
        Task { await app.finishCaptureBeforeQuitting(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    public func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate(); app?.shutdown()
    }
}

// Adapted from Clio's native menu header and mini switch.
private struct ShortcutMenuRow: View {
    @Bindable var app: AppModel
    var body: some View {
        HStack(spacing: 0) {
            Text("Alto")
            Text("   \(app.shortcutLabel)").foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Toggle("Enable reading shortcut", isOn: Binding(get: { app.shortcutEnabled }, set: { app.setShortcutEnabled($0) }))
                .toggleStyle(ShortcutMenuSwitchStyle())
        }.padding(.horizontal, 14).padding(.vertical, 3)
    }
}

private struct ShortcutMenuSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule().fill(configuration.isOn ? Color.accentColor : Color.primary.opacity(0.15))
                .frame(width: 36, height: 16)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(.white).frame(width: 21, height: 13)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5).padding(1.5)
                }
        }.buttonStyle(.plain).animation(.easeInOut(duration: 0.15), value: configuration.isOn)
            .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}
