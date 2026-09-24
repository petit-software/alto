import XCTest
import CoreML
@testable import AltoChatterbox

final class ChatterboxTests: XCTestCase {
    func testStridedCoreMLOutputDoesNotSmearRows() throws {
        let storage = UnsafeMutablePointer<Float>.allocate(capacity: 8)
        storage.initialize(from: [1, 2, 3, 99, 4, 5, 6, 99], count: 8)
        let array = try MLMultiArray(dataPointer: storage, shape: [1, 2, 3], dataType: .float32,
                                    strides: [8, 4, 1], deallocator: { $0.deallocate() })
        XCTAssertEqual(try ChatterboxMLSupport.floatBuffer(array), [1, 2, 3, 4, 5, 6])
    }

    func testAudioBudgetReservesReferenceAndSilence() {
        XCTAssertEqual(ChatterboxNanoOutputCapacity.standard.generationBudget(promptTokens: 250), 247)
        XCTAssertEqual(ChatterboxNanoOutputCapacity.standard.generationBudget(promptTokens: 600), 0)
    }

    func testTokenizerRejectsOutOfRangeEmbeddingAndRecognizesTags() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("{\"h\":0,\"i\":1}".utf8).write(to: folder.appendingPathComponent("vocab.json"))
        try Data("#version: 0.2\n".utf8).write(to: folder.appendingPathComponent("merges.txt"))
        try Data("{\"[laugh]\":2}".utf8).write(to: folder.appendingPathComponent("added_tokens.json"))
        let tokenizer = try ChatterboxNanoTokenizer(vocabURL: folder.appendingPathComponent("vocab.json"),
            mergesURL: folder.appendingPathComponent("merges.txt"), addedTokensURL: folder.appendingPathComponent("added_tokens.json"))
        XCTAssertNoThrow(try tokenizer.validate(embeddingRows: 3))
        XCTAssertThrowsError(try tokenizer.validate(embeddingRows: 2))
        XCTAssertEqual(tokenizer.encode("hi[laugh]"), [0, 1, 2])
    }
}
