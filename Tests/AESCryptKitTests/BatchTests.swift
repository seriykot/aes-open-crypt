import CryptoKit
import Foundation
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

    func testRunProcessesAllFiles() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let plaintexts = [
            "first file\n",
            "second file with more text\n",
            "",
        ]
        var inputs: [URL] = []
        for (index, text) in plaintexts.enumerated() {
            let url = directory.appendingPathComponent("file-\(index).txt")
            try Data(text.utf8).write(to: url)
            inputs.append(url)
        }

        let plan = try AESCryptBatch.plan(urls: inputs, mode: .encrypt)
        let results = AESCryptBatch.run(plan: plan, password: "apples")

        XCTAssertEqual(results.count, 3)
        for (index, result) in results.enumerated() {
            XCTAssertNil(result.failure, "file \(index) failed: \(String(describing: result.failure))")
            XCTAssertTrue(FileManager.default.fileExists(atPath: result.item.output.path))

            let decrypted = directory.appendingPathComponent("decrypted-\(index).txt")
            try AESCrypt.decrypt(url: result.item.output, to: decrypted, password: "apples")
            XCTAssertEqual(try Data(contentsOf: decrypted), Data(plaintexts[index].utf8))
        }
    }

    func testRunContinuesAfterWrongPassword() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let passwords = ["apples", "apples", "pears"]
        var encrypted: [URL] = []
        for (index, password) in passwords.enumerated() {
            let plain = directory.appendingPathComponent("secret-\(index).txt")
            let aes = directory.appendingPathComponent("secret-\(index).aes")
            try Data("secret \(index)\n".utf8).write(to: plain)
            try AESCrypt.encrypt(url: plain, to: aes, password: password)
            encrypted.append(aes)
        }

        let plan = try AESCryptBatch.plan(urls: encrypted)
        let results = AESCryptBatch.run(plan: plan, password: "apples")

        XCTAssertEqual(results.count, 3)
        XCTAssertNil(results[0].failure)
        XCTAssertNil(results[1].failure)
        XCTAssertEqual(results[2].failure, .crypto(.wrongPassword))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: results[2].item.output.path),
            "a failed decryption must not leave an output file"
        )
    }

    func testRunReportsPlanningIssuesWithoutStopping() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let broken = directory.appendingPathComponent("broken.aes")
        let good = directory.appendingPathComponent("good.txt")
        try Data("this is not an AES file".utf8).write(to: broken)
        try Data("good file\n".utf8).write(to: good)

        let plan = try AESCryptBatch.plan(urls: [broken, good])
        let results = AESCryptBatch.run(plan: plan, password: "apples")

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].failure, .issue(.invalidAESFile))
        XCTAssertNil(results[1].failure)
        XCTAssertTrue(FileManager.default.fileExists(atPath: good.path + ".aes"))
    }

    func testRunCancelsRemainingItems() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // One byte over a whole number of 64 KiB buffers: the 1.0 progress
        // event then lands on the final chunk, after which encrypt returns
        // instead of checking cancellation again.
        let payload = Data(repeating: 0x41, count: 512 * 1024 + 1)
        var inputs: [URL] = []
        for index in 0..<3 {
            let url = directory.appendingPathComponent("big-\(index).txt")
            try payload.write(to: url)
            inputs.append(url)
        }

        let plan = try AESCryptBatch.plan(urls: inputs, mode: .encrypt)

        var cancelled = false
        let results = AESCryptBatch.run(
            plan: plan,
            password: "apples",
            progress: { progress in
                if progress.itemIndex == 0, progress.itemFraction >= 1 {
                    cancelled = true
                }
            },
            isCancelled: { cancelled }
        )

        XCTAssertEqual(results.count, 3)
        XCTAssertNil(results[0].failure)
        XCTAssertTrue(FileManager.default.fileExists(atPath: results[0].item.output.path))
        XCTAssertEqual(results[1].failure, .crypto(.cancelled))
        XCTAssertEqual(results[2].failure, .crypto(.cancelled))
        XCTAssertFalse(FileManager.default.fileExists(atPath: results[1].item.output.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: results[2].item.output.path))
    }

    func testRunLeavesEveryInputUnchanged() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let plain = directory.appendingPathComponent("plain.txt")
        let encryptedInput = directory.appendingPathComponent("secret.aes")
        try Data("The input must survive a batch byte for byte.\n".utf8).write(to: plain)
        try AESCrypt.encrypt(
            url: plain,
            to: directory.appendingPathComponent("temporary.aes"),
            password: "apples"
        )
        try FileManager.default.moveItem(
            at: directory.appendingPathComponent("temporary.aes"),
            to: encryptedInput
        )

        let plainBefore = try inputStamp(plain)
        let encryptedBefore = try inputStamp(encryptedInput)

        let plan = try AESCryptBatch.plan(urls: [plain, encryptedInput])
        let results = AESCryptBatch.run(plan: plan, password: "apples")

        XCTAssertEqual(results.count, 2)
        XCTAssertNil(results[0].failure)
        XCTAssertNil(results[1].failure)
        XCTAssertEqual(try inputStamp(plain), plainBefore)
        XCTAssertEqual(try inputStamp(encryptedInput), encryptedBefore)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aesopen-batch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private struct InputStamp: Equatable {
    let digest: String
    let size: Int64
    let permissions: UInt16
    let fileNumber: UInt64
    let modificationDate: Date
    let creationDate: Date
}

private func inputStamp(_ url: URL) throws -> InputStamp {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let contents = try Data(contentsOf: url)

    func number(_ key: FileAttributeKey) -> NSNumber? {
        attributes[key] as? NSNumber
    }

    return InputStamp(
        digest: SHA256.hash(data: contents).map { String(format: "%02x", $0) }.joined(),
        size: number(.size)?.int64Value ?? -1,
        permissions: number(.posixPermissions)?.uint16Value ?? 0,
        fileNumber: number(.systemFileNumber)?.uint64Value ?? 0,
        modificationDate: attributes[.modificationDate] as? Date ?? .distantPast,
        creationDate: attributes[.creationDate] as? Date ?? .distantPast
    )
}
