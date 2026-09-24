import XCTest
@testable import AltoCore

final class ModelValidationTests: XCTestCase {
    func testNanoCatalogHasCompletePinnedAssetsAndItsOwnVoice() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try JSONDecoder().decode([ModelDescriptor].self, from: Data(contentsOf: root.appendingPathComponent("Resources/catalog.json")))
        var nano = try XCTUnwrap(catalog.first(where: { $0.id == "chatterbox-nano" }))
        XCTAssertNoThrow(try ModelValidation.validateNanoManifest(nano))
        XCTAssertEqual(nano.inferencePath, "alto-model.json")
        XCTAssertEqual(nano.voices.map(\.path), ["tables/voice-default.safetensors"])
        XCTAssertEqual(ModelDescriptor.voiceName(nano.voices[0].path), "Default · English")
        XCTAssertNil(nano.weight)
        XCTAssertTrue(nano.files.allSatisfy { $0.url?.path.contains(nano.revision) == true })
        nano.files.removeAll { $0.path == "tokenizer/vocab.json" }
        XCTAssertThrowsError(try ModelValidation.validateNanoManifest(nano))
        let kokoro = try XCTUnwrap(catalog.first(where: { $0.id == "kokoro-standard" }))
        XCTAssertEqual(kokoro.inferencePath, kokoro.weight?.path)
        XCTAssertEqual(kokoro.voices.count, 4)
    }

    @MainActor func testNanoInstallationSurvivesStoreReload() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try JSONDecoder().decode([ModelDescriptor].self, from: Data(contentsOf: repository.appendingPathComponent("Resources/catalog.json")))
        let nano = try XCTUnwrap(catalog.first(where: { $0.id == "chatterbox-nano" }))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent(nano.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(nano).write(to: folder.appendingPathComponent("alto-model.json"))
        XCTAssertTrue(ModelStore(root: root).isInstalled(nano))
    }

    func testTraversalAndSymlinkEscape() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["../outside", "/etc/passwd", "a/../../b", "foo\\bar"] {
            XCTAssertThrowsError(try ModelValidation.containedURL(path, in: root))
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root.deletingLastPathComponent())
        XCTAssertThrowsError(try ModelValidation.containedURL("link/outside", in: root))
        XCTAssertEqual(try ModelValidation.containedURL("voices/af_heart.safetensors", in: root).lastPathComponent, "af_heart.safetensors")
    }
    func testTensorOffsetsAndSchema() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".safetensors")
        defer { try? FileManager.default.removeItem(at: url) }
        func write(offset: Int) throws {
            let header = try JSONSerialization.data(withJSONObject: ["weight": ["dtype": "F32", "shape": [2], "data_offsets": [0, offset]]])
            var count = UInt64(header.count).littleEndian
            var data = withUnsafeBytes(of: &count) { Data($0) }
            data.append(header); data.append(Data(repeating: 0, count: 8)); try data.write(to: url)
        }
        try write(offset: 8)
        XCTAssertNoThrow(try ModelValidation.validateKokoro(url, schema: ["weight": [2]]))
        XCTAssertThrowsError(try ModelValidation.validateKokoro(url, schema: ["weight": [3]]))
        try write(offset: 12)
        XCTAssertThrowsError(try ModelValidation.tensors(url))
        try Data("version https://git-lfs.github.com/spec/v1".utf8).write(to: url)
        XCTAssertThrowsError(try ModelValidation.tensors(url))
    }
    func testChecksumsRejectCorruption() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("weights")
        try Data("hello".utf8).write(to: url)
        let file = ModelFile(path: "weights", bytes: 5, sha256: try ModelValidation.hash(url))
        XCTAssertNoThrow(try ModelValidation.verify(file, in: root))
        try Data("HELLO".utf8).write(to: url)
        XCTAssertThrowsError(try ModelValidation.verify(file, in: root))
    }
    func testSelectionLengthLimit() {
        XCTAssertThrowsError(try SelectionReader.checked(String(repeating: "a", count: 100_001)))
        XCTAssertThrowsError(try SelectionReader.checked(" \n "))
        XCTAssertEqual(try SelectionReader.checked(" Hi. "), "Hi.")
    }
}
