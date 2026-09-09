import SwiftUI
import AppKit
import ServiceManagement
import AltoCore

struct SettingsView: View {
    @Bindable var app: AppModel
    @State private var recording = false
    @State private var monitor: Any?
    @State private var error: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    var body: some View {
        TabView(selection: $app.settingsTab) {
            Form {
                Section {
                    Toggle("Enable reading shortcut", isOn: Binding(get: { app.shortcutEnabled }, set: { app.setShortcutEnabled($0) }))
                    HStack {
                        Text("Shortcut"); Spacer()
                        Button(recording ? "Press a combination…" : app.shortcutLabel) { record() }.frame(minWidth: 140)
                    }
                }
                Section {
                    Toggle("Launch at login", isOn: $launchAtLogin).onChange(of: launchAtLogin) {
                        do { if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { self.error = error.localizedDescription; launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
                }
                Section {
                    HStack {
                        Label(app.permissionGranted ? "Accessibility enabled" : "Accessibility needed", systemImage: app.permissionGranted ? "checkmark.circle" : "hand.raised")
                        Spacer()
                        Button("Open System Settings") { SelectionReader.requestPermission(); SelectionReader.openPermissionSettings() }
                    }
                    if !app.permissionGranted {
                        Button("Show This Copy of Alto in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                        }
                    }
                } header: {
                    Text("Permissions")
                } footer: {
                    if !app.permissionGranted {
                        Text("Enable Alto in Privacy & Security → Accessibility. If already enabled, remove the old entry and add this copy of Alto, then quit and reopen Alto. You can also copy text yourself and use Read Clipboard in the menu.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if app.selectedModel == nil {
                    Section {
                        Button("Download a Voice Model…") { app.showModels?() }
                    } footer: {
                        Text("Download once to read offline.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                if let message = app.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            }.formStyle(.grouped)
                .tabItem { Label { Text("General") } icon: { SettingsIcon.general } }
                .tag(SettingsTab.general)
            ModelsSettingsView(app: app)
                .tabItem { Label { Text("Models") } icon: { SettingsIcon.model } }
                .tag(SettingsTab.models)
            Form {
                Section {
                    Picker("Voice", selection: Binding(get: { app.voicePath }, set: { app.changeVoice($0) })) {
                        ForEach(app.voices, id: \.path) { voice in Text(ModelDescriptor.voiceName(voice.path)).tag(voice.path) }
                    }.disabled(app.voices.isEmpty)
                    HStack { Text("Speed"); Slider(value: $app.rate, in: 0.5...2, step: 0.1); Text("\(app.rate, specifier: "%.1f")×").monospacedDigit() }
                    Picker("Player size", selection: $app.playerSize) {
                        ForEach(PlayerSize.allCases, id: \.self) { size in
                            Text(size.label).tag(size)
                        }
                    }
                    Button("Manage Models…") { app.showModels?() }
                }
                Section {
                    Toggle("Clipboard fallback", isOn: $app.clipboardFallback)
                } footer: {
                    Text("Uses Copy when needed, then restores your clipboard unless it changed. Clipboard history apps may retain the copy.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Read Text") {
                    Button("Open Read Text…") { app.openTextReader() }
                }
            }.formStyle(.grouped)
                .tabItem { Label { Text("Reading") } icon: { SettingsIcon.reading } }
                .tag(SettingsTab.reading)
            Form {
                Section("Alto") {
                    Text("Local text to speech. No account or saved text history.")
                    Text("English (US/UK) · Kokoro").foregroundStyle(.secondary)
                    Button("Show Model Storage") { NSWorkspace.shared.open(AltoPaths.models) }
                    Button("Third-party notices") {
                        if let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md") { NSWorkspace.shared.open(url) }
                    }
                }
            }.formStyle(.grouped)
                .tabItem { Label { Text("About") } icon: { SettingsIcon.about } }
                .tag(SettingsTab.about)
        }.frame(width: 520, height: 480)
            .onDisappear { stopRecording() }
            .onChange(of: app.settingsTab) { stopRecording() }
    }
    private func stopRecording() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; recording = false }
    private func record() {
        stopRecording(); recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stopRecording(); return nil }
            do { try app.recordShortcut(event); error = nil; stopRecording() }
            catch { self.error = error.localizedDescription }
            return nil
        }
    }
}
