import Foundation
import AVFoundation

@MainActor public protocol SpeechEngine: AnyObject {
    func generate(model: URL, voice: URL, text: String) async throws -> URL
    func unload()
}

@MainActor public final class KokoroWorkerEngine: SpeechEngine {
    private var process: Process?
    private var input: Pipe?
    private var scratch: URL?
    public init() {}
    private func start() throws {
        guard process?.isRunning != true else { return }
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/AltoSpeechWorker")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw AltoError("The native speech worker is missing. Run the bundled Alto.app built with Xcode.")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("alto-speech-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let child = Process(), pipe = Pipe()
        child.executableURL = executable
        child.arguments = [folder.path]
        // MLX 0.30.2's NAX path corrupts long Kokoro convolutions on M5.
        // Set this before process initialization; all inference tensors are F32.
        var environment = ProcessInfo.processInfo.environment
        environment["MLX_ENABLE_TF32"] = "0"
        child.environment = environment
        child.standardInput = pipe
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { _ in try? FileManager.default.removeItem(at: folder) }
        try child.run()
        process = child; input = pipe; scratch = folder
    }
    public func generate(model: URL, voice: URL, text: String) async throws -> URL {
        try Task.checkCancellation()
        try start()
        guard let child = process, let scratch, let input else { throw AltoError("Could not start speech.") }
        let output = scratch.appendingPathComponent(UUID().uuidString + ".wav")
        let request = SpeechRequest(model: model.path, voice: voice.path, text: text, output: output.path)
        var data = try JSONEncoder().encode(request); data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
        let responseURL = output.appendingPathExtension("json")
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            try Task.checkCancellation()
            if FileManager.default.fileExists(atPath: responseURL.path) {
                let response = try JSONDecoder().decode(SpeechResponse.self, from: Data(contentsOf: responseURL))
                try? FileManager.default.removeItem(at: responseURL)
                if let error = response.error { throw AltoError(error) }
                return output
            }
            guard child.isRunning else { throw AltoError("The speech runtime stopped. This model may be incompatible or your Mac may be low on memory. Try Kokoro again.") }
            try await Task.sleep(for: .milliseconds(20))
        }
        unload()
        throw AltoError("The model took too long to respond. Try a shorter selection or another model.")
    }
    /// Physical footprint of the running worker in bytes, as Activity Monitor
    /// reports it. Regression checks use this to catch runaway GPU memory.
    public var workerFootprint: Int? {
        guard let pid = process?.processIdentifier, process?.isRunning == true else { return nil }
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return status == 0 ? Int(info.ri_phys_footprint) : nil
    }
    public func unload() {
        try? input?.fileHandleForWriting.close()
        if process?.isRunning == true { process?.terminate() }
        process = nil; input = nil; scratch = nil
    }
}

@MainActor public final class AudioPlayback {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private var epoch = UUID()
    public private(set) var bufferedSeconds: Double = 0
    public private(set) var queuedCount = 0
    public var onConsumed: ((Int) -> Void)?
    public var paused = false
    public var rate: Float = 1 { didSet { timePitch.rate = min(2, max(0.5, rate)) } }
    public init() {
        engine.attach(player); engine.attach(timePitch)
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
    }
    public func schedule(_ url: URL, index: Int) throws {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0, file.length <= 2_880_000,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw AltoError("Invalid audio returned by the model.")
        }
        try file.read(into: buffer)
        if !engine.isRunning { try engine.start() }
        let duration = Double(buffer.frameLength) / file.processingFormat.sampleRate
        bufferedSeconds += duration; queuedCount += 1
        let generation = epoch
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.epoch == generation else { return }
                self.bufferedSeconds = max(0, self.bufferedSeconds - duration)
                self.queuedCount = max(0, self.queuedCount - 1)
                self.onConsumed?(index)
            }
        }
        if !paused && !player.isPlaying { player.play() }
    }
    public func pause() { paused = true; player.pause() }
    public func resume() { paused = false; if queuedCount > 0 { player.play() } }
    public func stop() {
        epoch = UUID(); player.stop(); engine.stop()
        bufferedSeconds = 0; queuedCount = 0; paused = false
    }
}
