import Foundation

public enum AESCrypt {
    /// Read the header of an AES Crypt file without touching the encrypted payload.
    public static func inspect(url: URL) throws -> AESFileInfo {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw AESCryptError.io(error.localizedDescription)
        }
        defer { try? handle.close() }

        let size = Int64(try handle.seekToEnd())
        try handle.seek(toOffset: 0)

        let header = try readExactly(handle, 5)
        guard header[0] == 0x41, header[1] == 0x45, header[2] == 0x53 else {
            throw AESCryptError.notAnAESFile
        }
        guard let version = AESFormatVersion(rawValue: header[3]) else {
            throw AESCryptError.unsupportedVersion(header[3])
        }
        if version != .v0, header[4] != 0 {
            throw AESCryptError.corrupt("reserved header byte is nonzero")
        }

        var offset: Int64 = 5
        var extensions: [AESExtension] = []

        if version.rawValue >= AESFormatVersion.v2.rawValue {
            var total = 0
            while true {
                let lengthBytes = try readExactly(handle, 2)
                offset += 2
                let length = Int(lengthBytes[lengthBytes.startIndex]) << 8
                    | Int(lengthBytes[lengthBytes.startIndex + 1])
                if length == 0 { break }

                total += length
                if total > 1_048_576 {
                    throw AESCryptError.corrupt("extension block is too large")
                }
                guard Int64(length) <= size - offset else {
                    throw AESCryptError.truncated
                }
                let body = try readExactly(handle, length)
                offset += Int64(length)

                guard let terminator = body.firstIndex(of: 0) else {
                    throw AESCryptError.corrupt("extension identifier has no terminator")
                }
                let identifier = String(decoding: body[..<terminator], as: UTF8.self)
                let value = Data(body[(terminator + 1)...])
                extensions.append(AESExtension(identifier: identifier, value: value))
            }
        }

        var iterations: UInt32?
        if version == .v3 {
            let bytes = try readExactly(handle, 4)
            offset += 4
            let value = UInt32(bytes[bytes.startIndex]) << 24
                | UInt32(bytes[bytes.startIndex + 1]) << 16
                | UInt32(bytes[bytes.startIndex + 2]) << 8
                | UInt32(bytes[bytes.startIndex + 3])
            guard value >= 1, value <= 5_000_000 else {
                throw AESCryptError.corrupt("invalid KDF iteration count")
            }
            iterations = value
        }

        let overhead: Int64
        switch version {
        case .v0:
            overhead = 16 + 32
        case .v1, .v2:
            overhead = 16 + 48 + 32 + 33
        case .v3:
            overhead = 16 + 48 + 32 + 32
        }

        guard size >= offset + overhead else {
            throw AESCryptError.truncated
        }
        let ciphertextLength = size - offset - overhead
        guard ciphertextLength % 16 == 0 else {
            throw AESCryptError.corrupt("ciphertext is not a whole number of blocks")
        }
        if version == .v3, ciphertextLength == 0 {
            throw AESCryptError.corrupt("missing padding block")
        }

        let ciphertextOffset = offset + (version == .v0 ? 16 : 16 + 48 + 32)
        let trailerLength: Int64
        switch version {
        case .v0:
            trailerLength = 32
        case .v1, .v2:
            trailerLength = 33
        case .v3:
            trailerLength = 32
        }

        return AESFileInfo(
            version: version,
            kdfIterations: iterations,
            extensions: extensions,
            fileSize: size,
            ciphertextLength: ciphertextLength,
            payloadOffset: offset,
            ciphertextOffset: ciphertextOffset,
            trailerLength: trailerLength
        )
    }
}

func readExactly(_ handle: FileHandle, _ count: Int) throws -> Data {
    var result = Data()
    while result.count < count {
        guard let chunk = try? handle.read(upToCount: count - result.count),
              !chunk.isEmpty else {
            throw AESCryptError.truncated
        }
        result.append(chunk)
    }
    return result
}
