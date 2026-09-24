import SwiftUI
import AppKit
import AltoCore

/// Laid out like Clio's Model tab: a grouped form, one row per model with a
/// radio to make it active and a single glyph control, then import and
/// on-disk sections. Selection and download state live in the row itself.
struct ModelsSettingsView: View {
    @Bindable var app: AppModel
    @State private var deletion: ModelDescriptor?
    @State private var showImport = false
    @State private var importError: String?
    var body: some View {
        Form {
            Section {
                ForEach(app.models.all) { model in
                    ModelRow(app: app, model: model, delete: { deletion = model })
                }
            } header: {
                Text("Models")
            } footer: {
                Text("Models are downloaded once and run entirely on this Mac. "
                     + "Select an installed model to read with it. Reading briefly uses "
                     + "a few gigabytes of memory, released between passages.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if app.models.installed.isEmpty {
                Section {
                    Label("Download a model to start reading.", systemImage: "arrow.down.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let model = app.selectedModel {
                Section {
                    LabeledContent("License", value: model.license)
                    LabeledContent("Source") {
                        if model.repository != "Local files", let url = URL(string: "https://huggingface.co/\(model.repository)") {
                            Link(model.repository, destination: url)
                        } else {
                            Text(model.repository).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Revision") {
                        Text(model.revision.prefix(12)).font(.caption).textSelection(.enabled)
                    }
                    Button("Show Installed Files") { NSWorkspace.shared.open(app.models.folder(model)) }
                } header: {
                    Text(model.name)
                }
            }

            Section {
                Button("Import from Your Mac…") { importLocal() }
                Button("Import from Hugging Face…") { showImport = true }
                if app.models.importing {
                    ProgressView("Checking and importing model…").controlSize(.small)
                }
                if let importError {
                    Label(importError, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Import")
            } footer: {
                Text("Kokoro v1 safetensors weights with a voices folder beside them. "
                     + "Compatibility is checked before installation. Chatterbox Nano "
                     + "is available from the catalog above with one built-in English voice.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Folder") {
                    Text(AltoPaths.models.path)
                        .font(.caption)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Button("Reveal in Finder") {
                    try? FileManager.default.createDirectory(at: AltoPaths.models, withIntermediateDirectories: true)
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: AltoPaths.models.path)
                }
            } header: {
                Text("On disk")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showImport) { HubImportView(store: app.models) }
        .confirmationDialog("Move \(deletion?.name ?? "model") to Trash?",
                            isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let deletion { app.deleteModel(deletion) }
                deletion = nil
            }
        } message: {
            Text("Reclaims approximately \(deletion?.sizeLabel ?? ""). Active reading stops. "
                 + "Imported originals are preserved, and the installed files can be recovered from Trash.")
        }
    }

    private func importLocal() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Kokoro folder, or its safetensors weight file with a voices folder beside it."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do { try await app.models.importLocal(url); importError = nil }
                catch { importError = error.localizedDescription }
            }
        }
    }
}

private struct ModelRow: View {
    @Bindable var app: AppModel
    let model: ModelDescriptor
    let delete: () -> Void

    private var installed: Bool { app.models.isInstalled(model) }
    private var isActive: Bool { installed && model.id == app.preferredID }
    private var progress: Double? { app.models.progress[model.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                // The active model is chosen by selecting an installed row,
                // rather than a separate picker that can point at nothing.
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    .onTapGesture { if installed && !isActive { app.selectModel(model) } }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(isActive ? "\(model.name) is selected" : "Use \(model.name)")

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name).font(.body)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                controls
            }

            if let progress {
                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: progress).tint(.accentColor)
                    Text(progressLabel(progress))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !installed, let status = app.models.status[model.id] {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(status.hasPrefix("Paused") ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
            }
        }
        .padding(.vertical, 2)
    }

    /// Symbols rather than words: each row already carries a name, a size
    /// and a description. `help` keeps the meaning available on hover and
    /// to VoiceOver.
    @ViewBuilder
    private var controls: some View {
        if progress != nil {
            iconButton("xmark.circle.fill", "Pause the download", .secondary) {
                app.models.cancel(model)
            }
        } else if installed {
            iconButton("minus.circle.fill", "Move \(model.name) to Trash", .secondary, action: delete)
        } else {
            let resuming = app.models.status[model.id] != nil
            iconButton("arrow.down.circle.fill", resuming ? "Resume downloading \(model.name)" : "Download \(model.name)", .accentColor) {
                app.models.download(model)
            }
        }
    }

    private func iconButton(_ symbol: String, _ description: String, _ tint: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(tint)
        }
        .buttonStyle(.borderless)
        .help(description)
        .accessibilityLabel(description)
    }

    private var subtitle: String {
        var parts = [model.familyLabel, languages, model.voices.count == 1 ? "1 voice" : "\(model.voices.count) voices"]
        parts.append(installed ? "\(app.models.installedSize(model)) on disk" : "\(model.sizeLabel) download")
        if let note { parts.append(note) }
        return parts.joined(separator: " · ")
    }

    private var languages: String {
        if model.languages == ["English"] { return "English" }
        let names = model.languages.map { $0.replacingOccurrences(of: "English (", with: "").replacingOccurrences(of: ")", with: "") }
        return model.languages.allSatisfy({ $0.hasPrefix("English") }) ? "English (\(names.joined(separator: "/")))" : model.languages.joined(separator: ", ")
    }

    private var note: String? {
        switch model.id {
        case "chatterbox-nano": return "Beta"
        case "kokoro-standard": return "Recommended"
        case "kokoro-compact": return "Smaller download, prepared locally"
        default: return model.repository == "Local files" ? "Imported from your Mac" : "Imported"
        }
    }

    private func progressLabel(_ progress: Double) -> String {
        let received = ByteCountFormatter.string(fromByteCount: Int64(progress * Double(model.downloadBytes)), countStyle: .file)
        var label = "\(received) of \(model.sizeLabel)"
        if let status = app.models.status[model.id] { label += " · " + status }
        return label
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
            Text("Import from Hugging Face").font(.title2.weight(.semibold))
            Text("Inspect a public repository. Alto supports Kokoro v1 weights with English safetensors voices. Compatibility is verified before installation.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("owner/repository or Hugging Face URL", text: $repo).textFieldStyle(.roundedBorder)
            TextField("Revision", text: $revision).textFieldStyle(.roundedBorder)
            if let model {
                Text("\(model.name) · \(model.sizeLabel) · \(model.voices.count) voices").font(.headline)
                Text("License: \(model.license)\nCommit: \(model.revision)").font(.caption).textSelection(.enabled)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                if let model {
                    Button("Download Model") { store.addToCatalog(model); dismiss() }.buttonStyle(.borderedProminent)
                } else {
                    Button("Inspect Repository") {
                        busy = true; error = nil
                        Task { do { model = try await store.inspectHub(repo, revision: revision) } catch { self.error = error.localizedDescription }; busy = false }
                    }.buttonStyle(.borderedProminent).disabled(busy || repo.isEmpty)
                }
            }
        }.padding(28).frame(width: 480)
            .onChange(of: repo) { model = nil }.onChange(of: revision) { model = nil }
    }
}
