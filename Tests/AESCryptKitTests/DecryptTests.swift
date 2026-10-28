import XCTest
@testable import AESCryptKit

final class DecryptTests: XCTestCase {
    func testDecryptsV2Hello() throws {
        let output = try decrypt("v2-hello", password: "apples")
        XCTAssertEqual(try Data(contentsOf: output), Data("Hello, World!\n".utf8))
    }

    func testDecryptsV2EmptyFile() throws {
        let output = try decrypt("v2-empty", password: "apples")
        XCTAssertEqual(try Data(contentsOf: output), Data())
    }

    func testDecryptsV2OneByte() throws {
        let output = try decrypt("v2-one", password: "apples")
        XCTAssertEqual(try Data(contentsOf: output), Data("A".utf8))
    }

    func testDecryptsV2ExactBlock() throws {
        let output = try decrypt("v2-16", password: "apples")
        XCTAssertEqual(try Data(contentsOf: output), Data("0123456789abcdef".utf8))
    }

    func testDecryptsV2WithNonASCIIPassword() throws {
        let output = try decrypt("v2-unicode", password: "pässwörd€")
        XCTAssertEqual(
            try Data(contentsOf: output),
            Data("The quick brown fox jumps over the lazy dog.\n".utf8)
        )
    }

    func testWrongPasswordThrowsAndWritesNothing() throws {
        let input = try fixture("v2-hello")
        let output = temporaryOutput()
        defer { try? FileManager.default.removeItem(at: output) }

        XCTAssertThrowsError(try AESCrypt.decrypt(url: input, to: output, password: "wrong")) { error in
            XCTAssertEqual(error as? AESCryptError, .wrongPassword)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testTamperedCiphertextFailsAuthenticationAndWritesNothing() throws {
        let input = try fixture("v2-hello")
        let info = try AESCrypt.inspect(url: input)
        var bytes = try Data(contentsOf: input)
        let ciphertextOffset = Int(info.ciphertextOffset)
        bytes[ciphertextOffset + 1] ^= 0xFF
        let tampered = temporaryOutput()
        try bytes.write(to: tampered)

        let output = temporaryOutput()
        defer {
            try? FileManager.default.removeItem(at: tampered)
            try? FileManager.default.removeItem(at: output)
        }

        XCTAssertThrowsError(try AESCrypt.decrypt(url: tampered, to: output, password: "apples")) { error in
            XCTAssertEqual(error as? AESCryptError, .authenticationFailed)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testDecryptsOfficialV3Sample() throws {
        let output = try decrypt("v3-hello", password: "apples")
        XCTAssertEqual(try Data(contentsOf: output), Data("Hello, World!\n".utf8))
    }

    private func decrypt(_ name: String, password: String) throws -> URL {
        let input = try fixture(name)
        let output = temporaryOutput()
        try AESCrypt.decrypt(url: input, to: output, password: password)
        return output
    }
}
