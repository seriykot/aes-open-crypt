import Foundation
import XCTest
@testable import AESCryptKit

/// Hands out one full 64 KiB chunk and then fails, which is what a disk error
/// part way through a larger file looks like to the encrypt loop.
private final class FailAfterReader: ChunkReader {
    private var readCount = 0

    func read(upToCount count: Int) throws -> Data? {
        readCount += 1
        guard readCount == 1 else {
            throw NSError(domain: "test", code: 1)
        }
        return Data(repeating: 0x41, count: min(count, 64 * 1024))
    }

    func seekToEnd() throws -> UInt64 {
        128 * 1024
    }

    func seek(toOffset offset: UInt64) throws {}
}

final class EncryptReadErrorTests: XCTestCase {
    func testMidFileReadErrorFailsAndLeavesNoOutput() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aesopen-read-error-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let output = directory.appendingPathComponent("failed.aes")
        let reader = FailAfterReader()

        XCTAssertThrowsError(
            try AESCrypt.encrypt(
                reader: reader,
                to: output,
                password: "apples",
                format: .v3
            )
        ) { error in
            guard let aesError = error as? AESCryptError, case .io = aesError else {
                return XCTFail("expected AESCryptError.io, got \(error)")
            }
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(leftovers, [])
        XCTAssertFalse(leftovers.contains { $0.hasPrefix(".aesopen-") })
    }
}
