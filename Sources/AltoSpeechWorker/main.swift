import Foundation
import AVFoundation
import KokoroSwift
import MLX
import AltoCore

// Keep ordinary F32 GPU math; the pinned MLX NAX kernel overflows on long
// convolutions (mlx#3092). Misaki also pins MLX, so an isolated version bump
// cannot resolve. This is worker-local, not a change to the user's environment.
// The unsafe comparison mode only computes test tensors; it never makes audio.
let unsafeKernelCheck = CommandLine.arguments.contains("--check-convolution-unsafe")
setenv("MLX_ENABLE_TF32", unsafeKernelCheck ? "1" : "0", 1)
if unsafeKernelCheck || CommandLine.arguments.contains("--check-convolution") {
    let success = SpeechRuntimeCheck.run()
    exit(success ? 0 : 1)
}

// A native, persistent worker isolates third-party loader assertions from the UI.
// Requests travel over stdin. Only an atomic response file signals completion;
// dependency debug output is never interpreted as protocol traffic.
// Diagnostics only: ALTO_MEMORY_LOG=1 reports MLX and process memory after
// each request on stderr. The app discards stderr, so this never reaches users.
let memoryLog = ProcessInfo.processInfo.environment["ALTO_MEMORY_LOG"] != nil
func reportMemory(_ label: String) {
    guard memoryLog else { return }
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    let footprint = result == KERN_SUCCESS ? Int(info.phys_footprint) : -1
    let snapshot = MLX.Memory.snapshot()
    let mb = { (bytes: Int) in String(format: "%.0f", Double(bytes) / 1_048_576) }
    FileHandle.standardError.write("MEM \(label) footprint=\(mb(footprint))MB active=\(mb(snapshot.activeMemory))MB cache=\(mb(snapshot.cacheMemory))MB peak=\(mb(snapshot.peakMemory))MB cacheLimit=\(mb(MLX.Memory.cacheLimit))MB\n".data(using: .utf8)!)
}
// MLX keeps every freed GPU buffer in a pool and only recycles one of almost
// identical size. Each chunk's tensors are shaped by its own length, so the
// pool grew by several gigabytes per chunk until it reached the device limit
// (~50 GB on a 64 GB Mac). Bounding the pool costs no measurable time; the
// worker idles between chunks, so the pool is also emptied after each request.
MLX.Memory.cacheLimit = 256 * 1024 * 1024
var engine: KokoroTTS?
var loadedPath: String?
let scratch = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : FileManager.default.temporaryDirectory
let prepared = scratch.appendingPathComponent("alto-prepared-" + UUID().uuidString + ".safetensors")
defer { try? FileManager.default.removeItem(at: prepared) }
while let line = readLine() {
    guard let data = line.data(using: .utf8),
          let request = try? JSONDecoder().decode(SpeechRequest.self, from: data) else { continue }
    let start = Date()
    var response = SpeechResponse()
    do {
        if loadedPath != request.model {
            engine = nil
            let original = URL(fileURLWithPath: request.model)
            let header = try ModelValidation.tensors(original)
            if header.contains(where: { ModelValidation.canonicalKey($0.key) != $0.key || ($0.value["dtype"] as? String) != "F32" }) {
                let arrays = try MLX.loadArrays(url: original)
                var canonical: [String: MLXArray] = [:]
                for (key, value) in arrays { canonical[ModelValidation.canonicalKey(key)] = value.asType(.float32) }
                // The compact export omits ALBERT's unused pooled output. Kokoro
                // consumes only the sequence output, but this loader constructs both.
                if canonical["bert.pooler.weight"] == nil { canonical["bert.pooler.weight"] = MLXArray.zeros([768, 768]) }
                if canonical["bert.pooler.bias"] == nil { canonical["bert.pooler.bias"] = MLXArray.zeros([768]) }
                try MLX.save(arrays: canonical, url: prepared)
                engine = KokoroTTS(modelPath: prepared)
            } else {
                engine = KokoroTTS(modelPath: original)
            }
            loadedPath = request.model
        }
        let voiceURL = URL(fileURLWithPath: request.voice)
        let arrays = try MLX.loadArrays(url: voiceURL)
        guard let voice = arrays.values.first, voice.shape == [510, 1, 256] else {
            throw AltoError("Voice must contain a 510 × 1 × 256 Kokoro embedding.")
        }
        let language: Language = voiceURL.lastPathComponent.hasPrefix("b") ? .enGB : .enUS
        let (samples, _) = try engine!.generateAudio(voice: voice.asType(.float32), language: language, text: request.text)
        guard !samples.isEmpty, samples.count < 2_880_000, samples.allSatisfy({ $0.isFinite }) else {
            throw AltoError("The model returned invalid or oversized audio.")
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        let file = try AVAudioFile(forWriting: URL(fileURLWithPath: request.output), settings: format.settings)
        try file.write(from: buffer)
        response = SpeechResponse(samples: samples.count, seconds: Date().timeIntervalSince(start))
    } catch KokoroTTS.KokoroTTSError.tooManyTokens {
        response.error = "tooManyTokens"
    } catch {
        response.error = error.localizedDescription
    }
    MLX.Memory.clearCache()
    reportMemory("after-request samples=\(response.samples)")
    if let data = try? JSONEncoder().encode(response) {
        try? data.write(to: URL(fileURLWithPath: request.output + ".json"), options: .atomic)
    }
}
