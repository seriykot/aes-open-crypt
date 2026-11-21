import XCTest
@testable import AESCryptKit

final class AESOutputFormatTests: XCTestCase {
    func testStreamVersionMapping() {
        XCTAssertEqual(AESOutputFormat.v2.streamVersion, .v2)
        XCTAssertEqual(AESOutputFormat.v3.streamVersion, .v3)
    }

    func testCLITextParsingIsCaseInsensitive() {
        XCTAssertEqual(AESOutputFormat(cliText: "v2"), .v2)
        XCTAssertEqual(AESOutputFormat(cliText: "2"), .v2)
        XCTAssertEqual(AESOutputFormat(cliText: "V2"), .v2)
        XCTAssertEqual(AESOutputFormat(cliText: "v3"), .v3)
        XCTAssertEqual(AESOutputFormat(cliText: "3"), .v3)
    }

    func testCLITextRejectsOtherVersions() {
        for text in ["v0", "v1", "4", "v9", ""] {
            XCTAssertNil(AESOutputFormat(cliText: text), "unexpectedly parsed '\(text)'")
        }
    }
}
