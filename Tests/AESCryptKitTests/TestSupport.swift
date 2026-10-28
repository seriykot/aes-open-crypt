import Foundation
import XCTest

func fixture(_ name: String) throws -> URL {
    try XCTUnwrap(
        Bundle.module.url(forResource: name, withExtension: "aes", subdirectory: "Fixtures"),
        "missing fixture \(name).aes"
    )
}

func temporaryOutput(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("aesopen-\(name)")
}

extension Data {
    init(hex: String) {
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let byte = UInt8(hex[index..<next], radix: 16) {
                bytes.append(byte)
            }
            index = next
        }
        self.init(bytes)
    }
}
