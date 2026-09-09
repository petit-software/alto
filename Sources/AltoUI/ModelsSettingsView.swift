import SwiftUI
import AppKit
import AltoCore

struct ModelsSettingsView: View {
    @Bindable var app: AppModel
    @State private var query = ""
    @State private var installedOnly = false
    @State private var deletion: ModelDescriptor?
    @State private var showImport = false
    @State private var issue: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Models").font(.headline)
                Spacer()
                Menu {
                    Button("From your Mac…") { importLocal() }
                    Button("From Hugging Face…") { showImport = true }
                } label: { Label("Import", systemImage: "plus") }.fixedSize()
            }
            HStack {
                Picker("Show", selection: $installedOnly) { Text("All models").tag(false); Text("Installed").tag(true) }
                    .pickerStyle(.segmented).frame(width: 210)
                Spacer()
                TextField("Search models", text: $query).textFieldStyle(.roundedBorder).frame(width: 180)
            }
            Form {
                Section {
                    ForEach(app.models.all.filter { (!installedOnly || app.models.isInstalled($0)) && (query.isEmpty || ($0.name + $0.languages.joined()).localizedCaseInsensitiveContains(query)) }) { model in
                        ModelSettingsRow(app: app, model: model, delete: { deletion = model })
                    }
                    if installedOnly && app.models.installed.isEmpty {
                        ContentUnavailableView("No models yet", systemImage: "arrow.down.circle", description: Text("Choose All models to download your first voice."))
                    }
                }
            }.formStyle(.grouped)
            if app.models.importing { ProgressView("Checking and importing model…").controlSize(.small) }
            if let issue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            Text("Compatible Kokoro v1 safetensors only. Other families require an additional runtime. English (US/UK) is available in this version.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16)
            .sheet(isPresented: $showImport) { HubImportView(store: app.models) }
            .confirmationDialog("Move \(deletion?.name ?? "model") to Trash?", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
                Button("Move to Trash", role: .destructive) { if let deletion { app.deleteModel(deletion) }; deletion = nil }
            } message: { Text("Reclaims approximately \(deletion?.sizeLabel ?? ""). Active reading stops. Imported originals are preserved, and the installed files can be recovered from Trash.") }
    }
    private func importLocal() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.message = "Choose a Kokoro folder, or its safetensors weight file with a voices folder beside it."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in do { try await app.models.importLocal(url) } catch { issue = error.localizedDescription } }
        }
    }
}

private struct ModelSettingsRow: View {
    @Bindable var app: AppModel
    let model: ModelDescriptor
    let delete: () -> Void
    @State private var expanded = false
    private var installed: Bool { app.models.isInstalled(model) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: model.id == "kokoro-compact" ? "leaf" : "cube")
                    .font(.system(size: 18)).foregroundStyle(.secondary).frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(model.name).font(.headline)
                        if model.id == app.preferredID && installed { Text("SELECTED").font(.system(size: 8, weight: .bold)).tracking(1).foregroundStyle(Color.altoAccent) }
                        else if model.id == "kokoro-standard" { Text("RECOMMENDED").font(.system(size: 8, weight: .bold)).tracking(1).foregroundStyle(.secondary) }
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 14) {
                Label(model.sizeLabel, systemImage: "arrow.down").font(.caption)
                Text("English · \(model.voices.count) voices").font(.caption)
                Spacer()
                if let progress = app.models.progress[model.id] {
                    Button("Pause") { app.models.cancel(model) }.controlSize(.small)
                    Text(progress, format: .percent.precision(.fractionLength(0))).font(.caption).monospacedDigit()
                } else if installed {
                    Button(model.id == app.preferredID ? "Selected" : "Use model") { app.selectModel(model) }
                        .disabled(model.id == app.preferredID).controlSize(.small)
                    Button(action: delete) { Image(systemName: "trash") }.buttonStyle(.plain).help("Move model to Trash")
                } else {
                    Button(app.models.status[model.id] == nil ? "Download" : "Resume / retry") { app.models.download(model) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
            }.foregroundStyle(.secondary)
            if let progress = app.models.progress[model.id] { ProgressView(value: progress).tint(.altoAccent) }
            if let status = app.models.status[model.id] { Text(status).font(.caption2).foregroundStyle(.secondary).lineLimit(3) }
            DisclosureGroup("Model details", isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Apple Silicon M1+ · macOS 15+ · 8 GB RAM recommended (estimate)")
                    if model.id == "kokoro-standard" { Text("Measured worker peak: ~497 MB on M5 Max, short sample; longer passages may use more.") }
                    if model.id == "kokoro-compact" { Text("Measured worker peak: ~670 MB on M5 Max, including preparation; longer passages may use more.") }
                    if installed { Text("Installed assets: \(app.models.installedSize(model))") }
                    Text("Languages: \(model.languages.joined(separator: ", "))")
                    Text("License: \(model.license)")
                    Text("Source: \(model.repository)").textSelection(.enabled)
                    Text("Revision: \(model.revision)").textSelection(.enabled)
                    if model.id == "kokoro-compact" { Text("Smaller download; expands to full precision for inference. Allow 400 MB of temporary space. Runtime memory is similar to Kokoro.") }
                    if model.repository != "Local files", let url = URL(string: "https://huggingface.co/\(model.repository)") {
                        Link("View model card and license ↗", destination: url)
                    }
                    if installed { Button("Show installed files") { NSWorkspace.shared.open(app.models.folder(model)) } }
                }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            }.font(.caption)
        }.padding(.vertical, 8)
    }
}

private struct HubImportView: View {
    let store: ModelStore
    @Environment(\.dismiss) private var dismiss
    @State private var repo = ""
    @State private var revision = "main"
    @State private var model: ModelDescriptor?
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Bring your own model").font(.title2.bold())
            Text("Inspect a public Hugging Face repository. Alto supports Kokoro v1 weights with English safetensors voices. Compatibility is verified before installation.").font(.callout).foregroundStyle(.secondary)
            TextField("owner/repository or Hugging Face URL", text: $repo).textFieldStyle(.roundedBorder)
            TextField("Revision", text: $revision).textFieldStyle(.roundedBorder)
            if let model {
                Text("\(model.name) · \(model.sizeLabel) · \(model.voices.count) voices").font(.headline)
                Text("License: \(model.license)\nCommit: \(model.revision)").font(.caption).textSelection(.enabled)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                if let model {
                    Button("Download model") { store.addToCatalog(model); dismiss() }.buttonStyle(.borderedProminent)
                } else {
                    Button("Inspect repository") {
                        busy = true; error = nil
                        Task { do { model = try await store.inspectHub(repo, revision: revision) } catch { self.error = error.localizedDescription }; busy = false }
                    }.buttonStyle(.borderedProminent).disabled(busy || repo.isEmpty)
                }
            }
        }.padding(28).frame(width: 480)
            .onChange(of: repo) { model = nil }.onChange(of: revision) { model = nil }
    }
}
