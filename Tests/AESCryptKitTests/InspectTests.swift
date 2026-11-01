import XCTest
@testable import AESCryptKit

final class InspectTests: XCTestCase {
    func testReadsV2HeaderAndExtensions() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "v2-hello", withExtension: "aes", subdirectory: "Fixtures")
        )

        let info = try AESCrypt.inspect(url: url)

        XCTAssertEqual(info.version, .v2)
        XCTAssertNil(info.kdfIterations)
        XCTAssertEqual(info.fileSize, 308)
        XCTAssertEqual(info.ciphertextLength, 16)
        XCTAssertEqual(info.extensions.map(\.identifier), ["CREATED_BY", ""])
        XCTAssertEqual(info.extensions[0].value, Data("aescrypt 3.14".utf8))
    }

    func testRejectsNonzeroReservedByteForVersionsOneThroughThree() throws {
        for version in 1...3 {
            let bytes = try validStream(version: version)
            let mutated = try mutatedReservedByte(bytes)
            let input = temporaryOutput("reserved-v\(version)-\(UUID().uuidString).aes")
            try mutated.write(to: input)
            defer { try? FileManager.default.removeItem(at: input) }

            XCTAssertThrowsError(try AESCrypt.inspect(url: input), "v\(version)") { error in
                XCTAssertEqual(error as? AESCryptError, .corrupt("reserved header byte is nonzero"))
            }
        }
    }

    func testRejectsNonzeroReservedByteBeforeDecryptAndWritesNothing() throws {
        for version in [2, 3] {
            let bytes = try validStream(version: version)
            let mutated = try mutatedReservedByte(bytes)
            let input = temporaryOutput("reserved-decrypt-v\(version)-\(UUID().uuidString).aes")
            let output = temporaryOutput("reserved-decrypt-out-\(UUID().uuidString)")
            try mutated.write(to: input)
            defer {
                try? FileManager.default.removeItem(at: input)
                try? FileManager.default.removeItem(at: output)
            }

            XCTAssertThrowsError(try AESCrypt.decrypt(url: input, to: output, password: "apples")) { error in
                XCTAssertEqual(error as? AESCryptError, .corrupt("reserved header byte is nonzero"))
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
    }

    func testV0ModuloByteRemainsValidAndDecrypts() throws {
        let vectorsURL = try XCTUnwrap(
            Bundle.module.url(forResource: "v0", withExtension: "json", subdirectory: "Fixtures/vectors")
        )
        let vectors = try JSONSerialization.jsonObject(with: Data(contentsOf: vectorsURL)) as! [[String: String]]
        let bytes = try XCTUnwrap(vectors.first { $0["plaintext"] == "0" }?["ciphertext_hex"]).hexData
        XCTAssertNotEqual(bytes[4], 0)

        let input = temporaryOutput("v0-modulo-\(UUID().uuidString).aes")
        let output = temporaryOutput("v0-modulo-out-\(UUID().uuidString)")
        try bytes.write(to: input)
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
        }

        let info = try AESCrypt.inspect(url: input)
        XCTAssertEqual(info.version, .v0)
        try AESCrypt.decrypt(url: input, to: output, password: "Hello")
        XCTAssertEqual(try Data(contentsOf: output), Data("0".utf8))
    }

    private func validStream(version: Int) throws -> Data {
        switch version {
        case 1:
            let url = try XCTUnwrap(
                Bundle.module.url(forResource: "v1", withExtension: "json", subdirectory: "Fixtures/vectors")
            )
            let vectors = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: String]]
            let hex = try XCTUnwrap(vectors.first?["ciphertext_hex"])
            return hex.hexData
        case 2:
            return try Data(contentsOf: fixture("v2-hello"))
        case 3:
            return try Data(contentsOf: fixture("v3-test-data"))
        default:
            throw XCTSkip("Only versions 1 through 3 have a reserved header byte")
        }
    }

    private func mutatedReservedByte(_ bytes: Data) throws -> Data {
        guard bytes.count > 4 else { throw AESCryptError.truncated }
        var copy = bytes
        copy[4] = 1
        return copy
    }
}

private extension String {
    var hexData: Data {
        var bytes = Data()
        var index = startIndex
        while index < endIndex {
            let next = self.index(index, offsetBy: 2)
            bytes.append(UInt8(self[index..<next], radix: 16)!)
            index = next
        }
        return bytes
    }
}
