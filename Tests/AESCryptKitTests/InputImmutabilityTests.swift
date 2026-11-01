import Foundation
import XCTest
@testable import AESCryptKit

/// The input file must never be written to, truncated, renamed, or relinked.
/// These tests snapshot the bytes and inode metadata before and after every
/// operation, including failures and cancellations.
final class InputImmutabilityTests: XCTestCase {
    func testEncryptV2LeavesInputUnchanged() throws {
        try assertEncryptLeavesInputUnchanged(format: .v2)
    }

    func testEncryptV3LeavesInputUnchanged() throws {
        try assertEncryptLeavesInputUnchanged(format: .v3)
    }

    func testDecryptV2LeavesInputUnchanged() throws {
        try assertDecryptLeavesInputUnchanged(fixtureName: "v2-hello")
    }

    func testDecryptV3LeavesInputUnchanged() throws {
        try assertDecryptLeavesInputUnchanged(fixtureName: "v3-test-data")
    }

    func testWrongPasswordLeavesInputUnchanged() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("secret.aes")
        try FileManager.default.copyItem(at: try fixture("v2-hello"), to: input)
        let output = directory.appendingPathComponent("secret.txt")
        let before = try snapshot(input)

        XCTAssertThrowsError(try AESCrypt.decrypt(url: input, to: output, password: "wrong")) { error in
            XCTAssertEqual(error as? AESCryptError, .wrongPassword)
        }

        XCTAssertEqual(try snapshot(input), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testTamperedFileLeavesInputUnchanged() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("tampered.aes")
        var bytes = try Data(contentsOf: try fixture("v2-hello"))
        let info = try AESCrypt.inspect(url: try fixture("v2-hello"))
        bytes[Int(info.ciphertextOffset) + 1] ^= 0xFF
        try bytes.write(to: input)
        let output = directory.appendingPathComponent("tampered.txt")
        let before = try snapshot(input)

        XCTAssertThrowsError(try AESCrypt.decrypt(url: input, to: output, password: "apples")) { error in
            XCTAssertEqual(error as? AESCryptError, .authenticationFailed)
        }

        XCTAssertEqual(try snapshot(input), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testCancelledEncryptLeavesInputUnchanged() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("large.bin")
        try Data(repeating: 0x5A, count: 1024 * 1024).write(to: input)
        let output = directory.appendingPathComponent("large.bin.aes")
        let before = try snapshot(input)
        var checks = 0

        XCTAssertThrowsError(
            try AESCrypt.encrypt(
                url: input,
                to: output,
                password: "apples",
                format: .v3,
                isCancelled: {
                    checks += 1
                    return checks > 3
                }
            )
        ) { error in
            XCTAssertEqual(error as? AESCryptError, .cancelled)
        }

        XCTAssertEqual(try snapshot(input), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(),
            ["large.bin"]
        )
    }

    func testCancelledDecryptLeavesInputUnchanged() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let plain = directory.appendingPathComponent("large.bin")
        let encrypted = directory.appendingPathComponent("large.bin.aes")
        let output = directory.appendingPathComponent("large.out")
        try Data(repeating: 0x5A, count: 1024 * 1024).write(to: plain)
        try AESCrypt.encrypt(url: plain, to: encrypted, password: "apples", format: .v2)
        let before = try snapshot(encrypted)
        var checks = 0

        XCTAssertThrowsError(
            try AESCrypt.decrypt(
                url: encrypted,
                to: output,
                password: "apples",
                isCancelled: {
                    checks += 1
                    return checks > 3
                }
            )
        ) { error in
            XCTAssertEqual(error as? AESCryptError, .cancelled)
        }

        XCTAssertEqual(try snapshot(encrypted), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(),
            ["large.bin", "large.bin.aes"]
        )
    }

    func testEncryptRejectsOutputThatIsTheInput() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("notes.txt")
        try Data("do not replace me\n".utf8).write(to: input)
        let before = try snapshot(input)

        XCTAssertThrowsError(try AESCrypt.encrypt(url: input, to: input, password: "apples")) { error in
            XCTAssertEqual(error as? AESCryptError, .sameFile)
        }

        XCTAssertEqual(try snapshot(input), before)
    }

    func testDecryptRejectsOutputThatIsTheInput() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("secret.aes")
        try FileManager.default.copyItem(at: try fixture("v2-hello"), to: input)
        let before = try snapshot(input)

        XCTAssertThrowsError(try AESCrypt.decrypt(url: input, to: input, password: "apples")) { error in
            XCTAssertEqual(error as? AESCryptError, .sameFile)
        }

        XCTAssertEqual(try snapshot(input), before)
    }

    func testEncryptRejectsHardLinkedOutput() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("notes.txt")
        let output = directory.appendingPathComponent("notes-link.aes")
        try Data("do not replace me\n".utf8).write(to: input)
        try FileManager.default.linkItem(at: input, to: output)
        let before = try snapshot(input)

        XCTAssertThrowsError(try AESCrypt.encrypt(url: input, to: output, password: "apples")) { error in
            XCTAssertEqual(error as? AESCryptError, .sameFile)
        }

        XCTAssertEqual(try snapshot(input), before)
        XCTAssertEqual(try snapshot(output), before)
    }

    func testDecryptRejectsSymbolicLinkToInput() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("secret.aes")
        let output = directory.appendingPathComponent("secret-link.txt")
        try FileManager.default.copyItem(at: try fixture("v2-hello"), to: input)
        try FileManager.default.createSymbolicLink(at: output, withDestinationURL: input)
        let before = try snapshot(input)

        XCTAssertThrowsError(try AESCrypt.decrypt(url: input, to: output, password: "apples")) { error in
            XCTAssertEqual(error as? AESCryptError, .sameFile)
        }

        XCTAssertEqual(try snapshot(input), before)
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: output.path),
            input.path
        )
    }

    func testTemporaryFileCreationNeverTruncatesAnExistingFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let existing = directory.appendingPathComponent(".aesopen-known.tmp")
        try Data("keep this\n".utf8).write(to: existing)
        let before = try snapshot(existing)

        XCTAssertThrowsError(
            try TemporaryFile.create(
                nextTo: directory.appendingPathComponent("out.aes"),
                name: ".aesopen-known.tmp"
            )
        )

        XCTAssertEqual(try snapshot(existing), before)
    }

    private func assertEncryptLeavesInputUnchanged(format: AESFormatVersion) throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("notes.txt")
        let output = directory.appendingPathComponent("notes.txt.aes")
        try Data("The input must survive encryption byte for byte.\n".utf8).write(to: input)
        let before = try snapshot(input)

        try AESCrypt.encrypt(url: input, to: output, password: "apples", format: format)

        XCTAssertEqual(try snapshot(input), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
    }

    private func assertDecryptLeavesInputUnchanged(fixtureName: String) throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("\(fixtureName).aes")
        let output = directory.appendingPathComponent("\(fixtureName).txt")
        try FileManager.default.copyItem(at: try fixture(fixtureName), to: input)
        let before = try snapshot(input)

        try AESCrypt.decrypt(url: input, to: output, password: "apples")

        XCTAssertEqual(try snapshot(input), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aesopen-immutability-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
