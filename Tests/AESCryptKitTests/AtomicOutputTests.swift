import XCTest
@testable import AESCryptKit

final class AtomicOutputTests: XCTestCase {
    func testWriteUsesRequestedPermissions() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let policies: [(permissions: OutputPermission, mode: Int)] = [
            (.ownerOnly, 0o600),
            (.groupReadable, 0o644),
        ]

        for policy in policies {
            XCTAssertEqual(policy.permissions.mode, policy.mode)

            let output = directory.appendingPathComponent("out-\(policy.mode).bin")
            let payload = Data("payload for \(policy.mode)".utf8)
            try AtomicOutput.write(to: output, permissions: policy.permissions) { handle in
                try handle.write(contentsOf: payload)
            }

            XCTAssertEqual(try Data(contentsOf: output), payload)
            XCTAssertEqual(try posixPermissions(of: output), policy.mode)
        }
    }

    func testWriterErrorRemovesTemporaryFileAndOutput() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let output = directory.appendingPathComponent("out.bin")
        let expected = NSError(domain: "test", code: 7)

        XCTAssertThrowsError(
            try AtomicOutput.write(to: output, permissions: .groupReadable) { handle in
                try handle.write(contentsOf: Data("partial write".utf8))
                throw expected
            }
        ) { error in
            XCTAssertEqual(error as NSError, expected)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    func testExistingOutputIsNotOverwritten() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let output = directory.appendingPathComponent("out.bin")
        let sentinel = Data("keep me\n".utf8)
        try sentinel.write(to: output)

        var writerRan = false
        XCTAssertThrowsError(
            try AtomicOutput.write(to: output, permissions: .ownerOnly) { handle in
                writerRan = true
                try handle.write(contentsOf: Data("replacement".utf8))
            }
        ) { error in
            XCTAssertEqual(error as? AESCryptError, .outputExists(output.path))
        }

        XCTAssertTrue(writerRan)
        XCTAssertEqual(try Data(contentsOf: output), sentinel)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.path),
            ["out.bin"]
        )
    }

    private func posixPermissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aesopen-atomic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
