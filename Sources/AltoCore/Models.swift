import Foundation
import CryptoKit

public struct ModelFile: Codable, Hashable, Sendable {
    public var path: String
    public var bytes: Int64
    public var sha256: String?
    public var url: URL?
}

public struct ModelDescriptor: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var summary: String
    public var family: String
    public var repository: String
    public var revision: String
    public var license: String
    public var languages: [String]
    public var files: [ModelFile]
    public var downloadBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }
    public var sizeLabel: String { ByteCountFormatter.string(fromByteCount: downloadBytes, countStyle: .file) }
    public var weight: ModelFile? { files.first { $0.path.hasSuffix(".safetensors") && !$0.path.contains("/") } }
    public var isChatterboxNano: Bool { family == ModelValidation.chatterboxFamily }
    public var inferencePath: String? { isChatterboxNano ? "alto-model.json" : weight?.path }
    public var familyLabel: String { isChatterboxNano ? "Chatterbox Nano" : "Kokoro v1" }
    public var chunkLimit: Int { isChatterboxNano ? 140 : 220 }
    public var voices: [ModelFile] {
        files.filter { isChatterboxNano ? $0.path == "tables/voice-default.safetensors" : $0.path.hasPrefix("voices/") }
            .sorted { $0.path < $1.path }
    }
    public static func voiceName(_ path: String) -> String {
        if path == "tables/voice-default.safetensors" { return "Default · English" }
        let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let name = stem.split(separator: "_").dropFirst().joined(separator: " ").capitalized
        return name + (stem.hasPrefix("b") ? " · UK" : " · US")
    }
}

public enum ModelValidation {
    public static let supportedFamily = "kokoro-v1"
    public static let chatterboxFamily = "chatterbox-nano-coreml"
    public static let supportedFamilies: Set<String> = [supportedFamily, chatterboxFamily]
    public static let nanoModels = [
        "T3Nano-Prefill-T512-M1536-fp16.mlmodelc",
        "T3Nano-Decode-M1536-fp16-stateful.mlmodelc",
        "FlowMean-N500-fp16.mlmodelc", "HiFT-T1000-fp16.mlmodelc"
    ]
    public static let nanoAuxFiles = ["tables/tables.safetensors", "tables/voice-default.safetensors",
                                     "tokenizer/vocab.json", "tokenizer/merges.txt", "tokenizer/added_tokens.json"]
    public static func validateNanoManifest(_ model: ModelDescriptor) throws {
        let paths = Set(model.files.map(\.path))
        let required = nanoAuxFiles + nanoModels.flatMap { [$0 + "/coremldata.bin", $0 + "/model.mil", $0 + "/weights/weight.bin"] }
        guard model.isChatterboxNano, paths.count == model.files.count,
              required.allSatisfy(paths.contains),
              model.files.allSatisfy({ $0.bytes > 0 && $0.sha256?.count == 64 }) else {
            throw AltoError("Incomplete Chatterbox Nano manifest. Use the model in Alto's catalog.")
        }
    }
    public static func containedURL(_ path: String, in root: URL) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.split(separator: "/").contains(".."),
              !path.contains("\\") else { throw AltoError("Invalid model file path.") }
        var componentURL = root.resolvingSymlinksInPath().standardizedFileURL
        for component in path.split(separator: "/") {
            componentURL.appendPathComponent(String(component))
            if (try? componentURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw AltoError("Model assets cannot contain symbolic links.")
            }
        }
        let target = componentURL.standardizedFileURL
        guard target.path.hasPrefix(root.resolvingSymlinksInPath().standardizedFileURL.path + "/") else {
            throw AltoError("Model files must stay inside their installation folder.")
        }
        return target
    }
    public static func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public static func verify(_ file: ModelFile, in root: URL) throws {
        let url = try containedURL(file.path, in: root)
        let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard bytes == file.bytes else { throw AltoError("Incomplete file: \(file.path). Retry the download.") }
        if let expected = file.sha256, try hash(url) != expected {
            throw AltoError("Integrity check failed for \(file.path). Delete the partial download and retry.")
        }
    }
    /// Validate the header before the native loader sees untrusted tensors.
    public static func tensors(_ url: URL) throws -> [String: [String: Any]] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let prefix = try handle.read(upToCount: 8), prefix.count == 8 else { throw AltoError("Incomplete safetensors file.") }
        let count = prefix.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << ($1.offset * 8) }
        guard count > 0, count < 4_000_000,
              let header = try handle.read(upToCount: Int(count)), header.count == count,
              let object = try JSONSerialization.jsonObject(with: header) as? [String: Any] else {
            throw AltoError("Not a supported safetensors file. PyTorch, ONNX, GGUF and Git LFS pointers cannot be loaded.")
        }
        let size = try handle.seekToEnd()
        var tensors: [String: [String: Any]] = [:]
        for (name, value) in object where name != "__metadata__" {
            guard let tensor = value as? [String: Any], let shape = tensor["shape"] as? [Int],
                  let offsets = tensor["data_offsets"] as? [Int], offsets.count == 2,
                  let dtype = tensor["dtype"] as? String,
                  let stride = ["F32": 4, "F16": 2, "BF16": 2, "I64": 8][dtype],
                  shape.allSatisfy({ $0 > 0 && $0 <= 1_000_000 }),
                  offsets[0] >= 0, offsets[1] >= offsets[0],
                  UInt64(offsets[1]) <= size - min(size, count + 8) else {
                throw AltoError("Unsupported tensor or invalid offsets: \(name).")
            }
            var elements = 1
            for dimension in shape {
                let product = elements.multipliedReportingOverflow(by: dimension)
                guard !product.overflow, product.partialValue <= 500_000_000 else { throw AltoError("Tensor is too large.") }
                elements = product.partialValue
            }
            guard elements * stride == offsets[1] - offsets[0] else { throw AltoError("Invalid tensor length: \(name).") }
            tensors[name] = tensor
        }
        return tensors
    }
    public static func validateKokoro(_ url: URL, schema: [String: [Int]]) throws {
        let tensors = try tensors(url)
        var normalized: [String: [String: Any]] = [:]
        for (key, value) in tensors {
            let canonical = canonicalKey(key)
            guard normalized[canonical] == nil else { throw AltoError("Ambiguous duplicate tensor names.") }
            normalized[canonical] = value
        }
        let compact = tensors.keys.contains { canonicalKey($0) != $0 }
        for (name, shape) in schema where !(compact && name.hasPrefix("bert.pooler")) {
            guard let tensor = normalized[name], tensor["shape"] as? [Int] == shape else {
                throw AltoError("Incompatible Kokoro weights: missing or different tensor \(name). Quantized and other architectures need another runtime.")
            }
        }
    }
    public static func canonicalKey(_ name: String) -> String {
        var key = name.replacingOccurrences(of: "albertLayerGroups", with: "albert_layer_groups")
            .replacingOccurrences(of: "albertLayers", with: "albert_layers")
            .replacingOccurrences(of: "fullLayerLayerNorm", with: "full_layer_layer_norm")
            .replacingOccurrences(of: "ffnOutput", with: "ffn_output")
            .replacingOccurrences(of: "decoder.asr_res.conv.", with: "decoder.asr_res.0.")
        if key.hasPrefix("text_encoder.cnn.") {
            key = key.replacingOccurrences(of: ".conv.", with: ".0.").replacingOccurrences(of: ".norm.", with: ".1.")
        }
        return key
    }
}

public enum AltoPaths {
    public static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Alto", isDirectory: true)
    }
    public static var models: URL { support.appendingPathComponent("Models", isDirectory: true) }
}
