import AESCryptKit
import Foundation
import XCTest
@testable import AESOpenCLI

/// The presentation layer: exit-code tables, JSON shape, escaping, progress.
final class ReportingTests: XCTestCase {
    // MARK: - Exit-code priority

    func testPreferredCodePriority() {
        XCTAssertEqual(Report.preferredCode(in: [3, 2, 5]), 2)
        XCTAssertEqual(Report.preferredCode(in: [5, 3, 4]), 3)
        XCTAssertEqual(Report.preferredCode(in: [5, 4]), 4)
        XCTAssertEqual(Report.preferredCode(in: [5]), 5)
        XCTAssertEqual(Report.preferredCode(in: [130, 2, 3, 4, 5]), 130)
        XCTAssertEqual(Report.preferredCode(in: [4, 5, 130]), 130)
    }

    func testPreferredCodeEdgeCases() {
        XCTAssertEqual(Report.preferredCode(in: []), 0)
        XCTAssertEqual(Report.preferredCode(in: [1]), 1)
        XCTAssertEqual(Report.preferredCode(in: [1, 5]), 5)
    }

    // MARK: - Exit-code tables

    func testAESCryptErrorExitCodes() {
        let expected: [(AESCryptError, Int32)] = [
            (AESCryptError.wrongPassword, 2),
            (AESCryptError.notAnAESFile, 3),
            (AESCryptError.truncated, 3),
            (AESCryptError.corrupt("detail"), 3),
            (AESCryptError.authenticationFailed, 3),
            (AESCryptError.unsupportedVersion(9), 4),
            (AESCryptError.outputExists("/tmp/out"), 5),
            (AESCryptError.sameFile, 5),
            (AESCryptError.io("detail"), 5),
            (AESCryptError.cancelled, 130),
        ]

        for (error, code) in expected {
            XCTAssertEqual(Report.exitCode(for: error), code, "exit code for \(error)")
        }
    }

    func testAESCryptErrorKinds() {
        XCTAssertEqual(Report.kind(for: AESCryptError.notAnAESFile), "notAnAESFile")
        XCTAssertEqual(Report.kind(for: AESCryptError.unsupportedVersion(9)), "unsupportedVersion")
        XCTAssertEqual(Report.kind(for: AESCryptError.truncated), "truncated")
        XCTAssertEqual(Report.kind(for: AESCryptError.corrupt("x")), "corrupt")
        XCTAssertEqual(Report.kind(for: AESCryptError.wrongPassword), "wrongPassword")
        XCTAssertEqual(Report.kind(for: AESCryptError.authenticationFailed), "authenticationFailed")
        XCTAssertEqual(Report.kind(for: AESCryptError.outputExists("x")), "outputExists")
        XCTAssertEqual(Report.kind(for: AESCryptError.sameFile), "sameFile")
        XCTAssertEqual(Report.kind(for: AESCryptError.cancelled), "cancelled")
        XCTAssertEqual(Report.kind(for: AESCryptError.io("x")), "io")
    }

    func testBatchIssueExitCodes() {
        let expected: [(AESCryptBatchIssue, Int32)] = [
            (AESCryptBatchIssue.tooManyFiles(10), 1),
            (AESCryptBatchIssue.alreadyEncrypted, 3),
            (AESCryptBatchIssue.notEncrypted, 3),
            (AESCryptBatchIssue.invalidAESFile, 3),
            (AESCryptBatchIssue.unsupportedVersion(9), 4),
            (AESCryptBatchIssue.notAFile, 5),
            (AESCryptBatchIssue.outputExists("/tmp/out"), 5),
            (AESCryptBatchIssue.sameFile, 5),
            (AESCryptBatchIssue.inspectFailed("detail"), 5),
        ]

        for (issue, code) in expected {
            XCTAssertEqual(Report.exitCode(for: issue), code, "exit code for \(issue)")
        }
    }

    func testBatchIssueKinds() {
        XCTAssertEqual(Report.kind(for: .tooManyFiles(10)), "tooManyFiles")
        XCTAssertEqual(Report.kind(for: .notAFile), "notAFile")
        XCTAssertEqual(Report.kind(for: .alreadyEncrypted), "alreadyEncrypted")
        XCTAssertEqual(Report.kind(for: .notEncrypted), "notEncrypted")
        XCTAssertEqual(Report.kind(for: .invalidAESFile), "invalidAESFile")
        XCTAssertEqual(Report.kind(for: AESCryptBatchIssue.unsupportedVersion(9)), "unsupportedVersion")
        XCTAssertEqual(Report.kind(for: AESCryptBatchIssue.outputExists("x")), "outputExists")
        XCTAssertEqual(Report.kind(for: AESCryptBatchIssue.sameFile), "sameFile")
        XCTAssertEqual(Report.kind(for: .inspectFailed("x")), "inspectFailed")
    }

    func testCLIErrorExitCodes() {
        XCTAssertEqual(CLIError.usage("detail").code, 1)
        XCTAssertEqual(CLIError.batchLimit("detail").code, 1)
        XCTAssertEqual(CLIError.io("detail").code, 5)
        XCTAssertTrue(CLIError.usage("detail").message.contains(usageText))
        XCTAssertEqual(CLIError.batchLimit("detail").message, "detail")
        XCTAssertEqual(CLIError.io("detail").message, "detail")
    }

    func testIssueMessagesComeFromTheModel() {
        let detail = Report.describe(.issue(.notAFile))
        XCTAssertEqual(detail.code, 5)
        XCTAssertEqual(detail.kind, "notAFile")
        XCTAssertEqual(detail.message, AESCryptBatchIssue.notAFile.userMessage)
    }

    // MARK: - JSON

    func testEncryptJSONRow() throws {
        let item = try plannedItem(mode: .encrypt)

        let row = Report.jsonResult(AESCryptBatchResult(item: item, failure: nil))

        XCTAssertEqual(row["input"] as? String, item.input.path)
        XCTAssertEqual(row["output"] as? String, item.output.path)
        XCTAssertEqual(row["mode"] as? String, "encrypt")
        XCTAssertEqual(row["status"] as? String, "ok")
        XCTAssertTrue(row["error"] is NSNull)
        XCTAssertEqual(Set(row.keys), ["input", "output", "mode", "status", "error"])
    }

    func testDecryptJSONRowError() throws {
        let item = try plannedItem(mode: .decrypt)

        let row = Report.jsonResult(AESCryptBatchResult(item: item, failure: .crypto(.wrongPassword)))

        XCTAssertEqual(row["input"] as? String, item.input.path)
        XCTAssertEqual(row["mode"] as? String, "decrypt")
        XCTAssertEqual(row["status"] as? String, "error")
        XCTAssertTrue(row["output"] is NSNull)
        let error = try XCTUnwrap(row["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, 2)
        XCTAssertEqual(error["kind"] as? String, "wrongPassword")
        XCTAssertEqual(error["message"] as? String, "Wrong password.")
    }

    func testIssueJSONRow() throws {
        let item = try plannedItem(mode: .encrypt)
        let issue = AESCryptBatchIssue.outputExists(item.output.path)

        let row = Report.jsonResult(AESCryptBatchResult(item: item, failure: .issue(issue)))

        let error = try XCTUnwrap(row["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, 5)
        XCTAssertEqual(error["kind"] as? String, "outputExists")
        XCTAssertEqual(error["message"] as? String, issue.userMessage)
    }

    func testInfoJSON() throws {
        let info = AESFileInfo(
            version: .v3,
            kdfIterations: 600_000,
            extensions: [AESExtension(identifier: "CREATED_BY", value: Data("me".utf8))],
            fileSize: 512,
            ciphertextLength: 128,
            payloadOffset: 100,
            ciphertextOffset: 200,
            trailerLength: 32
        )

        let row = Report.infoJSON(url: URL(fileURLWithPath: "/tmp/a.aes"), info: info)

        XCTAssertEqual(row["input"] as? String, "/tmp/a.aes")
        XCTAssertEqual(row["status"] as? String, "ok")
        XCTAssertEqual(row["format"] as? String, "v3")
        XCTAssertEqual(row["size"] as? Int64, 512)
        XCTAssertEqual(row["ciphertext"] as? Int64, 128)
        XCTAssertEqual(row["kdfIterations"] as? Int, 600_000)
        XCTAssertTrue(row["hint"] is NSNull)
        let extensions = try XCTUnwrap(row["extensions"] as? [[String: Any]])
        XCTAssertEqual(extensions.count, 1)
        XCTAssertEqual(extensions.first?["identifier"] as? String, "CREATED_BY")
        XCTAssertEqual(extensions.first?["value"] as? String, "me")
    }

    func testInfoJSONWithoutIterationsOrExtensions() throws {
        let info = AESFileInfo(
            version: .v2,
            kdfIterations: nil,
            extensions: [],
            fileSize: 10,
            ciphertextLength: 20,
            payloadOffset: 1,
            ciphertextOffset: 2,
            trailerLength: 33
        )

        let row = Report.infoJSON(url: URL(fileURLWithPath: "/tmp/a.aes"), info: info)

        XCTAssertEqual(row["format"] as? String, "v2")
        XCTAssertTrue(row["kdfIterations"] is NSNull)
        XCTAssertEqual((row["extensions"] as? [Any])?.count, 0)
    }

    func testInfoErrorJSONKeepsTheSchema() throws {
        let row = Report.infoErrorJSON(
            url: URL(fileURLWithPath: "/tmp/bad.aes"),
            failure: .crypto(.notAnAESFile)
        )

        XCTAssertEqual(row["status"] as? String, "error")
        XCTAssertTrue(row["format"] is NSNull)
        XCTAssertTrue(row["size"] is NSNull)
        XCTAssertTrue(row["ciphertext"] is NSNull)
        XCTAssertTrue(row["kdfIterations"] is NSNull)
        XCTAssertNil(row["hint"], "error rows carry no hint key, matching the shipped schema")
        XCTAssertEqual((row["extensions"] as? [Any])?.count, 0)
        let error = try XCTUnwrap(row["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, 3)
        XCTAssertEqual(error["kind"] as? String, "notAnAESFile")
    }

    func testJSONIsOneSortedLine() throws {
        let environment = FakeEnvironment()
        try Report.printJSON(["b": 1, "a": 2], environment: environment)

        XCTAssertEqual(environment.stdoutLines, ["{\"a\":2,\"b\":1}"])
    }

    // MARK: - Escaping

    func testErrorTextEscapesTerminalControls() {
        let environment = FakeEnvironment()
        Report.writeError(
            url: URL(fileURLWithPath: "/tmp/control\u{1B}name.txt"),
            message: "bad\u{1B}detail",
            environment: environment
        )

        XCTAssertEqual(environment.stderr, "aesopen: /tmp/control\\u{001B}name.txt: bad\\u{001B}detail\n")
        XCTAssertFalse(environment.stderr.unicodeScalars.contains { $0.value == 0x1B })
    }

    func testSuccessTextEscapesTerminalControlsInThePath() throws {
        let environment = FakeEnvironment()
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("control\u{1B}name-\(UUID().uuidString).aes")
        let item = try plannedItem(mode: .encrypt, outputPath: output)

        try Report.emit(
            [AESCryptBatchResult(item: item, failure: nil)],
            command: "encrypt",
            options: Options(),
            environment: environment
        )

        XCTAssertEqual(environment.stdoutLines, [output.path.replacingOccurrences(of: "\u{1B}", with: "\\u{001B}")])
        XCTAssertFalse(environment.stdout.unicodeScalars.contains { $0.value == 0x1B })
    }

    func testInfoEscapesTerminalControlsInTheHint() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let environment = FakeEnvironment()

        let plain = directory.appendingPathComponent("hint.txt")
        try Data("payload\n".utf8).write(to: plain)
        try AESCrypt.encrypt(url: plain, to: plain.appendingPathExtension("aes"), password: "pw", format: .v2, hint: "visible\u{1B}[2J\nnext")

        try Report.printInfo(plain.appendingPathExtension("aes"), environment: environment)

        let hintLines = environment.stdoutLines.filter { $0.hasPrefix("password hint: ") }
        XCTAssertEqual(hintLines, ["password hint: visible\\u{001B}[2J\\nnext"])
        XCTAssertFalse(environment.stdout.unicodeScalars.contains { $0.value == 0x1B })
    }

    // MARK: - Progress

    func testProgressIsSuppressedForJSONQuietAndNonTerminals() {
        let environment = FakeEnvironment()
        var options = Options()

        environment.showsProgress = false
        XCTAssertFalse(Report.showsProgress(options, environment: environment))
        XCTAssertNil(Report.progressHandler(options, environment: environment))

        environment.showsProgress = true
        XCTAssertTrue(Report.showsProgress(options, environment: environment))
        XCTAssertNotNil(Report.progressHandler(options, environment: environment))

        options.json = true
        XCTAssertFalse(Report.showsProgress(options, environment: environment))
        XCTAssertNil(Report.progressHandler(options, environment: environment))

        options.json = false
        options.quiet = true
        XCTAssertFalse(Report.showsProgress(options, environment: environment))
        XCTAssertNil(Report.progressHandler(options, environment: environment))
    }

    func testProgressReportsEachPercentOnce() throws {
        let environment = FakeEnvironment()
        environment.showsProgress = true
        let handler = try XCTUnwrap(Report.progressHandler(Options(), environment: environment))

        for fraction in [0.0, 0.001, 0.5, 0.501, 1.0, 1.0] {
            handler(
                AESCryptBatchProgress(
                    itemIndex: 0,
                    itemCount: 1,
                    itemFraction: fraction,
                    overallFraction: fraction
                )
            )
        }

        XCTAssertEqual(environment.progress, [0, 50, 100])
    }

    func testClearProgressOnlyWhenShown() {
        let environment = FakeEnvironment()

        Report.clearProgress(Options(), environment: environment)
        XCTAssertEqual(environment.clearProgressCount, 0)

        environment.showsProgress = true
        Report.clearProgress(Options(), environment: environment)
        XCTAssertEqual(environment.clearProgressCount, 1)

        var quiet = Options()
        quiet.quiet = true
        Report.clearProgress(quiet, environment: environment)
        XCTAssertEqual(environment.clearProgressCount, 1)
    }

    // MARK: - Helpers

    /// Plan one real file so a report test has a planner-made item to show.
    private func plannedItem(
        mode: AESCryptBatchMode,
        outputPath: URL? = nil
    ) throws -> AESCryptBatchItem {
        let directory = try makeDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent(mode == .encrypt ? "in.txt" : "in.aes")
        switch mode {
        case .encrypt:
            try Data("payload".utf8).write(to: input)
        case .decrypt:
            let seed = directory.appendingPathComponent("seed.txt")
            try Data("payload".utf8).write(to: seed)
            try AESCrypt.encrypt(url: seed, to: input, password: "pw", format: .v2)
            try FileManager.default.removeItem(at: seed)
        }

        let output = outputPath ?? directory.appendingPathComponent("out")
        let plan = AESCryptBatch.planSingle(input: input, output: output, mode: mode)
        return try XCTUnwrap(
            plan.runnableItems.first,
            "the planner rejected the item: \(String(describing: plan.items.first?.issue))"
        )
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aesopen-report-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
