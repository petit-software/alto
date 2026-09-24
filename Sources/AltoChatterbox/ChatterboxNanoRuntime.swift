import Foundation
@preconcurrency import CoreML
import AltoCore

// Alto owns installation. This loader has no network or global model cache.
struct ChatterboxNanoModels: Sendable {
    let prefill: MLModel
    let decode: MLModel
    let flow: MLModel
    let vocoder: MLModel
    let capacity: ChatterboxNanoOutputCapacity = .standard
    let tokenizer: ChatterboxNanoTokenizer
    let tables: ChatterboxTables.Nano
    let voice: ChatterboxTables.Voice

    static func load(manifest: URL) async throws -> Self {
        let descriptor = try JSONDecoder().decode(ModelDescriptor.self, from: Data(contentsOf: manifest))
        try ModelValidation.validateNanoManifest(descriptor)
        let directory = manifest.deletingLastPathComponent()
        for file in descriptor.files { try ModelValidation.verify(file, in: directory) }
        func asset(_ path: String) throws -> URL { try ModelValidation.containedURL(path, in: directory) }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndGPU
        var models: [MLModel] = []
        for path in ModelValidation.nanoModels {
            models.append(try await MLModel.load(contentsOf: asset(path), configuration: configuration))
        }
        let tokenizer = try ChatterboxNanoTokenizer(
            vocabURL: asset("tokenizer/vocab.json"), mergesURL: asset("tokenizer/merges.txt"),
            addedTokensURL: asset("tokenizer/added_tokens.json"))
        let tables = try ChatterboxTables.loadNano(tablesURL: asset("tables/tables.safetensors"))
        let voice = try ChatterboxTables.loadVoice(voiceURL: asset("tables/voice-default.safetensors"))
        try ChatterboxTables.validate(tables, voice: voice)
        try tokenizer.validate(embeddingRows: tables.textEmb.rows)
        return Self(prefill: models[0], decode: models[1], flow: models[2], vocoder: models[3],
                    tokenizer: tokenizer, tables: tables, voice: voice)
    }
}

public actor ChatterboxNanoRuntime {
    private var models: ChatterboxNanoModels?
    public init() {}

    public func load(manifest: URL) async throws {
        models = try await ChatterboxNanoModels.load(manifest: manifest)
    }

    public func generate(text: String, seed: UInt64 = 42) async throws -> [Float] {
        guard let models else { throw AltoError("Chatterbox Nano has not been loaded.") }
        let result = try await ChatterboxNanoSynthesizer(models: models).synthesize(
            text: text, temperature: ChatterboxNanoConstants.temperature,
            topK: ChatterboxNanoConstants.topK, topP: ChatterboxNanoConstants.topP,
            repetitionPenalty: ChatterboxNanoConstants.repetitionPenalty, seed: seed)
        return result.samples
    }
}
