import XCTest
@testable import AESCryptKit

final class KnownAnswerTests: XCTestCase {
    private struct Vector: Decodable {
        let plaintext: String
        let ciphertextHex: String

        enum CodingKeys: String, CodingKey {
            case plaintext
            case ciphertextHex = "ciphertext_hex"
        }
    }

    func testOfficialVectorsForAllStreamFormats() throws {
        for version in 0...3 {
            let url = try XCTUnwrap(
                Bundle.module.url(
                    forResource: "v\(version)",
                    withExtension: "json",
                    subdirectory: "Fixtures/vectors"
                )
            )
            let vectors = try JSONDecoder().decode([Vector].self, from: Data(contentsOf: url))
            XCTAssertEqual(vectors.count, 21)

            for (index, vector) in vectors.enumerated() {
                let encrypted = temporaryOutput("v\(version)-\(index).aes")
                let decrypted = temporaryOutput("v\(version)-\(index).out")
                defer {
                    try? FileManager.default.removeItem(at: encrypted)
                    try? FileManager.default.removeItem(at: decrypted)
                }

                try Data(hex: vector.ciphertextHex).write(to: encrypted)
                try AESCrypt.decrypt(url: encrypted, to: decrypted, password: "Hello")

                XCTAssertEqual(
                    try Data(contentsOf: decrypted),
                    Data(vector.plaintext.utf8),
                    "stream format \(version), vector \(index)"
                )
            }
        }
    }
}
