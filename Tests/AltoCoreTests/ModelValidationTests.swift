import XCTest
@testable import AltoCore

final class ModelValidationTests: XCTestCase {
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
