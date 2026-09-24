import Foundation
import Observation

/// One transfer at a time. URLSession owns temporary download files; the delegate
/// moves the completed file before returning and persists resumable state on errors.
private final class FileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let destination: URL
    let resumeURL: URL
    let progress: @Sendable (Int64) -> Void
    var continuation: CheckedContinuation<Void, Error>?
    var session: URLSession!
    var task: URLSessionDownloadTask?
    let lock = NSLock()
    var cancelled = false
    init(destination: URL, progress: @escaping @Sendable (Int64) -> Void) {
        self.destination = destination
        self.resumeURL = destination.appendingPathExtension("resume")
        self.progress = progress
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    func run(_ url: URL) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                if let resume = try? Data(contentsOf: resumeURL) {
                    task = session.downloadTask(withResumeData: resume)
                } else { task = session.downloadTask(with: url) }
                let wasCancelled = cancelled
                task?.resume()
                lock.unlock()
                if wasCancelled { cancel() }
            }
        } onCancel: { self.cancel() }
    }
    func cancel() {
        lock.lock(); cancelled = true; let current = task; lock.unlock()
        current?.cancel(byProducingResumeData: { data in
            if let data { try? data.write(to: self.resumeURL, options: .atomic) }
        })
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200 || response.statusCode == 206 else {
                throw AltoError("The model server could not provide this file. Check the repository and retry.")
            }
            try FileManager.default.moveItem(at: location, to: destination)
            try? FileManager.default.removeItem(at: resumeURL)
        } catch { finish(.failure(error)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            if let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                try? data.write(to: resumeURL, options: .atomic)
            }
            finish(.failure(error))
        } else { finish(.success(())) }
    }
    func finish(_ result: Result<Void, Error>) {
        lock.lock(); let pending = continuation; continuation = nil; lock.unlock()
        pending?.resume(with: result)
        session.finishTasksAndInvalidate()
    }
}

@MainActor @Observable
public final class ModelStore {
    public private(set) var catalog: [ModelDescriptor] = []
    public private(set) var installed: [ModelDescriptor] = []
    public private(set) var progress: [String: Double] = [:]
    public private(set) var status: [String: String] = [:]
    public var importing = false
    private var transfers: [String: Task<Void, Never>] = [:]
    private let root: URL
    private let schema: [String: [Int]]
    public init(root: URL = AltoPaths.models, resources: Bundle = .main) {
        self.root = root
        catalog = (try? resources.url(forResource: "catalog", withExtension: "json").map { try JSONDecoder().decode([ModelDescriptor].self, from: Data(contentsOf: $0)) }) ?? []
        schema = (try? resources.url(forResource: "kokoro-schema", withExtension: "json").map { try JSONDecoder().decode([String: [Int]].self, from: Data(contentsOf: $0)) }) ?? [:]
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: root.appendingPathComponent(".catalog.json")),
           let imported = try? JSONDecoder().decode([ModelDescriptor].self, from: data) {
            catalog += imported.filter { entry in !catalog.contains { $0.id == entry.id } }
        }
        reload()
    }
    public var all: [ModelDescriptor] { catalog + installed.filter { model in !catalog.contains { $0.id == model.id } } }
    public func folder(_ model: ModelDescriptor) -> URL { root.appendingPathComponent(model.id) }
    public func isInstalled(_ model: ModelDescriptor) -> Bool { installed.contains { $0.id == model.id } }
    public func installedSize(_ model: ModelDescriptor) -> String {
        let bytes = model.files.reduce(Int64(0)) { total, file in
            total + Int64((try? folder(model).appendingPathComponent(file.path).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    public func reload() {
        installed = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []).compactMap { url in
            guard !url.lastPathComponent.hasPrefix("."), let data = try? Data(contentsOf: url.appendingPathComponent("alto-model.json")),
                  let model = try? JSONDecoder().decode(ModelDescriptor.self, from: data), model.id == url.lastPathComponent,
                  ModelValidation.supportedFamilies.contains(model.family) else { return nil }
            return model
        }.sorted { $0.name < $1.name }
    }
    public func download(_ model: ModelDescriptor) {
        guard transfers[model.id] == nil, !isInstalled(model) else { return }
        progress[model.id] = 0
        transfers[model.id] = Task {
            defer { transfers[model.id] = nil; progress[model.id] = nil }
            do {
                try await install(model)
                status[model.id] = "Ready offline"
            } catch {
                status[model.id] = Task.isCancelled ? "Paused · Resume download" : error.localizedDescription
            }
        }
    }
    public func cancel(_ model: ModelDescriptor) { transfers[model.id]?.cancel() }
    public func cancelAll() { transfers.values.forEach { $0.cancel() } }
    private func install(_ model: ModelDescriptor) async throws {
        if model.isChatterboxNano {
            try ModelValidation.validateNanoManifest(model)
        } else {
            guard model.family == ModelValidation.supportedFamily, model.weight != nil, !model.voices.isEmpty,
                  !schema.isEmpty else { throw AltoError("This model needs a runtime or resources Alto does not include.") }
        }
        let staging = root.appendingPathComponent(".staging-" + model.id)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let values = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let free = values.volumeAvailableCapacityForImportantUsage, free < model.downloadBytes + 400_000_000 {
            throw AltoError("Not enough disk space. Free at least \(model.sizeLabel) plus 400 MB for model preparation.")
        }
        var completed: Int64 = 0
        for file in model.files {
            try Task.checkCancellation()
            let destination = try ModelValidation.containedURL(file.path, in: staging)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                do { try await Task.detached { try ModelValidation.verify(file, in: staging) }.value }
                catch { try FileManager.default.removeItem(at: destination) }
            }
            if !FileManager.default.fileExists(atPath: destination.path) {
                guard let url = file.url, url.scheme == "https" else { throw AltoError("This model has no secure download URL.") }
                status[model.id] = "Downloading \(URL(fileURLWithPath: file.path).lastPathComponent)"
                let base = completed
                let download = FileDownload(destination: destination) { bytes in
                    Task { @MainActor [weak self] in
                        self?.progress[model.id] = min(1, Double(base + bytes) / Double(max(1, model.downloadBytes)))
                    }
                }
                try await download.run(url)
            }
            try await Task.detached { try ModelValidation.verify(file, in: staging) }.value
            completed += file.bytes
            progress[model.id] = Double(completed) / Double(max(1, model.downloadBytes))
        }
        status[model.id] = "Checking compatibility…"
        try await validate(model, in: staging)
        try Task.checkCancellation()
        if model.license == "apache-2.0", let license = Bundle.main.url(forResource: "Apache-2.0", withExtension: "txt", subdirectory: "Notices") {
            let target = staging.appendingPathComponent("LICENSE-Apache-2.0.txt")
            if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.copyItem(at: license, to: target) }
        }
        try JSONEncoder().encode(model).write(to: staging.appendingPathComponent("alto-model.json"), options: .atomic)
        try FileManager.default.moveItem(at: staging, to: folder(model))
        reload()
    }
    private func validate(_ model: ModelDescriptor, in folder: URL) async throws {
        let schema = self.schema
        try await Task.detached {
            if model.isChatterboxNano {
                try ModelValidation.validateNanoManifest(model)
                for file in model.files { try ModelValidation.verify(file, in: folder) }
                return
            }
            guard let weight = model.weight, !schema.isEmpty else { throw AltoError("Missing Kokoro weights or runtime schema.") }
            try ModelValidation.validateKokoro(try ModelValidation.containedURL(weight.path, in: folder), schema: schema)
            for voice in model.voices {
                let url = try ModelValidation.containedURL(voice.path, in: folder)
                guard url.pathExtension == "safetensors" else { throw AltoError("Voice files must be safetensors embeddings in this version.") }
                let tensors = try ModelValidation.tensors(url)
                guard tensors.count == 1, tensors.values.first?["shape"] as? [Int] == [510, 1, 256] else {
                    throw AltoError("Invalid voice embedding: \(voice.path).")
                }
            }
        }.value
    }
    public func delete(_ model: ModelDescriptor) throws {
        guard isInstalled(model), transfers[model.id] == nil else { return }
        let target = try ModelValidation.containedURL(model.id, in: root)
        try FileManager.default.trashItem(at: target, resultingItemURL: nil)
        status[model.id] = nil
        reload()
    }
    public func importLocal(_ selection: URL) async throws {
        let scope = selection.startAccessingSecurityScopedResource()
        defer { if scope { selection.stopAccessingSecurityScopedResource() } }
        importing = true
        defer { importing = false }
        let isDirectory = (try? selection.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let source = isDirectory ? selection : selection.deletingLastPathComponent()
        let listed = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: [.fileSizeKey])
        let weights = isDirectory ? listed.filter { $0.pathExtension == "safetensors" } : [selection]
        guard weights.count == 1, weights[0].pathExtension == "safetensors" else {
            throw AltoError("Choose one Kokoro safetensors weight file with a voices folder beside it. For Chatterbox Nano, use Alto's model catalog. Other formats cannot be imported.")
        }
        let voicesFolder = source.appendingPathComponent("voices")
        let voices = ((try? FileManager.default.contentsOfDirectory(at: voicesFolder, includingPropertiesForKeys: nil)) ?? []).filter {
            $0.pathExtension == "safetensors" && ["af_", "am_", "bf_", "bm_"].contains(where: $0.lastPathComponent.hasPrefix)
        }
        guard !voices.isEmpty else { throw AltoError("Missing voices. Add a voices folder with English Kokoro .safetensors embeddings beside the weights.") }
        let assets = [weights[0]] + voices + listed.filter { ["README.md", "LICENSE", "config.json"].contains($0.lastPathComponent) }
        let files = try assets.map { url -> ModelFile in
            let path = url.deletingLastPathComponent() == voicesFolder ? "voices/" + url.lastPathComponent : url.lastPathComponent
            _ = try ModelValidation.containedURL(path, in: source)
            let size = Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            guard size > 0, size < 600_000_000 else { throw AltoError("Unsupported file size: \(path).") }
            return ModelFile(path: path, bytes: size)
        }
        let model = ModelDescriptor(id: UUID().uuidString, name: weights[0].deletingPathExtension().lastPathComponent,
            summary: "Imported from your Mac", family: "kokoro-v1", repository: "Local files", revision: "local",
            license: "License not provided · see original source", languages: ["English (US)", "English (UK)"], files: files)
        try await validate(model, in: source)
        let destination = folder(model)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            for file in files {
                let target = try ModelValidation.containedURL(file.path, in: destination)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: ModelValidation.containedURL(file.path, in: source), to: target)
            }
            try JSONEncoder().encode(model).write(to: destination.appendingPathComponent("alto-model.json"), options: .atomic)
            reload()
        } catch { try? FileManager.default.removeItem(at: destination); throw error }
    }
    public func inspectHub(_ input: String, revision: String = "main") async throws -> ModelDescriptor {
        var repo = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if repo.hasPrefix("https://huggingface.co/") { repo = String(repo.dropFirst("https://huggingface.co/".count)) }
        let parts = repo.split(separator: "/")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }),
              !revision.isEmpty, revision.unicodeScalars.allSatisfy(allowed.contains) else {
            throw AltoError("Enter a public Hugging Face owner/repository and a branch, tag, or commit revision.")
        }
        let url = URL(string: "https://huggingface.co/api/models/\(repo)/revision/\(revision)?blobs=true")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let commit = object["sha"] as? String, let siblings = object["siblings"] as? [[String: Any]] else {
            throw AltoError("Could not inspect this public repository. Check its name, revision, and your connection. Gated models are not supported.")
        }
        let weightFiles = siblings.filter { item in
            let name = item["rfilename"] as? String ?? ""
            return !name.contains("/") && name.hasSuffix(".safetensors")
        }
        guard weightFiles.count == 1 else { throw AltoError("Expected one Kokoro safetensors weight file. For Chatterbox Nano, use Alto's model catalog. Other formats cannot be imported.") }
        let selected = siblings.filter { item in
            let path = item["rfilename"] as? String ?? ""
            return path == weightFiles[0]["rfilename"] as? String || ["config.json", "README.md", "LICENSE", "LICENSE.txt"].contains(path)
                || (["voices/af_", "voices/am_", "voices/bf_", "voices/bm_"].contains(where: path.hasPrefix) && path.hasSuffix(".safetensors"))
        }
        let files = try selected.map { item -> ModelFile in
            guard let path = item["rfilename"] as? String, let bytes = item["size"] as? Int64, bytes > 0, bytes < 600_000_000 else {
                throw AltoError("Missing file sizes or an unsupported large file.")
            }
            _ = try ModelValidation.containedURL(path, in: root)
            return ModelFile(path: path, bytes: bytes, sha256: (item["lfs"] as? [String: Any])?["sha256"] as? String,
                             url: URL(string: "https://huggingface.co/\(repo)/resolve/\(commit)/\(path)"))
        }
        guard files.contains(where: { $0.path.hasPrefix("voices/") }) else { throw AltoError("This repository lacks English Kokoro safetensors voice embeddings. Import a complete folder instead.") }
        let card = object["cardData"] as? [String: Any]
        return ModelDescriptor(id: repo.replacingOccurrences(of: "/", with: "--") + "-" + String(commit.prefix(8)),
            name: String(parts[1]), summary: "Imported from Hugging Face · tensor compatibility checked after download",
            family: "kokoro-v1", repository: repo, revision: commit, license: card?["license"] as? String ?? "License not provided",
            languages: ["English (US)", "English (UK)"], files: files)
    }
    public func addToCatalog(_ model: ModelDescriptor) {
        if !all.contains(where: { $0.id == model.id }) { catalog.append(model) }
        try? JSONEncoder().encode(catalog).write(to: root.appendingPathComponent(".catalog.json"), options: .atomic)
        download(model)
    }
}
