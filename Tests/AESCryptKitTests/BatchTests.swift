import XCTest
@testable import AESCryptKit

final class BatchTests: XCTestCase {
    func testPlanRejectsMoreThanTenFiles() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let urls = try (0..<11).map { index in
            let url = directory.appendingPathComponent("file-\(index).txt")
            try Data("file \(index)".utf8).write(to: url)
            return url
        }

        XCTAssertThrowsError(try AESCryptBatch.plan(urls: urls)) { error in
            XCTAssertEqual(error as? AESCryptBatchIssue, .tooManyFiles(10))
        }
    }

    func testPlanDeduplicatesHardLinksAndSymlinks() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = directory.appendingPathComponent("original.txt")
        let hardLink = directory.appendingPathComponent("hard-link.txt")
        let symlink = directory.appendingPathComponent("symlink.txt")
        try Data("same file".utf8).write(to: original)
        try FileManager.default.linkItem(at: original, to: hardLink)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: original)

        let plan = try AESCryptBatch.plan(urls: [original, hardLink, symlink])

        XCTAssertEqual(plan.items.count, 1)
        XCTAssertEqual(plan.items.first?.input.lastPathComponent, "original.txt")
        XCTAssertEqual(plan.items.first?.mode, .encrypt)
    }

    func testPlanAutoDetectsEncryptAndDecrypt() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let plain = directory.appendingPathComponent("notes.txt")
        let encrypted = directory.appendingPathComponent("secret.aes")
        try Data("plain".utf8).write(to: plain)
        try FileManager.default.copyItem(at: try fixture("v2-hello"), to: encrypted)

        let plan = try AESCryptBatch.plan(urls: [plain, encrypted])

        XCTAssertEqual(plan.items.count, 2)
        XCTAssertEqual(plan.items[0].mode, .encrypt)
        XCTAssertEqual(plan.items[1].mode, .decrypt)
        XCTAssertEqual(plan.items[0].output.lastPathComponent, "notes.txt.aes")
        XCTAssertEqual(plan.items[1].output.lastPathComponent, "secret")
    }

    func testPlanRejectsInvalidAESFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let broken = directory.appendingPathComponent("broken.aes")
        try Data("this is not an AES file".utf8).write(to: broken)

        let plan = try AESCryptBatch.plan(urls: [broken])

        XCTAssertEqual(plan.items.count, 1)
        XCTAssertEqual(plan.items.first?.issue, .invalidAESFile)
    }

    func testPlanForcedEncryptRejectsEncryptedFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let encrypted = directory.appendingPathComponent("secret.aes")
        try FileManager.default.copyItem(at: try fixture("v2-hello"), to: encrypted)

        let plan = try AESCryptBatch.plan(urls: [encrypted], mode: .encrypt)

        XCTAssertEqual(plan.items.first?.issue, .alreadyEncrypted)
    }

    func testPlanForcedDecryptRejectsPlainFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let plain = directory.appendingPathComponent("notes.txt")
        try Data("plain".utf8).write(to: plain)

        let plan = try AESCryptBatch.plan(urls: [plain], mode: .decrypt)

        XCTAssertEqual(plan.items.first?.issue, .notEncrypted)
    }

    func testPlanPicksUniqueOutputNames() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("notes.txt")
        let existing = directory.appendingPathComponent("notes.txt.aes")
        try Data("plain".utf8).write(to: input)
        try Data("existing".utf8).write(to: existing)

        let plan = try AESCryptBatch.plan(urls: [input])

        XCTAssertEqual(plan.items.first?.output.lastPathComponent, "notes.txt (1).aes")
        XCTAssertNil(plan.items.first?.issue)
    }

    func testPlanStrictPolicyRejectsExistingOutput() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("notes.txt")
        let existing = directory.appendingPathComponent("notes.txt.aes")
        try Data("plain".utf8).write(to: input)
        try Data("existing".utf8).write(to: existing)

        let plan = try AESCryptBatch.plan(urls: [input], outputPolicy: .strict)

        XCTAssertEqual(plan.items.first?.issue, .outputExists(existing.path))
    }

    func testPlanRejectsSameFileOutput() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("secret.aes")
        let output = directory.appendingPathComponent("secret")
        try FileManager.default.copyItem(at: try fixture("v2-hello"), to: input)
        try FileManager.default.linkItem(at: input, to: output)

        let plan = try AESCryptBatch.plan(urls: [input], mode: .decrypt)

        XCTAssertEqual(plan.items.first?.issue, .sameFile)
    }

    func testPlanCaseInsensitiveCollision() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let values = try directory.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
        try XCTSkipIf(
            values.volumeSupportsCaseSensitiveNames == true,
            "requires a case-insensitive volume"
        )

        let input = directory.appendingPathComponent("Report.txt")
        let existing = directory.appendingPathComponent("report.txt.aes")
        try Data("plain".utf8).write(to: input)
        try Data("existing".utf8).write(to: existing)

        let plan = try AESCryptBatch.plan(urls: [input])

        XCTAssertEqual(plan.items.first?.output.lastPathComponent, "Report.txt (1).aes")
        XCTAssertNil(plan.items.first?.issue)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aesopen-batch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
