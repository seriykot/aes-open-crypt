import XCTest
@testable import AESCryptKit

final class EncryptTests: XCTestCase {
    func testV2RoundTrip() throws {
        let plaintext = Data("The quick brown fox jumps over the lazy dog.\n".utf8)
        XCTAssertEqual(try roundTrip(plaintext, format: .v2), plaintext)
    }

    func testV2EmptyFileRoundTrip() throws {
        XCTAssertEqual(try roundTrip(Data(), format: .v2), Data())
    }

    func testV2ExactBlockRoundTrip() throws {
        let plaintext = Data("0123456789abcdef".utf8)
        XCTAssertEqual(try roundTrip(plaintext, format: .v2), plaintext)
    }

    func testV3RoundTrip() throws {
        let plaintext = Data("The quick brown fox jumps over the lazy dog.\n".utf8)
        XCTAssertEqual(try roundTrip(plaintext, format: .v3), plaintext)
    }

    func testV3EmptyFileRoundTrip() throws {
        XCTAssertEqual(try roundTrip(Data(), format: .v3), Data())
    }

    func testV3RecordsIterationCount() throws {
        let input = temporaryOutput("plain")
        let encrypted = temporaryOutput("plain.aes")
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: encrypted)
        }
        try Data("hello".utf8).write(to: input)

        try AESCrypt.encrypt(url: input, to: encrypted, password: "apples", format: .v3, iterations: 123_456)

        let info = try AESCrypt.inspect(url: encrypted)
        XCTAssertEqual(info.version, .v3)
        XCTAssertEqual(info.kdfIterations, 123_456)
        XCTAssertEqual(info.extensions.first?.identifier, "CREATED_BY")
    }

    func testV2Header() throws {
        let input = temporaryOutput("plain")
        let encrypted = temporaryOutput("plain.aes")
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: encrypted)
        }
        try Data("hello".utf8).write(to: input)

        try AESCrypt.encrypt(url: input, to: encrypted, password: "apples", format: .v2)

        let header = try Data(contentsOf: encrypted).prefix(5)
        XCTAssertEqual(Array(header), [0x41, 0x45, 0x53, 0x02, 0x00])
    }

    func testLargeFileRoundTrip() throws {
        var generator = SystemRandomNumberGenerator()
        let plaintext = Data((0..<(1024 * 1024)).map { _ in UInt8.random(in: 0...255, using: &generator) })
        XCTAssertEqual(try roundTrip(plaintext, format: .v2), plaintext)
    }

    func testBundledAESCryptCLIReadsOurV2Output() throws {
        let cli = "/Applications/AESCrypt.app/Contents/MacOS/aescrypt"
        try XCTSkipUnless(FileManager.default.fileExists(atPath: cli), "AES Crypt 3.14 CLI not installed")

        let plaintext = Data("Written by aes-open-crypt, read by AES Crypt 3.14.\n".utf8)
        let input = temporaryOutput("plain.txt")
        let encrypted = temporaryOutput("plain.txt.aes")
        let decrypted = temporaryOutput("decrypted.txt")
        defer {
            for url in [input, encrypted, decrypted] {
                try? FileManager.default.removeItem(at: url)
            }
        }
        try plaintext.write(to: input)
        try AESCrypt.encrypt(url: input, to: encrypted, password: "apples", format: .v2)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cli)
        process.arguments = ["-d", "-p", "apples", "-o", decrypted.path, encrypted.path]
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(try Data(contentsOf: decrypted), plaintext)
    }

    func testRefusesToOverwriteExistingOutput() throws {
        let input = temporaryOutput("plain")
        let encrypted = temporaryOutput("plain.aes")
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: encrypted)
        }
        try Data("hello".utf8).write(to: input)
        try Data("keep me".utf8).write(to: encrypted)

        XCTAssertThrowsError(try AESCrypt.encrypt(url: input, to: encrypted, password: "apples")) { error in
            XCTAssertEqual(error as? AESCryptError, .outputExists(encrypted.path))
        }
        XCTAssertEqual(try Data(contentsOf: encrypted), Data("keep me".utf8))
    }

    func testCancelRemovesTemporaryFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aesopen-cancel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("plain")
        let encrypted = directory.appendingPathComponent("plain.aes")
        try Data(repeating: 7, count: 1024 * 1024).write(to: input)

        XCTAssertThrowsError(
            try AESCrypt.encrypt(
                url: input,
                to: encrypted,
                password: "apples",
                format: .v3,
                isCancelled: { true }
            )
        ) { error in
            XCTAssertEqual(error as? AESCryptError, .cancelled)
        }

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(leftovers.sorted(), ["plain"])
    }

    private func roundTrip(_ plaintext: Data, format: AESFormatVersion) throws -> Data {
        let input = temporaryOutput("in")
        let encrypted = temporaryOutput("in.aes")
        let decrypted = temporaryOutput("out")
        defer {
            for url in [input, encrypted, decrypted] {
                try? FileManager.default.removeItem(at: url)
            }
        }
        try plaintext.write(to: input)
        try AESCrypt.encrypt(url: input, to: encrypted, password: "apples", format: format)
        try AESCrypt.decrypt(url: encrypted, to: decrypted, password: "apples")
        return try Data(contentsOf: decrypted)
    }
}
