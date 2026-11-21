import AESCryptKit
import Foundation
import XCTest
@testable import AESOpenCLI

/// Whole runs through the fake environment, on real files in a temp directory.
final class RunTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aesopen-run-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    // MARK: - Top-level output

    func testNoArgumentsPrintsUsageToStdoutAndExitsOne() {
        let environment = FakeEnvironment()

        XCTAssertEqual(CLIRunner.run(arguments: [], environment: environment), 1)
        XCTAssertEqual(environment.stdoutLines, [usageText])
        XCTAssertEqual(environment.stderr, "")
    }

    func testHelpExitsZero() {
        let environment = FakeEnvironment()

        XCTAssertEqual(CLIRunner.run(arguments: ["--help"], environment: environment), 0)
        XCTAssertEqual(environment.stdoutLines, [usageText])
        XCTAssertEqual(environment.stderr, "")
    }

    func testVersionUsesTheSharedProductVersion() {
        let environment = FakeEnvironment()

        XCTAssertEqual(CLIRunner.run(arguments: ["--version"], environment: environment), 0)
        XCTAssertEqual(environment.stdoutLines, ["aesopen \(AESOpenVersion.current)"])
    }

    func testUsageErrorGoesToStderrWithTheUsageText() {
        let environment = FakeEnvironment()

        XCTAssertEqual(CLIRunner.run(arguments: ["encrypt", "--bogus"], environment: environment), 1)
        XCTAssertEqual(environment.stdoutLines, [])
        XCTAssertTrue(environment.stderr.hasPrefix("aesopen: unknown option '--bogus'\n\n"))
        XCTAssertTrue(environment.stderr.contains(usageText))
    }

    // MARK: - Round trips

    func testEncryptAndDecryptRoundTripWithAFlagPassword() throws {
        let payload = Data("plain payload\n".utf8)
        let plain = try write(payload, name: "a.txt")
        let encryptEnvironment = FakeEnvironment()

        let encryptCode = CLIRunner.run(
            arguments: ["encrypt", "--password", "apples", plain.path],
            environment: encryptEnvironment
        )

        XCTAssertEqual(encryptCode, 0, encryptEnvironment.stderr)
        XCTAssertEqual(encryptEnvironment.stdoutLines, [plain.path + ".aes"])
        XCTAssertEqual(encryptEnvironment.stderr, "")
        XCTAssertEqual(encryptEnvironment.installedHandlerCount, 1)
        XCTAssertEqual(encryptEnvironment.passwordPrompts, [])

        let encrypted = URL(fileURLWithPath: plain.path + ".aes")
        XCTAssertTrue(FileManager.default.fileExists(atPath: encrypted.path))
        try FileManager.default.removeItem(at: plain)

        let decryptEnvironment = FakeEnvironment()
        let decryptCode = CLIRunner.run(
            arguments: ["decrypt", "--password", "apples", encrypted.path],
            environment: decryptEnvironment
        )

        XCTAssertEqual(decryptCode, 0, decryptEnvironment.stderr)
        XCTAssertEqual(decryptEnvironment.stdoutLines, [plain.path])
        XCTAssertEqual(try Data(contentsOf: plain), payload)
    }

    func testInteractivePasswordIsPromptedTwiceForEncrypt() throws {
        let plain = try write("prompted payload\n", name: "p.txt")
        let environment = FakeEnvironment()
        environment.passwords = ["apples", "apples"]

        let code = CLIRunner.run(arguments: ["encrypt", plain.path], environment: environment)

        XCTAssertEqual(code, 0, environment.stderr)
        XCTAssertEqual(environment.passwordPrompts, ["Password: ", "Repeat password: "])
        XCTAssertEqual(environment.stdoutLines, [plain.path + ".aes"])
    }

    func testMismatchedInteractivePasswordsExitOne() throws {
        let plain = try write("payload\n", name: "m.txt")
        let environment = FakeEnvironment()
        environment.passwords = ["apples", "pears"]

        let code = CLIRunner.run(arguments: ["encrypt", plain.path], environment: environment)

        XCTAssertEqual(code, 1)
        XCTAssertTrue(environment.stderr.contains("passwords do not match"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plain.path + ".aes"))
    }

    func testUnreadablePasswordPromptExitsOne() throws {
        let plain = try write("payload\n", name: "n.txt")
        let environment = FakeEnvironment()

        let code = CLIRunner.run(arguments: ["encrypt", plain.path], environment: environment)

        XCTAssertEqual(code, 1)
        XCTAssertTrue(environment.stderr.contains("could not read a password"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plain.path + ".aes"))
    }

    func testOutputFlagWritesTheExactPath() throws {
        let plain = try write("exact payload\n", name: "e.txt")
        let output = directory.appendingPathComponent("chosen-out.aes")
        let environment = FakeEnvironment()

        let code = CLIRunner.run(
            arguments: ["encrypt", "--password", "apples", "-o", output.path, plain.path],
            environment: environment
        )

        XCTAssertEqual(code, 0, environment.stderr)
        XCTAssertEqual(environment.stdoutLines, [output.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plain.path + ".aes"))
    }

    // MARK: - Password files

    func testPasswordFileUsesItsFirstLine() throws {
        let plain = try write("file payload\n", name: "f.txt")
        let environment = FakeEnvironment()
        environment.passwordFiles["secrets.txt"] = Data("file secret\nsecond line\n".utf8)

        let code = CLIRunner.run(
            arguments: ["encrypt", "--password-file", "secrets.txt", plain.path],
            environment: environment
        )

        XCTAssertEqual(code, 0, environment.stderr)
        XCTAssertEqual(environment.passwordPrompts, [])

        let encrypted = URL(fileURLWithPath: plain.path + ".aes")
        let decrypted = directory.appendingPathComponent("back.txt")
        try AESCrypt.decrypt(url: encrypted, to: decrypted, password: "file secret")
        XCTAssertEqual(try Data(contentsOf: decrypted), Data("file payload\n".utf8))
    }

    func testPasswordFileDashReadsStdin() throws {
        let plain = try write("stdin payload\n", name: "s.txt")
        let environment = FakeEnvironment()
        environment.passwordFiles["-"] = Data("stdin secret\n".utf8)

        let code = CLIRunner.run(
            arguments: ["encrypt", "--password-file", "-", plain.path],
            environment: environment
        )

        XCTAssertEqual(code, 0, environment.stderr)
        let encrypted = URL(fileURLWithPath: plain.path + ".aes")
        let decrypted = directory.appendingPathComponent("stdin-back.txt")
        try AESCrypt.decrypt(url: encrypted, to: decrypted, password: "stdin secret")
        XCTAssertEqual(try Data(contentsOf: decrypted), Data("stdin payload\n".utf8))
    }

    func testEmptyPasswordFileLineIsAUsageError() throws {
        let plain = try write("payload\n", name: "e.txt")
        let environment = FakeEnvironment()
        environment.passwordFiles["empty"] = Data("\nsecret\n".utf8)

        let code = CLIRunner.run(
            arguments: ["encrypt", "--password-file", "empty", plain.path],
            environment: environment
        )

        XCTAssertEqual(code, 1)
        XCTAssertTrue(environment.stderr.contains("password file empty is empty"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plain.path + ".aes"))
    }

    func testUnreadablePasswordFileExitsFive() throws {
        let plain = try write("payload\n", name: "u.txt")
        let environment = FakeEnvironment()

        let code = CLIRunner.run(
            arguments: ["encrypt", "--password-file", "missing", plain.path],
            environment: environment
        )

        XCTAssertEqual(code, 5)
        XCTAssertTrue(environment.stderr.contains("cannot read password file missing"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plain.path + ".aes"))
    }

    // MARK: - Results

    func testJSONRunEmitsTheDocumentedSchema() throws {
        let plain = try write("json payload\n", name: "j.txt")
        let environment = FakeEnvironment()

        let code = CLIRunner.run(
            arguments: ["encrypt", "--password", "apples", "--json", "--iterations", "1000", plain.path],
            environment: environment
        )

        XCTAssertEqual(code, 0, environment.stderr)
        let document = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(environment.stdout.utf8)) as? [String: Any]
        )
        XCTAssertEqual(document["version"] as? String, AESOpenVersion.current)
        XCTAssertEqual(document["command"] as? String, "encrypt")
        let results = try XCTUnwrap(document["results"] as? [[String: Any]])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0]["mode"] as? String, "encrypt")
        XCTAssertEqual(results[0]["status"] as? String, "ok")
        XCTAssertEqual(results[0]["input"] as? String, plain.path)
        XCTAssertEqual(results[0]["output"] as? String, plain.path + ".aes")
        XCTAssertTrue(results[0]["error"] is NSNull)
    }

    func testWrongPasswordExitsTwoAndLeavesNoOutput() throws {
        let plain = try write("secret payload\n", name: "w.txt")
        try AESCrypt.encrypt(
            url: plain,
            to: URL(fileURLWithPath: plain.path + ".aes"),
            password: "apples",
            format: .v2
        )
        try FileManager.default.removeItem(at: plain)
        let environment = FakeEnvironment()

        let code = CLIRunner.run(
            arguments: ["decrypt", "--password", "pears", plain.path + ".aes"],
            environment: environment
        )

        XCTAssertEqual(code, 2)
        XCTAssertEqual(environment.stdoutLines, [])
        XCTAssertTrue(environment.stderr.contains("Wrong password."))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plain.path))
    }

    func testInfoReportsAFile() throws {
        let plain = try write("info payload\n", name: "i.txt")
        try AESCrypt.encrypt(
            url: plain,
            to: URL(fileURLWithPath: plain.path + ".aes"),
            password: "apples",
            format: .v3,
            iterations: 1000,
            hint: "pet name"
        )
        let environment = FakeEnvironment()

        let code = CLIRunner.run(
            arguments: ["info", plain.path + ".aes"],
            environment: environment
        )

        XCTAssertEqual(code, 0, environment.stderr)
        XCTAssertTrue(environment.stdoutLines.contains("stream format: 3"))
        XCTAssertTrue(environment.stdoutLines.contains("kdf iterations: 1000"))
        XCTAssertTrue(environment.stdoutLines.contains("password hint: pet name"))
    }

    func testBatchLimitExitsOne() throws {
        let environment = FakeEnvironment()
        var arguments = ["encrypt", "--password", "apples"]
        for index in 0..<11 {
            arguments.append(try write("file \(index)\n", name: "many-\(index).txt").path)
        }

        let code = CLIRunner.run(arguments: arguments, environment: environment)

        XCTAssertEqual(code, 1)
        XCTAssertTrue(environment.stderr.contains("10"))
        XCTAssertEqual(environment.passwordPrompts, [])
    }

    // MARK: - Explicit output preflight

    func testOutputFlagPreflightsAnExistingOutputBeforeAskingForAPassword() throws {
        let plain = try write("payload\n", name: "pre.txt")
        let existing = directory.appendingPathComponent("existing.aes")
        try Data("sentinel bytes\n".utf8).write(to: existing)
        let environment = FakeEnvironment()

        let code = CLIRunner.run(
            arguments: ["encrypt", "-o", existing.path, plain.path],
            environment: environment
        )

        XCTAssertEqual(code, 5)
        XCTAssertEqual(environment.passwordPrompts, [])
        XCTAssertEqual(try Data(contentsOf: existing), Data("sentinel bytes\n".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plain.path + ".aes"))
    }

    func testOutputFlagRejectsAnAlreadyEncryptedInputBeforeAskingForAPassword() throws {
        let encrypted = try makeEncryptedFile(named: "double.aes")
        let output = directory.appendingPathComponent("double.out.aes")
        let environment = FakeEnvironment()

        let code = CLIRunner.run(
            arguments: ["encrypt", "-o", output.path, encrypted.path],
            environment: environment
        )

        XCTAssertEqual(code, 3)
        XCTAssertEqual(environment.passwordPrompts, [])
        XCTAssertTrue(environment.stderr.contains(AESCryptBatchIssue.alreadyEncrypted.userMessage))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testOutputFlagRejectsAPlainInputForDecryptBeforeAskingForAPassword() throws {
        let plain = try write("payload\n", name: "plain-for-decrypt.txt")
        let output = directory.appendingPathComponent("plain.out")
        let environment = FakeEnvironment()

        let code = CLIRunner.run(
            arguments: ["decrypt", "-o", output.path, plain.path],
            environment: environment
        )

        XCTAssertEqual(code, 3)
        XCTAssertEqual(environment.passwordPrompts, [])
        XCTAssertTrue(environment.stderr.contains(AESCryptBatchIssue.notEncrypted.userMessage))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testOutputFlagRejectsAFolderBeforeAskingForAPassword() throws {
        let folder = directory.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("folder.aes")
        let environment = FakeEnvironment()

        let code = CLIRunner.run(
            arguments: ["encrypt", "-o", output.path, folder.path],
            environment: environment
        )

        XCTAssertEqual(code, 5)
        XCTAssertEqual(environment.passwordPrompts, [])
        XCTAssertTrue(environment.stderr.contains(AESCryptBatchIssue.notAFile.userMessage))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testOutputFlagRejectsTheInputItselfBeforeAskingForAPassword() throws {
        let encrypted = try makeEncryptedFile(named: "same.aes")
        let before = try Data(contentsOf: encrypted)
        let environment = FakeEnvironment()

        let code = CLIRunner.run(
            arguments: ["decrypt", "-o", encrypted.path, encrypted.path],
            environment: environment
        )

        XCTAssertEqual(code, 5)
        XCTAssertEqual(environment.passwordPrompts, [])
        XCTAssertTrue(environment.stderr.contains(AESCryptBatchIssue.sameFile.userMessage))
        XCTAssertEqual(try Data(contentsOf: encrypted), before)
    }

    // MARK: - Empty passwords

    func testEmptyFlagPasswordIsAUsageError() throws {
        let plain = try write("payload\n", name: "empty-flag.txt")
        let environment = FakeEnvironment()

        let code = CLIRunner.run(
            arguments: ["encrypt", "--password", "", plain.path],
            environment: environment
        )

        XCTAssertEqual(code, 1)
        XCTAssertTrue(environment.stderr.contains("must not be empty"), environment.stderr)
        XCTAssertEqual(environment.passwordPrompts, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: plain.path + ".aes"))
    }

    func testEmptyInteractivePasswordIsAUsageError() throws {
        let plain = try write("payload\n", name: "empty-prompt.txt")
        let environment = FakeEnvironment()
        environment.passwords = ["", ""]

        let code = CLIRunner.run(arguments: ["encrypt", plain.path], environment: environment)

        XCTAssertEqual(code, 1)
        XCTAssertTrue(environment.stderr.contains("must not be empty"), environment.stderr)
        XCTAssertEqual(environment.passwordPrompts, ["Password: "])
        XCTAssertFalse(FileManager.default.fileExists(atPath: plain.path + ".aes"))
    }

    func testEmptyInteractivePasswordIsRejectedForDecrypt() throws {
        let encrypted = try makeEncryptedFile(named: "empty-decrypt.aes")
        let environment = FakeEnvironment()
        environment.passwords = [""]

        let code = CLIRunner.run(arguments: ["decrypt", encrypted.path], environment: environment)

        XCTAssertEqual(code, 1)
        XCTAssertTrue(environment.stderr.contains("must not be empty"), environment.stderr)
        XCTAssertEqual(environment.passwordPrompts, ["Password: "])
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("empty-decrypt").path))
    }

    // MARK: - Cancellation

    func testInterruptAfterTheFirstProgressWriteCancelsTheRun() throws {
        let first = try write(Data(repeating: 0x41, count: 512 * 1024 + 1), name: "big-0.txt")
        let second = try write(Data(repeating: 0x41, count: 512 * 1024 + 1), name: "big-1.txt")
        let environment = FakeEnvironment()
        environment.showsProgress = true
        environment.interruptOnFirstProgress = true

        let code = CLIRunner.run(
            arguments: ["encrypt", "--password", "apples", "--iterations", "1000", first.path, second.path],
            environment: environment
        )

        XCTAssertEqual(code, 130)
        XCTAssertEqual(environment.installedHandlerCount, 1)
        XCTAssertFalse(environment.progress.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path + ".aes"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path + ".aes"))
        XCTAssertEqual(environment.stdoutLines, [])
        XCTAssertTrue(environment.stderr.contains("Cancelled."), environment.stderr)
    }

    func testQuietRunShowsNoProgress() throws {
        let plain = try write("quiet payload\n", name: "q.txt")
        let environment = FakeEnvironment()
        environment.showsProgress = true

        let code = CLIRunner.run(
            arguments: ["encrypt", "--password", "apples", "--quiet", "--iterations", "1000", plain.path],
            environment: environment
        )

        XCTAssertEqual(code, 0, environment.stderr)
        XCTAssertEqual(environment.progress, [])
        XCTAssertEqual(environment.clearProgressCount, 0)
        XCTAssertEqual(environment.stdoutLines, [plain.path + ".aes"])
    }

    // MARK: - Helpers

    private func write(_ text: String, name: String) throws -> URL {
        try write(Data(text.utf8), name: name)
    }

    private func write(_ data: Data, name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    /// Make a real encrypted file at `<name>` in the test directory.
    private func makeEncryptedFile(named name: String) throws -> URL {
        let plain = try write("encrypted payload\n", name: name + ".plain")
        let encrypted = directory.appendingPathComponent(name)
        try AESCrypt.encrypt(url: plain, to: encrypted, password: "apples", format: .v2)
        try FileManager.default.removeItem(at: plain)
        return encrypted
    }
}
