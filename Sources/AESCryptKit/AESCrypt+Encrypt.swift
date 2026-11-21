import CommonCrypto
import Foundation
import Security

extension AESCrypt {
    public static func encrypt(
        url: URL,
        to outputURL: URL,
        password: String,
        format: AESOutputFormat = .v2,
        iterations: UInt32 = 600_000,
        hint: String? = nil,
        progress: AESCryptProgressHandler? = nil,
        isCancelled: () -> Bool = { false }
    ) throws {
        try FileSafety.ensureDistinct(input: url, output: outputURL)

        // Reject an unusable iteration count before touching the file system.
        try validateIterations(iterations, for: format.streamVersion)

        let input: FileHandle
        do {
            input = try FileHandle(forReadingFrom: url)
        } catch {
            throw AESCryptError.io(error.localizedDescription)
        }
        defer { try? input.close() }

        try encrypt(
            reader: input,
            to: outputURL,
            password: password,
            format: format,
            iterations: iterations,
            hint: hint,
            progress: progress,
            isCancelled: isCancelled
        )
    }

    /// The encrypt path with its input abstracted, so tests can drive read
    /// failures that a real file cannot produce on demand. `url`-based callers
    /// reach it through the public wrapper above.
    static func encrypt(
        reader input: ChunkReader,
        to outputURL: URL,
        password: String,
        format: AESOutputFormat = .v2,
        iterations: UInt32 = 600_000,
        hint: String? = nil,
        progress: AESCryptProgressHandler? = nil,
        isCancelled: () -> Bool = { false }
    ) throws {
        let version = format.streamVersion
        try validateIterations(iterations, for: version)

        let total = Int64(try input.seekToEnd())
        try input.seek(toOffset: 0)

        let iv1 = try randomData(16)
        let iv0 = try randomData(16)
        let sessionKey = try randomData(32)
        let key: Data
        if version == .v3 {
            key = try KeyDerivation.pbkdf2(password: password, salt: iv1, iterations: iterations)
        } else {
            key = KeyDerivation.legacy(password: password, iv: iv1)
        }

        let encryptedSession = try AES256CBC.encrypt(
            key: key,
            iv: iv1,
            data: iv0 + sessionKey
        )

        var headerMAC = HMACStream(key: key)
        headerMAC.update(encryptedSession)
        if version == .v3 {
            headerMAC.update(Data([version.rawValue]))
        }

        var header = Data([0x41, 0x45, 0x53, version.rawValue, 0x00])
        let createdBy = Data("aes-open-crypt \(AESOpenVersion.current)".utf8)
        header.append(try extensionBlock(identifier: "CREATED_BY", value: createdBy))
        if let hint = normalizedHint(hint) {
            header.append(
                try extensionBlock(
                    identifier: AESPasswordHint.extensionIdentifier,
                    value: Data(hint.utf8)
                )
            )
        }
        header.append(contentsOf: [0x00, 0x00])
        if version == .v3 {
            header.append(UInt8((iterations >> 24) & 0xFF))
            header.append(UInt8((iterations >> 16) & 0xFF))
            header.append(UInt8((iterations >> 8) & 0xFF))
            header.append(UInt8(iterations & 0xFF))
        }
        header.append(iv1)
        header.append(encryptedSession)
        header.append(headerMAC.finalize())

        try AtomicOutput.write(to: outputURL, permissions: .groupReadable) { writer in
            try writer.write(contentsOf: header)

            let encryptor = try CBCStream(
                operation: CCOperation(kCCEncrypt),
                key: sessionKey,
                iv: iv0
            )
            var payloadMAC = HMACStream(key: sessionKey)
            var modulo: UInt8 = 0
            var completed: Int64 = 0
            let bufferSize = 64 * 1024
            progress?(AESCryptProgress(completed: 0, total: total))

            while true {
                if isCancelled() {
                    throw AESCryptError.cancelled
                }
                let chunk = try readUpTo(input, bufferSize)
                let isFinal = chunk.count < bufferSize
                var plain = chunk

                if isFinal {
                    if version == .v2 {
                        let padding = (16 - plain.count % 16) % 16
                        plain.append(contentsOf: repeatElement(UInt8(padding), count: padding))
                        modulo = UInt8(chunk.count % 16)
                    } else {
                        let padding = 16 - plain.count % 16
                        plain.append(contentsOf: repeatElement(UInt8(padding), count: padding))
                    }
                }

                let ciphertext = try encryptor.update(plain)
                payloadMAC.update(ciphertext)
                try writer.write(contentsOf: ciphertext)
                completed += Int64(chunk.count)
                progress?(AESCryptProgress(completed: completed, total: total))

                if isFinal { break }
            }

            let tail = try encryptor.finalize()
            if !tail.isEmpty {
                payloadMAC.update(tail)
                try writer.write(contentsOf: tail)
            }
            if version == .v2 {
                try writer.write(contentsOf: Data([modulo]))
            }
            try writer.write(contentsOf: payloadMAC.finalize())
        }
    }
}

private func validateIterations(_ iterations: UInt32, for version: AESFormatVersion) throws {
    if version == .v3, !(1...5_000_000).contains(iterations) {
        throw AESCryptError.corrupt("KDF iteration count is out of range")
    }
}

private func normalizedHint(_ hint: String?) -> String? {
    guard let hint else { return nil }
    let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func extensionBlock(identifier: String, value: Data) throws -> Data {
    var body = Data(identifier.utf8)
    body.append(0)
    body.append(value)
    guard body.count <= 0xFFFF else {
        throw AESCryptError.corrupt("extension is too large")
    }
    var block = Data([UInt8((body.count >> 8) & 0xFF), UInt8(body.count & 0xFF)])
    block.append(body)
    return block
}

private func randomData(_ count: Int) throws -> Data {
    var data = Data(count: count)
    let status = data.withUnsafeMutableBytes { bytes in
        SecRandomCopyBytes(kSecRandomDefault, count, bytes.baseAddress!)
    }
    guard status == errSecSuccess else {
        throw AESCryptError.io("the system random generator failed")
    }
    return data
}

private func readUpTo(_ reader: ChunkReader, _ count: Int) throws -> Data {
    var result = Data()
    while result.count < count {
        let chunk: Data?
        do {
            chunk = try reader.read(upToCount: count - result.count)
        } catch {
            // A failed read is not end of file. Reporting it here keeps a
            // short read from being encrypted as if it were the whole tail.
            throw AESCryptError.io(error.localizedDescription)
        }
        guard let chunk, !chunk.isEmpty else {
            break
        }
        result.append(chunk)
    }
    return result
}
