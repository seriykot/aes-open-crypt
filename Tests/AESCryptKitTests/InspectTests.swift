import XCTest
@testable import AESCryptKit

final class InspectTests: XCTestCase {
    func testReadsV2HeaderAndExtensions() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "v2-hello", withExtension: "aes", subdirectory: "Fixtures")
        )

        let info = try AESCrypt.inspect(url: url)

        XCTAssertEqual(info.version, .v2)
        XCTAssertNil(info.kdfIterations)
        XCTAssertEqual(info.fileSize, 308)
        XCTAssertEqual(info.ciphertextLength, 16)
        XCTAssertEqual(info.extensions.map(\.identifier), ["CREATED_BY", ""])
        XCTAssertEqual(info.extensions[0].value, Data("aescrypt 3.14".utf8))
    }
}
