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
        try assertTamperedCiphertextFailsAuthenticationAndWritesNothing(fixtureName: "v2-hello")
    }

    func testTamperedV3CiphertextFailsAuthenticationAndWritesNothing() throws {
        try assertTamperedCiphertextFailsAuthenticationAndWritesNothing(fixtureName: "v3-hello")
    }

    func testV2ModuloByteIsUnauthenticatedAndDoesNotModifySource() throws {
        let fixtureURL = try fixture("v2-hello")
        let sourceBefore = try Data(contentsOf: fixtureURL)
        let input = temporaryOutput("v2-modulo-copy-\(UUID().uuidString).aes")
        let output = temporaryOutput("v2-modulo-out-\(UUID().uuidString)")
        try sourceBefore.write(to: input)
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
        }

        let info = try AESCrypt.inspect(url: input)
        let original = try Data(contentsOf: input)
        let moduloOffset = Int(info.ciphertextOffset + info.ciphertextLength)
        XCTAssertEqual(original[moduloOffset] & 0x0F, 14)
        var mutated = original
        mutated[moduloOffset] = 15
        try mutated.write(to: input)

        try AESCrypt.decrypt(url: input, to: output, password: "apples")

        let originalPlaintext = Data("Hello, World!\n".utf8)
        let decrypted = try Data(contentsOf: output)
        XCTAssertEqual(decrypted.count, originalPlaintext.count + 1)
        XCTAssertEqual(decrypted.prefix(originalPlaintext.count), originalPlaintext)
        XCTAssertEqual(try Data(contentsOf: input), mutated)
        XCTAssertEqual(try Data(contentsOf: fixtureURL), sourceBefore)
    }

    private func assertTamperedCiphertextFailsAuthenticationAndWritesNothing(
        fixtureName: String
    ) throws {
        let input = try fixture(fixtureName)
        let info = try AESCrypt.inspect(url: input)
        var bytes = try Data(contentsOf: input)
        let ciphertextOffset = Int(info.ciphertextOffset)
        bytes[ciphertextOffset + 1] ^= 0xFF
        let tampered = temporaryOutput("tampered-\(fixtureName)-\(UUID().uuidString).aes")
        try bytes.write(to: tampered)

        let output = temporaryOutput("tampered-out-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: tampered)
            try? FileManager.default.removeItem(at: output)
        }

        XCTAssertThrowsError(try AESCrypt.decrypt(url: tampered, to: output, password: "apples")) { error in
            XCTAssertEqual(error as? AESCryptError, .authenticationFailed)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: output.deletingLastPathComponent()
                .appendingPathComponent(".aesopen-\(UUID().uuidString).tmp").path)
        )
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
