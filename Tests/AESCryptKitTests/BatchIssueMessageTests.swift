import AESCryptKit
import XCTest

/// Pins the one shared wording table for ``AESCryptBatchIssue``. The GUI and
/// the CLI both read these strings, so a change here is a user-visible change
/// in both frontends at once.
final class BatchIssueMessageTests: XCTestCase {
    func testTooManyFilesMessage() {
        XCTAssertEqual(
            AESCryptBatchIssue.tooManyFiles(10).userMessage,
            "Maximum of 10 files at a time is allowed."
        )
        XCTAssertEqual(
            AESCryptBatchIssue.tooManyFiles(3).userMessage,
            "Maximum of 3 files at a time is allowed."
        )
    }

    func testNotAFileMessage() {
        XCTAssertEqual(
            AESCryptBatchIssue.notAFile.userMessage,
            "This is a folder or document package, not a file. Zip it first to encrypt it."
        )
    }

    func testAlreadyEncryptedMessage() {
        XCTAssertEqual(
            AESCryptBatchIssue.alreadyEncrypted.userMessage,
            "This is already an AES Crypt file. Use decrypt instead."
        )
    }

    func testNotEncryptedMessage() {
        XCTAssertEqual(
            AESCryptBatchIssue.notEncrypted.userMessage,
            "This is not an AES Crypt file. Use encrypt instead."
        )
    }

    func testInvalidAESFileMessage() {
        XCTAssertEqual(
            AESCryptBatchIssue.invalidAESFile.userMessage,
            "This .aes file is not a valid AES Crypt file."
        )
    }

    func testUnsupportedVersionMessage() {
        XCTAssertEqual(
            AESCryptBatchIssue.unsupportedVersion(9).userMessage,
            "AES Crypt stream format 9 is not supported."
        )
    }

    func testOutputExistsMessage() {
        XCTAssertEqual(
            AESCryptBatchIssue.outputExists("/tmp/notes.txt.aes").userMessage,
            "An output file already exists at /tmp/notes.txt.aes."
        )
    }

    func testSameFileMessage() {
        XCTAssertEqual(
            AESCryptBatchIssue.sameFile.userMessage,
            "The input and output are the same file. Choose a different output name."
        )
    }

    func testInspectFailedMessage() {
        XCTAssertEqual(
            AESCryptBatchIssue.inspectFailed("Permission denied").userMessage,
            "Could not read the file: Permission denied"
        )
    }

    func testErrorDescriptionIsTheUserMessage() {
        let issue = AESCryptBatchIssue.outputExists("/tmp/notes.txt.aes")
        let localized: LocalizedError = issue
        XCTAssertEqual(localized.errorDescription, issue.userMessage)
        XCTAssertEqual(
            (AESCryptBatchIssue.notAFile as Error).localizedDescription,
            AESCryptBatchIssue.notAFile.userMessage
        )
    }
}
