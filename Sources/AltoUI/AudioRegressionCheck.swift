import Foundation
import AVFoundation
import AltoCore

@MainActor enum AudioRegressionCheck {
    // Opt-in only. Uses existing test installations, not user text or models.
    static func run(at root: URL) async throws {
        let helper = Process()
        helper.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/AltoSpeechWorker")
        helper.arguments = ["--check-convolution"]
        try helper.run()
        let deadline = Date().addingTimeInterval(60)
        while helper.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        guard !helper.isRunning else { helper.terminate(); throw AltoError("Convolution regression timed out.") }
        guard helper.terminationStatus == 0 else { throw AltoError("Runtime returned incorrect convolution results.") }

        let store = ModelStore(root: root.appendingPathComponent("Models"))
        let destination = root.appendingPathComponent("audio-regression-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let passages = [
            "Alto reads entirely on your Mac.",
            "Reading should feel calm and effortless, whether you are following a short note or a longer passage about the world around you, with every word spoken clearly and without distracting noise in the background.",
            "When the morning sun appeared over the hills, the village slowly came to life, and people opened their windows to welcome the fresh air, while a small group of friends gathered beside the river to plan their journey through the countryside, taking their time to enjoy the quiet streets and the sound of birds in the trees before they set off together toward the mountains in the distance."
        ]
        var results: [[String: Any]] = []
        for id in ["kokoro-standard", "kokoro-compact"] {
            guard let model = store.installed.first(where: { $0.id == id }), let weight = model.weight else {
                throw AltoError("Install both test models using --integration-test before running audio regression.")
            }
            let engine = NativeSpeechWorkerEngine()
            defer { engine.unload() }
            var footprints: [Int] = []
            for voice in model.voices.prefix(4) {
                for (index, passage) in passages.enumerated() {
                    let start = Date()
                    let url = try await engine.generate(model: store.folder(model).appendingPathComponent(weight.path),
                        voice: store.folder(model).appendingPathComponent(voice.path), text: passage)
                    let file = try AVAudioFile(forReading: url)
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
                        throw AltoError("Cannot read regression audio.")
                    }
                    try file.read(into: buffer)
                    let samples = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
                    let leading = samples.prefix(Int(file.processingFormat.sampleRate * 0.2))
                    let leadingRMS = sqrt(leading.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(leading.count))
                    let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
                    let output = destination.appendingPathComponent("\(id)-\(URL(fileURLWithPath: voice.path).deletingPathExtension().lastPathComponent)-\(index).wav")
                    try FileManager.default.copyItem(at: url, to: output)
                    // These fixed fixtures start with silence; this is not a
                    // general silence requirement or a filter on user speech.
                    guard samples.allSatisfy({ $0.isFinite }), peak > 0.01, peak < 1,
                          leadingRMS < 0.0001 else {
                        throw AltoError("Corrupted speech: \(output.lastPathComponent), leading RMS \(leadingRMS), peak \(peak). Sample saved for inspection.")
                    }
                    let footprint = engine.workerFootprint ?? 0
                    footprints.append(footprint)
                    results.append(["model": id, "voice": voice.path, "characters": passage.count,
                        "leadingRMS": leadingRMS, "peak": peak, "generationSeconds": Date().timeIntervalSince(start),
                        "audioSeconds": Double(file.length) / file.processingFormat.sampleRate, "workerFootprintBytes": footprint])
                    print("PASS \(output.lastPathComponent): leading RMS \(leadingRMS), peak \(peak), worker \(footprint / 1_048_576) MB"); fflush(stdout)
                }
            }
            // MLX's buffer pool once grew by gigabytes per chunk; twelve chunks
            // reached ~40 GB. The fixed worker settles between 1 and 2 GB.
            guard let last = footprints.last, last < 4_000_000_000 else {
                throw AltoError("Worker memory grew to \((footprints.last ?? 0) / 1_048_576) MB after \(footprints.count) chunks. The MLX buffer pool is no longer bounded.")
            }
        }
        try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
            .write(to: destination.appendingPathComponent("measurements.json"))
        print("PASS 24 speech fixtures and exact convolution checks. Saved: \(destination.path)"); fflush(stdout)
    }
}
