import XCTest
@testable import AESCryptKit

final class PasswordHintTests: XCTestCase {
    func testV2HintIsWrittenAndRead() throws {
        let files = try encryptedFile(Data("payload".utf8), format: .v2, hint: "pet name")
        defer { cleanUp(files.input, files.output) }

        let info = try AESCrypt.inspect(url: files.output)
        XCTAssertEqual(info.version, .v2)
        XCTAssertEqual(
            info.extensions.map(\.identifier),
            ["CREATED_BY", AESPasswordHint.extensionIdentifier]
        )
        XCTAssertEqual(info.passwordHint, "pet name")
    }

    func testV3HintIsWrittenAndRead() throws {
        let files = try encryptedFile(Data("payload".utf8), format: .v3, hint: "pet name")
        defer { cleanUp(files.input, files.output) }

        let info = try AESCrypt.inspect(url: files.output)
        XCTAssertEqual(info.version, .v3)
        XCTAssertEqual(
            info.extensions.map(\.identifier),
            ["CREATED_BY", AESPasswordHint.extensionIdentifier]
        )
        XCTAssertEqual(info.passwordHint, "pet name")
    }

    func testNoHintAddsNoExtension() throws {
        for format in [AESFormatVersion.v2, .v3] {
            let files = try encryptedFile(Data("payload".utf8), format: format, hint: nil)
            defer { cleanUp(files.input, files.output) }

            let info = try AESCrypt.inspect(url: files.output)
            XCTAssertEqual(info.extensions.map(\.identifier), ["CREATED_BY"])
            XCTAssertNil(info.passwordHint)
        }
    }

    func testWhitespaceOnlyHintIsOmitted() throws {
        let files = try encryptedFile(Data("payload".utf8), format: .v3, hint: " \n\t ")
        defer { cleanUp(files.input, files.output) }

        let info = try AESCrypt.inspect(url: files.output)
        XCTAssertEqual(info.extensions.map(\.identifier), ["CREATED_BY"])
        XCTAssertNil(info.passwordHint)
    }

    func testHintIsTrimmed() throws {
        let files = try encryptedFile(Data("payload".utf8), format: .v2, hint: "  garden  ")
        defer { cleanUp(files.input, files.output) }

        XCTAssertEqual(try AESCrypt.inspect(url: files.output).passwordHint, "garden")
    }

    func testUnicodeHintRoundTrips() throws {
        let plaintext = Data("unicode hint payload".utf8)
        for format in [AESFormatVersion.v2, .v3] {
            let files = try encryptedFile(plaintext, format: format, hint: "clé 🔐 世界")
            let decrypted = temporaryOutput("hint-decrypted-\(UUID().uuidString)")
            defer {
                cleanUp(files.input, files.output)
                try? FileManager.default.removeItem(at: decrypted)
            }

            XCTAssertEqual(try AESCrypt.inspect(url: files.output).passwordHint, "clé 🔐 世界")

            try AESCrypt.decrypt(url: files.output, to: decrypted, password: "apples")
            XCTAssertEqual(try Data(contentsOf: decrypted), plaintext)
        }
    }

    func testHintOnlyGrowsTheHeader() throws {
        let plaintext = Data("offset check payload".utf8)
        let base = try encryptedFile(plaintext, format: .v2, hint: nil)
        let hinted = try encryptedFile(plaintext, format: .v2, hint: "pet")
        let baseOut = temporaryOutput("hint-base-out-\(UUID().uuidString)")
        let hintedOut = temporaryOutput("hint-hinted-out-\(UUID().uuidString)")
        defer {
            cleanUp(base.input, base.output)
            cleanUp(hinted.input, hinted.output)
            try? FileManager.default.removeItem(at: baseOut)
            try? FileManager.default.removeItem(at: hintedOut)
        }

        let baseInfo = try AESCrypt.inspect(url: base.output)
        let hintedInfo = try AESCrypt.inspect(url: hinted.output)
        let blockLength = Int64(
            2 + AESPasswordHint.extensionIdentifier.utf8.count + 1 + "pet".utf8.count
        )

        XCTAssertEqual(hintedInfo.payloadOffset - baseInfo.payloadOffset, blockLength)
        XCTAssertEqual(hintedInfo.ciphertextOffset - baseInfo.ciphertextOffset, blockLength)
        XCTAssertEqual(hintedInfo.trailerLength, baseInfo.trailerLength)
        XCTAssertEqual(hintedInfo.ciphertextLength, baseInfo.ciphertextLength)

        try AESCrypt.decrypt(url: base.output, to: baseOut, password: "apples")
        try AESCrypt.decrypt(url: hinted.output, to: hintedOut, password: "apples")
        XCTAssertEqual(try Data(contentsOf: baseOut), plaintext)
        XCTAssertEqual(try Data(contentsOf: hintedOut), plaintext)
    }

    func testOversizedHintFailsBeforeCreatingOutput() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aesopen-hint-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("plain")
        let output = directory.appendingPathComponent("plain.aes")
        try Data("payload".utf8).write(to: input)

        let hugeHint = String(repeating: "a", count: 70_000)
        XCTAssertThrowsError(
            try AESCrypt.encrypt(
                url: input,
                to: output,
                password: "apples",
                format: .v3,
                hint: hugeHint
            )
        ) { error in
            XCTAssertEqual(error as? AESCryptError, .corrupt("extension is too large"))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(leftovers, ["plain"])
    }

    func testBatchWritesHintToEveryFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aesopen-hint-batch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let urls = try (0..<3).map { index -> URL in
            let url = directory.appendingPathComponent("file-\(index).txt")
            try Data("batch file \(index)\n".utf8).write(to: url)
            return url
        }

        let plan = try AESCryptBatch.plan(urls: urls, mode: .encrypt, outputPolicy: .unique)
        let results = AESCryptBatch.run(
            plan: plan,
            password: "apples",
            format: .v3,
            hint: "batch hint"
        )

        XCTAssertEqual(results.count, 3)
        for result in results {
            XCTAssertNil(result.failure)
            XCTAssertEqual(
                try AESCrypt.inspect(url: result.item.output).passwordHint,
                "batch hint"
            )
        }
    }

    func testReaderPicksTheHintAmongOtherExtensions() {
        let info = makeInfo([
            AESExtension(identifier: "urn:uuid:not-ours", value: Data("nope".utf8)),
            AESExtension(identifier: AESPasswordHint.extensionIdentifier, value: Data("hello".utf8)),
            AESExtension(identifier: "", value: Data("container".utf8)),
        ])

        XCTAssertEqual(info.passwordHint, "hello")
    }

    func testReaderIgnoresInvalidAndEmptyHints() {
        XCTAssertNil(
            makeInfo([
                AESExtension(identifier: AESPasswordHint.extensionIdentifier, value: Data([0xFF, 0xFE]))
            ]).passwordHint
        )
        XCTAssertNil(
            makeInfo([
                AESExtension(identifier: AESPasswordHint.extensionIdentifier, value: Data("  \n ".utf8))
            ]).passwordHint
        )
        XCTAssertNil(
            makeInfo([
                AESExtension(identifier: AESPasswordHint.extensionIdentifier, value: Data())
            ]).passwordHint
        )
    }

    func testFixtureContainerExtensionHasNoHint() throws {
        let info = try AESCrypt.inspect(url: try fixture("v2-hello"))
        XCTAssertNil(info.passwordHint)
    }

    private func encryptedFile(
        _ plaintext: Data,
        format: AESFormatVersion,
        hint: String?,
        password: String = "apples"
    ) throws -> (input: URL, output: URL) {
        let input = temporaryOutput("hint-in-\(UUID().uuidString)")
        let output = temporaryOutput("hint-out-\(UUID().uuidString).aes")
        try plaintext.write(to: input)
        try AESCrypt.encrypt(
            url: input,
            to: output,
            password: password,
            format: format,
            hint: hint
        )
        return (input, output)
    }

    private func makeInfo(_ extensions: [AESExtension]) -> AESFileInfo {
        AESFileInfo(
            version: .v3,
            kdfIterations: 600_000,
            extensions: extensions,
            fileSize: 0,
            ciphertextLength: 0,
            payloadOffset: 0,
            ciphertextOffset: 0,
            trailerLength: 32
        )
    }

    private func cleanUp(_ urls: URL...) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
