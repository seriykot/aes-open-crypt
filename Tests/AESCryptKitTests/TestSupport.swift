import Darwin
import Foundation
import XCTest
@testable import AESCryptKit

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

struct FileSnapshot: Equatable {
    let contents: Data
    let size: Int64
    let permissions: UInt16
    let fileNumber: UInt64
    let systemNumber: UInt64
    let owner: UInt32
    let group: UInt32
    let immutable: Bool
    let appendOnly: Bool
    let modificationDate: Date
    let creationDate: Date
    let extendedAttributes: [String: Data]
}

func snapshot(_ url: URL) throws -> FileSnapshot {
    let attributes: [FileAttributeKey: Any]
    do {
        attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    } catch {
        throw AESCryptError.io("could not read attributes for \(url.path)")
    }

    func number(_ key: FileAttributeKey) -> NSNumber? {
        attributes[key] as? NSNumber
    }

    guard let size = number(.size),
          let permissions = number(.posixPermissions),
          let fileNumber = number(.systemFileNumber),
          let systemNumber = number(.systemNumber),
          let owner = number(.ownerAccountID),
          let group = number(.groupOwnerAccountID),
          let modificationDate = attributes[.modificationDate] as? Date,
          let creationDate = attributes[.creationDate] as? Date else {
        throw AESCryptError.io("incomplete attributes for \(url.path)")
    }

    return FileSnapshot(
        contents: try Data(contentsOf: url),
        size: size.int64Value,
        permissions: permissions.uint16Value,
        fileNumber: fileNumber.uint64Value,
        systemNumber: systemNumber.uint64Value,
        owner: owner.uint32Value,
        group: group.uint32Value,
        immutable: attributes[.immutable] as? Bool ?? false,
        appendOnly: attributes[.appendOnly] as? Bool ?? false,
        modificationDate: modificationDate,
        creationDate: creationDate,
        extendedAttributes: extendedAttributes(of: url)
    )
}

func extendedAttributes(of url: URL) -> [String: Data] {
    let path = url.path
    let listSize = listxattr(path, nil, 0, 0)
    guard listSize > 0 else { return [:] }

    var names = [CChar](repeating: 0, count: listSize)
    let listed = listxattr(path, &names, listSize, 0)
    guard listed > 0 else { return [:] }

    var result: [String: Data] = [:]
    var offset = 0
    while offset < listed {
        let name = names.withUnsafeBufferPointer { buffer in
            String(cString: buffer.baseAddress! + offset)
        }
        offset += name.utf8.count + 1

        let valueSize = name.withCString { getxattr(path, $0, nil, 0, 0, 0) }
        guard valueSize >= 0 else { continue }
        if valueSize == 0 {
            result[name] = Data()
            continue
        }

        var value = [UInt8](repeating: 0, count: valueSize)
        let read = name.withCString { getxattr(path, $0, &value, valueSize, 0, 0) }
        if read >= 0 {
            result[name] = Data(value.prefix(read))
        }
    }
    return result
}
