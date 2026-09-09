import Foundation
import AVFoundation
import AltoCore

/// Explicit opt-in integration mode: uses a caller-selected scratch directory,
/// downloads real model files, tests the bundled worker, and exits. No text from
/// other apps, user clipboard, preferences, or existing model installs is touched.
@MainActor enum IntegrationCheck {
    static func run(at root: URL, offline: Bool, audiblePlayback: Bool = false) async throws {
        let store = ModelStore(root: root.appendingPathComponent("Models"))
        let engine = KokoroWorkerEngine()
        defer { engine.unload() }
        func log(_ text: String) { print(text); fflush(stdout) }
        if !offline {
            let inspected = try await store.inspectHub("mlx-community/Kokoro-82M-bf16", revision: "a71e4d38b236d968966a2002c4c895dbd12b1c3c")
            guard inspected.weight != nil, !inspected.voices.isEmpty else { throw AltoError("Hub inspection failed.") }
            log("PASS Hugging Face inspection: \(inspected.voices.count) English voices")
        }
        var results: [[String: Any]] = []
        for model in store.catalog {
            if !store.isInstalled(model) {
                guard !offline else { throw AltoError("Install test models before the offline run.") }
                store.download(model)
                if model.id == "kokoro-standard" {
                    let cancelDeadline = Date().addingTimeInterval(20)
                    while (store.progress[model.id] ?? 0) < 0.02, store.progress[model.id] != nil, Date() < cancelDeadline {
                        try await Task.sleep(for: .milliseconds(20))
                    }
                    store.cancel(model)
                    while store.progress[model.id] != nil { try await Task.sleep(for: .milliseconds(20)) }
                    guard !store.isInstalled(model) else { throw AltoError("Cancelled download was marked installed.") }
                    log("PASS interrupted download remains uninstalled")
                    store.download(model)
                }
                let deadline = Date().addingTimeInterval(600)
                while store.progress[model.id] != nil, Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
                guard store.isInstalled(model) else { throw AltoError(store.status[model.id] ?? "Installation timed out.") }
                log("PASS verified download and atomic install: \(model.name), \(model.downloadBytes) bytes")
            }
            let folder = store.folder(model)
            let firstVoice = model.voices.first(where: { $0.path.contains("af_heart") })!
            var output: URL?
            for (index, text) in ["Alto reads entirely on your Mac.", "On September ninth, the train leaves at three thirty. Take a breath, and listen."].enumerated() {
                let start = Date()
                let file = try await engine.generate(model: folder.appendingPathComponent(model.weight!.path),
                    voice: folder.appendingPathComponent(firstVoice.path), text: text)
                let audio = try AVAudioFile(forReading: file)
                let duration = Double(audio.length) / audio.processingFormat.sampleRate
                guard duration > 0.3 else { throw AltoError("Generated audio is too short.") }
                results.append(["model": model.id, "run": index, "generationSeconds": Date().timeIntervalSince(start), "audioSeconds": duration])
                log("PASS \(model.name) run \(index): \(duration.formatted()) seconds of audio")
                let saved = root.appendingPathComponent("\(model.id)-\(index).wav")
                if FileManager.default.fileExists(atPath: saved.path) { try FileManager.default.removeItem(at: saved) }
                try FileManager.default.copyItem(at: file, to: saved)
                if index == 0 { output = file }
            }
            if audiblePlayback, let output {
                let playback = AudioPlayback()
                playback.rate = 2
                var completed = false
                playback.onConsumed = { _ in completed = true }
                playback.paused = true
                try playback.schedule(output, index: 0)
                try await Task.sleep(for: .milliseconds(300))
                guard !completed, playback.queuedCount == 1 else { throw AltoError("Pause did not hold queued audio.") }
                playback.resume()
                let deadline = Date().addingTimeInterval(20)
                while !completed, Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
                guard completed, playback.queuedCount == 0 else { throw AltoError("Playback did not drain.") }
                try playback.schedule(output, index: 1)
                playback.stop()
                guard playback.queuedCount == 0 else { throw AltoError("Stop did not flush audio.") }
                log("PASS playback, pause/resume, 2× speed and stop")
            }
            engine.unload()
        }
        if !offline, store.installed.count == 2, let model = store.installed.first {
            try await store.importLocal(store.folder(model))
            guard store.installed.count == 3 else { throw AltoError("Local model import failed.") }
            log("PASS compatible local folder import")
        }
        if !offline {
            let hub = try await store.inspectHub("mlx-community/Kokoro-82M-bf16", revision: "a71e4d38b236d968966a2002c4c895dbd12b1c3c")
            if !store.isInstalled(hub) {
                store.addToCatalog(hub)
                let deadline = Date().addingTimeInterval(600)
                while store.progress[hub.id] != nil, Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
                guard store.isInstalled(hub) else { throw AltoError(store.status[hub.id] ?? "Hub import timed out.") }
            }
            let output = try await engine.generate(model: store.folder(hub).appendingPathComponent(hub.weight!.path),
                voice: store.folder(hub).appendingPathComponent(hub.voices.first!.path), text: "This voice was imported from Hugging Face.")
            guard FileManager.default.fileExists(atPath: output.path) else { throw AltoError("Imported Hub model did not synthesize.") }
            engine.unload()
            log("PASS Hugging Face import, installation and synthesis")
            let reloaded = ModelStore(root: root.appendingPathComponent("Models"))
            guard reloaded.installed.count == store.installed.count else { throw AltoError("Installed model metadata did not survive reload.") }
            log("PASS installed metadata reload")
        }
        if audiblePlayback {
            try await checkAudibleCoordinator(store: store)
            log("PASS coordinator pause during generation, replacement, completion and cancellation")
        } else {
            log("SKIP speaker playback and audible coordinator checks (requires --audible-playback)")
        }
        let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent(offline ? "offline-results.json" : "results.json"), options: .atomic)
        log("PASS requested integration checks. Audible playback: \(audiblePlayback). Results: \(root.path)")
    }

    private static func checkAudibleCoordinator(store: ModelStore) async throws {
        // Exercise the coordinator as well as its audio primitives. Preferences
        // use an isolated suite and no global hotkey or workspace observer is installed.
        let suite = "software.petit.alto.integration." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let coordinator = AppModel(modelStore: store, preferences: preferences, registerHotkey: false)
        defer { coordinator.shutdown() }
        coordinator.rate = 2
        coordinator.read("The first passage begins here. " + String(repeating: "This is a longer reading to exercise the audio queue. ", count: 6))
        try await Task.sleep(for: .milliseconds(100))
        coordinator.pause()
        try await Task.sleep(for: .milliseconds(200))
        guard coordinator.isPaused else { throw AltoError("Coordinator lost pause intent during generation.") }
        coordinator.togglePause()
        try await Task.sleep(for: .milliseconds(100))
        coordinator.read("A replacement reading should be the only one you hear.")
        let deadline = Date().addingTimeInterval(30)
        while coordinator.isActive, Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        guard coordinator.message == nil, !coordinator.isActive else { throw AltoError(coordinator.message ?? "Replacement reading did not finish.") }
        coordinator.read("Stopping this reading must flush both generation and playback.")
        coordinator.stop()
        try await Task.sleep(for: .milliseconds(300))
        guard !coordinator.isActive, coordinator.audio.queuedCount == 0 else { throw AltoError("Cancelled reading restarted.") }
    }
}
