import AppKit
import Observation
import NaturalLanguage
import AVFoundation
import AltoCore

enum GenerationState { case idle, capturing, loading, generating, finished }
enum PlaybackState { case stopped, playing, paused }
enum SettingsTab: Hashable, CaseIterable { case general, models, reading, about }
enum PlayerSize: Double, CaseIterable {
    case standard = 1, large = 1.25, extraLarge = 1.5
    var label: String {
        switch self { case .standard: return "Default"; case .large: return "1.25×"; case .extraLarge: return "1.5×" }
    }
}

@MainActor @Observable
final class AppModel {
    var settingsTab: SettingsTab = .general
    var setupTab: SettingsTab { !permissionGranted || selectedModel != nil ? .general : .models }
    let models: ModelStore
    let hotkey = GlobalHotkey()
    let speech: any SpeechEngine
    let audio = AudioPlayback()
    var generation: GenerationState = .idle
    var playback: PlaybackState = .stopped
    var message: String?
    var currentSentence = 0
    var totalSentences = 0
    var preferredID: String { didSet { defaults.set(preferredID, forKey: "model") } }
    var voicePath: String { didSet { defaults.set(voicePath, forKey: "voice") } }
    var rate: Double { didSet { audio.rate = Float(rate); defaults.set(rate, forKey: "rate") } }
    var playerSize: PlayerSize {
        didSet {
            defaults.set(playerSize.rawValue, forKey: "playerSize")
            if hasReading { showPlayer?() }
        }
    }
    var clipboardFallback: Bool { didSet { defaults.set(clipboardFallback, forKey: "clipboardFallback") } }
    var shortcutLabel: String { didSet { defaults.set(shortcutLabel, forKey: "shortcutLabel") } }
    private(set) var shortcutEnabled: Bool
    var keyCode: UInt32
    var modifiers: UInt32
    var permissionGranted = SelectionReader.hasPermission
    var showWindow: (() -> Void)?
    var showPlayer: (() -> Void)?
    var hidePlayer: (() -> Void)?
    var showModels: (() -> Void)?
    var showSettings: (() -> Void)?
    var presentTextReader: (() -> Void)?
    var closeTextReader: (() -> Void)?
    private(set) var isTextReaderOpen = false
    var draftText = ""
    var canReadDraft: Bool { selectedModel != nil && !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private let defaults: UserDefaults
    private var task: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private let selectionReader: @MainActor (pid_t, Bool) async throws -> String
    private var session = UUID()
    private var sentences: [String] = []
    private(set) var readingText = ""
    private var observers: [NSObjectProtocol] = []
    var selectedModel: ModelDescriptor? { models.installed.first { $0.id == preferredID } }
    var voices: [ModelFile] { selectedModel?.voices ?? [] }
    var isActive: Bool { generation != .idle || playback != .stopped }
    var isPaused: Bool { playback == .paused }
    var hasReading: Bool { !sentences.isEmpty && isActive }
    var status: String {
        if message != nil { return "Needs your attention" }
        if isPaused { return "Paused" }
        switch generation {
        case .capturing: return "Reading selection…"
        case .loading: return "Warming up…"
        case .generating, .finished: return audio.queuedCount > 0 ? "Reading" : "Preparing audio…"
        case .idle: return "Ready when you are"
        }
    }
    init(modelStore: ModelStore? = nil, speechEngine: (any SpeechEngine)? = nil, preferences: UserDefaults? = nil, registerHotkey: Bool = true,
         selectionReader: @escaping @MainActor (pid_t, Bool) async throws -> String = { try await SelectionReader.read(from: $0, allowClipboard: $1) }) {
        self.selectionReader = selectionReader
        let defaults = preferences ?? .standard
        self.defaults = defaults
        self.models = modelStore ?? ModelStore()
        self.speech = speechEngine ?? KokoroWorkerEngine()
        preferredID = defaults.string(forKey: "model") ?? "kokoro-standard"
        voicePath = defaults.string(forKey: "voice") ?? "voices/af_heart.safetensors"
        rate = defaults.object(forKey: "rate") == nil ? 1 : min(2, max(0.5, defaults.double(forKey: "rate")))
        playerSize = PlayerSize(rawValue: defaults.double(forKey: "playerSize")) ?? .standard
        clipboardFallback = defaults.object(forKey: "clipboardFallback") == nil ? true : defaults.bool(forKey: "clipboardFallback")
        shortcutLabel = defaults.string(forKey: "shortcutLabel") ?? "⌥ Space"
        shortcutEnabled = defaults.object(forKey: "shortcutEnabled") as? Bool ?? true
        keyCode = UInt32(defaults.object(forKey: "keyCode") as? Int ?? 49)
        modifiers = UInt32(defaults.object(forKey: "modifiers") as? Int ?? 2048)
        audio.rate = Float(rate)
        audio.onConsumed = { [weak self] index in
            guard let self else { return }
            self.currentSentence = min(index + 1, self.totalSentences)
            self.finishIfDrained()
        }
        hotkey.onPress = { [weak self] in
            guard let self, self.shortcutEnabled else { return }
            self.readSelection()
        }
        guard registerHotkey else { return }
        if shortcutEnabled {
            do { try hotkey.register(key: keyCode, modifiers: modifiers) }
            catch { shortcutEnabled = false; message = error.localizedDescription }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in if self?.isActive == true { self?.pause() } }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                self.stopAndDismiss(); self.message = "Audio output changed. Select your text again to continue."; self.showWindow?()
            }
        })
    }
    func setShortcutEnabled(_ enabled: Bool) {
        guard enabled != shortcutEnabled else { return }
        do {
            if enabled { try hotkey.register(key: keyCode, modifiers: modifiers) }
            else { hotkey.disable() }
            shortcutEnabled = enabled
            defaults.set(enabled, forKey: "shortcutEnabled")
        } catch { message = error.localizedDescription; showWindow?() }
    }
    func recordShortcut(_ event: NSEvent) throws {
        let flags = GlobalHotkey.carbonFlags(event.modifierFlags)
        guard flags != 0, ![36, 48, 51, 53].contains(Int(event.keyCode)) else { throw AltoError("Choose a key with Command, Option, Control or Shift.") }
        if keyCode == UInt32(event.keyCode), modifiers == flags { return }
        if shortcutEnabled { try hotkey.register(key: UInt32(event.keyCode), modifiers: flags) }
        keyCode = UInt32(event.keyCode); modifiers = flags
        defaults.set(Int(keyCode), forKey: "keyCode"); defaults.set(Int(flags), forKey: "modifiers")
        var label = ""
        for (flag, symbol): (NSEvent.ModifierFlags, String) in [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")] {
            if event.modifierFlags.contains(flag) { label += symbol }
        }
        shortcutLabel = label + " " + (event.keyCode == 49 ? "Space" : (event.charactersIgnoringModifiers ?? "Key \(event.keyCode)").uppercased())
    }
    func readSelection() {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, pid != ProcessInfo.processInfo.processIdentifier else {
            message = "Select text in another app and press \(shortcutLabel)."; showWindow?(); return
        }
        readSelection(from: pid)
    }
    func readSelection(from pid: pid_t) {
        guard captureTask == nil else { return }
        stop(keepWorker: generation == .idle)
        hidePlayer?()
        generation = .capturing
        let token = session
        captureTask = Task {
            defer { captureTask = nil }
            do {
                let text = try await selectionReader(pid, clipboardFallback)
                guard session == token, !Task.isCancelled else { return }
                captureTask = nil
                read(text)
            } catch {
                guard session == token, !Task.isCancelled else { return }
                generation = .idle; message = error.localizedDescription; showWindow?()
            }
        }
    }
    func readClipboard() { read(NSPasteboard.general.string(forType: .string) ?? "") }
    func read(_ text: String) {
        do {
            let source = try SelectionReader.checked(text)
            let text = SpeechText.prepare(source)
            guard !text.isEmpty else { throw AltoError("There is no readable text after skipping tags and emojis.") }
            let recognizer = NLLanguageRecognizer(); recognizer.processString(text)
            if text.count > 40, let dominant = recognizer.dominantLanguage, dominant != .english,
               (recognizer.languageHypotheses(withMaximum: 1)[dominant] ?? 0) > 0.8 {
                throw AltoError("The installed speech runtime supports English. Choose English text; other language pipelines are not bundled yet.")
            }
            guard let model = selectedModel else {
                throw AltoError("Download and select a voice model in Models to start listening.")
            }
            let chunks = TextChunker.split(text)
            if isTextReaderOpen { draftText = source }
            start(chunks, model: model, previewText: text)
        } catch { reportReadingError(error.localizedDescription) }
    }
    private func reportReadingError(_ text: String) {
        stop(); hidePlayer?(); message = text
        if !isTextReaderOpen { showWindow?() }
    }
    private func start(_ chunks: [String], model: ModelDescriptor, paused: Bool = false, previewText: String? = nil) {
        stop(keepWorker: generation == .idle || generation == .capturing)
        guard let weight = model.weight, let voice = model.voices.first(where: { $0.path == voicePath }) ?? model.voices.first else { return }
        voicePath = voice.path
        sentences = chunks; totalSentences = chunks.count; currentSentence = 0
        readingText = previewText ?? chunks.joined(separator: "\n\n")
        generation = .loading; playback = paused ? .paused : .playing; audio.paused = paused
        let token = session
        showPlayer?()
        task = Task {
            do {
                var pending = chunks
                var index = 0
                while index < pending.count {
                    try Task.checkCancellation()
                    while audio.bufferedSeconds >= 20 || isPaused {
                        try await Task.sleep(for: .milliseconds(100)); try Task.checkCancellation()
                    }
                    let output: URL
                    do {
                        output = try await speech.generate(model: models.folder(model).appendingPathComponent(weight.path),
                            voice: models.folder(model).appendingPathComponent(voice.path), text: pending[index])
                    } catch {
                        if error.localizedDescription == "tooManyTokens", pending[index].count > 8 {
                            let smaller = TextChunker.split(pending[index], limit: pending[index].count / 2)
                            pending.replaceSubrange(index...index, with: smaller)
                            sentences = pending; totalSentences = pending.count
                            continue
                        }
                        throw error
                    }
                    guard session == token, !Task.isCancelled else { return }
                    generation = .generating
                    try audio.schedule(output, index: index)
                    try? FileManager.default.removeItem(at: output)
                    index += 1
                }
                guard session == token else { return }
                generation = .finished; finishIfDrained()
            } catch {
                guard session == token, !Task.isCancelled else { return }
                reportReadingError(error.localizedDescription)
            }
        }
    }
    private func finishIfDrained() {
        guard generation == .finished, audio.queuedCount == 0 else { return }
        generation = .idle; playback = .stopped
        sentences = []; totalSentences = 0; currentSentence = 0
        readingText = ""
        hidePlayer?()
        cleanupTask = Task { try? await Task.sleep(for: .seconds(60)); if !Task.isCancelled { speech.unload() } }
    }
    func pause() { playback = .paused; audio.pause() }
    func togglePause() {
        guard isActive else { return }
        if isPaused { playback = .playing; audio.resume() } else { pause() }
    }
    func changeVoice(_ path: String) {
        let remaining = Array(sentences.dropFirst(currentSentence))
        let wasPaused = isPaused
        voicePath = path
        if isActive, !remaining.isEmpty, let model = selectedModel { start(remaining, model: model, paused: wasPaused) }
    }
    func selectModel(_ model: ModelDescriptor) {
        stop()
        guard let weight = model.weight, let voice = model.voices.first else { return }
        generation = .loading; hidePlayer?()
        let token = session
        task = Task {
            do {
                let output = try await speech.generate(model: models.folder(model).appendingPathComponent(weight.path),
                    voice: models.folder(model).appendingPathComponent(voice.path), text: "Ready to read.")
                try? FileManager.default.removeItem(at: output)
                guard session == token, !Task.isCancelled else { return }
                preferredID = model.id
                if !model.voices.contains(where: { $0.path == voicePath }) { voicePath = voice.path }
                generation = .idle; hidePlayer?()
                cleanupTask = Task { try? await Task.sleep(for: .seconds(60)); if !Task.isCancelled { speech.unload() } }
            } catch {
                guard session == token, !Task.isCancelled else { return }
                stopAndDismiss(); message = "Could not switch models. Your previous choice is preserved. " + error.localizedDescription; showModels?()
            }
        }
    }
    func deleteModel(_ model: ModelDescriptor) {
        do {
            if preferredID == model.id { stop() }
            try models.delete(model)
            if preferredID == model.id { preferredID = models.installed.first?.id ?? "kokoro-standard" }
        } catch { message = error.localizedDescription }
    }
    func stop(keepWorker: Bool = false) {
        captureTask?.cancel()
        session = UUID(); task?.cancel(); task = nil; cleanupTask?.cancel(); cleanupTask = nil
        audio.stop(); if !keepWorker { speech.unload() }; generation = .idle; playback = .stopped
        sentences = []; totalSentences = 0; currentSentence = 0; message = nil
        readingText = ""
    }
    func shutdown() { stop(); captureTask?.cancel(); models.cancelAll(); hotkey.unregister() }
    func openTextReader() {
        if !isTextReaderOpen { stop(); hidePlayer?(); isTextReaderOpen = true }
        presentTextReader?()
    }
    func playDraft() {
        if hasReading { togglePause() }
        else if canReadDraft { read(draftText) }
    }
    func stopAndDismiss() {
        stop(); hidePlayer?()
        if isTextReaderOpen {
            isTextReaderOpen = false; draftText = ""; closeTextReader?()
        }
    }
    var hasPendingCapture: Bool { captureTask != nil }
    func finishCaptureBeforeQuitting() async {
        // Invalidate speech immediately, but let an in-flight Copy restore the
        // clipboard before ending the process. This takes at most the AX/copy timeout.
        stop()
        await captureTask?.value
    }
}
