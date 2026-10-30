import AESCryptKit
import Foundation
import XCTest
@testable import AESOpenCore

@MainActor
final class BatchModelTests: XCTestCase {
    func testAddThreeFilesCreatesRows() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let urls = try (0..<3).map { index in
            let url = directory.appendingPathComponent("file-\(index).txt")
            try Data("file \(index)\n".utf8).write(to: url)
            return url
        }

        let model = BatchModel()
        model.add(urls: urls, preferredMode: nil)

        XCTAssertEqual(model.rows.count, 3)
        XCTAssertEqual(model.phase, .ready)
    }

    func testAddRejectsElevenFiles() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let urls = try (0..<11).map { index in
            let url = directory.appendingPathComponent("file-\(index).txt")
            try Data("file \(index)\n".utf8).write(to: url)
            return url
        }

        let model = BatchModel()
        model.add(urls: urls, preferredMode: nil)

        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertTrue(model.errorMessage?.contains("10") == true)
    }

    func testAddDeduplicatesRepeatedURL() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("once.txt")
        try Data("once\n".utf8).write(to: url)

        let model = BatchModel()
        model.add(urls: [url, url], preferredMode: nil)

        XCTAssertEqual(model.rows.count, 1)
    }

    func testModeSwitchReplansRows() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let plain = directory.appendingPathComponent("notes.txt")
        try Data("plain\n".utf8).write(to: plain)
        let encrypted = try makeEncryptedFile(in: directory, name: "secret", password: "apples")

        let model = BatchModel()
        model.add(urls: [plain, encrypted], preferredMode: nil)
        XCTAssertEqual(model.rows.count, 2)

        model.mode = .decrypt

        let plainRow = try XCTUnwrap(model.rows.first { $0.item.input == plain })
        XCTAssertEqual(plainRow.item.issue, .notEncrypted)
        XCTAssertEqual(model.rows.count, 2)
    }

    func testMixedInputsSetsFlag() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let plain = directory.appendingPathComponent("notes.txt")
        try Data("plain\n".utf8).write(to: plain)
        let encrypted = try makeEncryptedFile(in: directory, name: "secret", password: "apples")

        let mixed = BatchModel()
        mixed.add(urls: [plain, encrypted], preferredMode: nil)
        XCTAssertTrue(mixed.hasMixedInputs)

        let plainOnly = BatchModel()
        let second = directory.appendingPathComponent("second.txt")
        try Data("second\n".utf8).write(to: second)
        plainOnly.add(urls: [plain, second], preferredMode: nil)
        XCTAssertFalse(plainOnly.hasMixedInputs)
    }

    func testMixedBatchUsesOneModeForEveryRow() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let plain = directory.appendingPathComponent("notes.txt")
        try Data("plain\n".utf8).write(to: plain)
        let encrypted = try makeEncryptedFile(in: directory, name: "secret", password: "apples")

        let model = BatchModel()
        model.add(urls: [plain, encrypted], preferredMode: nil)

        XCTAssertEqual(model.mode, .encrypt)
        XCTAssertTrue(model.hasMixedInputs)
        XCTAssertEqual(model.rows[0].item.issue, nil)
        XCTAssertEqual(model.rows[1].item.issue, .alreadyEncrypted)
        XCTAssertFalse(model.canStart)

        model.mode = .decrypt
        XCTAssertTrue(model.hasMixedInputs, "the inputs are still mixed after a mode switch")
        XCTAssertEqual(model.rows[0].item.issue, .notEncrypted)
        XCTAssertEqual(model.rows[1].item.issue, nil)
    }

    func testCanStartRequiresMatchingConfirmationForEncrypt() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let plain = directory.appendingPathComponent("notes.txt")
        try Data("plain\n".utf8).write(to: plain)

        let model = BatchModel()
        model.add(urls: [plain], preferredMode: nil)
        model.password = "apples"
        model.confirmation = "pears"
        XCTAssertFalse(model.canStart)

        model.confirmation = "apples"
        XCTAssertTrue(model.canStart)
    }

    func testWrongPasswordMarksOnlyFailedRow() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try makeEncryptedFile(in: directory, name: "first", password: "apples")
        let second = try makeEncryptedFile(in: directory, name: "second", password: "pears")

        let model = BatchModel()
        model.add(urls: [first, second], preferredMode: nil)
        XCTAssertEqual(model.mode, .decrypt)
        model.password = "apples"
        XCTAssertTrue(model.canStart)

        model.start()
        await model.activeTask?.value

        XCTAssertEqual(model.phase, .finished)
        XCTAssertEqual(model.rows[0].status, .succeeded)
        XCTAssertTrue(isFailed(model.rows[1].status))
    }

    func testRetryFailedRunsOnlyFailedRows() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try makeEncryptedFile(in: directory, name: "first", password: "apples")
        let second = try makeEncryptedFile(in: directory, name: "second", password: "pears")

        let model = BatchModel()
        model.add(urls: [first, second], preferredMode: nil)
        model.password = "apples"
        model.start()
        await model.activeTask?.value

        XCTAssertEqual(model.rows[0].status, .succeeded)
        XCTAssertTrue(isFailed(model.rows[1].status))
        let firstOutput = model.rows[0].item.output
        let firstOutputDate = try modificationDate(of: firstOutput)

        model.password = "pears"
        model.retryFailed()
        await model.activeTask?.value

        XCTAssertEqual(model.rows[0].status, .succeeded)
        XCTAssertEqual(model.rows[1].status, .succeeded)
        XCTAssertEqual(try modificationDate(of: firstOutput), firstOutputDate)
    }

    func testCancelMarksRemainingRows() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let big = directory.appendingPathComponent("big.txt")
        try Data(repeating: 0x41, count: 64 * 1024 * 1024).write(to: big)
        let second = directory.appendingPathComponent("second.txt")
        let third = directory.appendingPathComponent("third.txt")
        try Data("second\n".utf8).write(to: second)
        try Data("third\n".utf8).write(to: third)

        let model = BatchModel()
        model.add(urls: [big, second, third], preferredMode: .encrypt)
        model.password = "apples"
        model.confirmation = "apples"
        model.start()

        let deadline = Date().addingTimeInterval(10)
        while model.rows.first?.status != .running, Date() < deadline {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(model.rows.first?.status, .running)

        model.cancel()
        await model.activeTask?.value

        XCTAssertEqual(model.rows[0].status, .cancelled)
        XCTAssertEqual(model.rows[1].status, .cancelled)
        XCTAssertEqual(model.rows[2].status, .cancelled)
    }

    func testStaleRunCompletionCannotFinishANewerRun() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = directory.appendingPathComponent("first.txt")
        let second = directory.appendingPathComponent("second.txt")
        try Data("first\n".utf8).write(to: first)
        try Data("second\n".utf8).write(to: second)

        let model = BatchModel()
        model.add(urls: [first], preferredMode: .encrypt)
        model.password = "apples"
        model.confirmation = "apples"
        model.start()

        let firstRows = model.rows
        let firstGeneration = model.runGeneration
        XCTAssertEqual(model.phase, .working)

        model.cancel()
        XCTAssertEqual(model.phase, .finished)

        model.add(urls: [second], preferredMode: .encrypt)
        model.password = "apples"
        model.confirmation = "apples"
        model.start()
        XCTAssertEqual(model.phase, .working)
        XCTAssertGreaterThan(model.runGeneration, firstGeneration)

        // The cancelled run finishes late, after a new run has started.
        let staleResults = firstRows.map {
            AESCryptBatchResult(item: $0.item, failure: nil)
        }
        model.applyResults(
            staleResults,
            rowIDs: firstRows.map(\.id),
            generation: firstGeneration
        )

        XCTAssertEqual(
            model.phase,
            .working,
            "a stale completion must not finish the new run"
        )
        XCTAssertTrue(model.rows.allSatisfy { $0.status == .pending || $0.status == .running })

        model.cancel()
        XCTAssertEqual(model.phase, .finished)
        XCTAssertTrue(model.rows.allSatisfy {
            $0.status == .cancelled || $0.status == .succeeded
        })
        await model.activeTask?.value
    }

    func testAddReportsUnreadableDroppedFiles() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("notes.txt")
        try Data("notes\n".utf8).write(to: file)

        let model = BatchModel()
        model.add(urls: [file], preferredMode: nil, unreadableCount: 2)

        XCTAssertEqual(model.rows.count, 1)
        XCTAssertEqual(model.notice, "Could not read 2 of the dropped files.")
    }

    func testAddReportsWhenEveryDroppedFileWasUnreadable() {
        let model = BatchModel()
        model.add(urls: [], preferredMode: nil, unreadableCount: 3)

        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertEqual(model.notice, "Could not read 3 of the dropped files.")
    }

    private func isFailed(_ status: BatchModel.RowStatus) -> Bool {
        if case .failed = status { return true }
        return false
    }

    private func makeEncryptedFile(
        in directory: URL,
        name: String,
        password: String
    ) throws -> URL {
        let plain = directory.appendingPathComponent("\(name)-source.txt")
        let encrypted = directory.appendingPathComponent("\(name).aes")
        try Data("secret \(name)\n".utf8).write(to: plain)
        try AESCrypt.encrypt(url: plain, to: encrypted, password: password)
        return encrypted
    }

    private func modificationDate(of url: URL) throws -> Date {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.modificationDate] as? Date)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aesopen-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
