import CommonCrypto
import Foundation

public struct AESCryptProgress: Sendable {
    public let completed: Int64
    public let total: Int64

    public init(completed: Int64, total: Int64) {
        self.completed = completed
        self.total = total
    }

    public var fraction: Double {
        total == 0 ? 1 : Double(completed) / Double(total)
    }
}

public typealias AESCryptProgressHandler = (AESCryptProgress) -> Void

extension AESCrypt {
    public static func decrypt(
        url: URL,
        to outputURL: URL,
        password: String,
        progress: AESCryptProgressHandler? = nil,
        isCancelled: () -> Bool = { false }
    ) throws {
        try FileSafety.ensureDistinct(input: url, output: outputURL)

        let info = try inspect(url: url)
        let input: FileHandle
        do {
            input = try FileHandle(forReadingFrom: url)
        } catch {
            throw AESCryptError.io(error.localizedDescription)
        }
        defer { try? input.close() }

        try input.seek(toOffset: 0)
        let header = try readExactly(input, 5)
        let headerModulo = header[4] & 0x0F

        try input.seek(toOffset: UInt64(info.payloadOffset))
        let iv1 = try readExactly(input, 16)

        let dataIV: Data
        let dataKey: Data

        if info.version == .v0 {
            dataIV = iv1
            dataKey = KeyDerivation.legacy(password: password, iv: iv1)
        } else {
            let encryptedSession = try readExactly(input, 48)
            let storedHeaderMAC = try readExactly(input, 32)
            let key: Data
            if info.version == .v3 {
                guard let iterations = info.kdfIterations else {
                    throw AESCryptError.corrupt("missing KDF iteration count")
                }
                key = try KeyDerivation.pbkdf2(password: password, salt: iv1, iterations: iterations)
            } else {
                key = KeyDerivation.legacy(password: password, iv: iv1)
            }

            var headerMAC = HMACStream(key: key)
            headerMAC.update(encryptedSession)
            if info.version == .v3 {
                headerMAC.update(Data([3]))
            }
            guard constantTimeEquals(headerMAC.finalize(), storedHeaderMAC) else {
                throw AESCryptError.wrongPassword
            }

            let session = try AES256CBC.decrypt(key: key, iv: iv1, data: encryptedSession)
            guard session.count == 48 else {
                throw AESCryptError.corrupt("bad session block")
            }
            dataIV = Data(session.prefix(16))
            dataKey = Data(session.suffix(32))
        }

        try input.seek(toOffset: UInt64(info.ciphertextOffset + info.ciphertextLength))
        let trailer = try readExactly(input, Int(info.trailerLength))

        let modulo: UInt8
        let storedPayloadMAC: Data
        switch info.version {
        case .v0:
            modulo = headerModulo
            storedPayloadMAC = trailer
        case .v1, .v2:
            modulo = trailer[trailer.startIndex] & 0x0F
            storedPayloadMAC = Data(trailer.dropFirst())
        case .v3:
            modulo = 0
            storedPayloadMAC = trailer
        }

        let temporary = try TemporaryFile.create(nextTo: outputURL)
        let tempURL = temporary.url
        let writer = temporary.handle

        var moved = false
        defer {
            try? writer.close()
            if !moved {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }

        try input.seek(toOffset: UInt64(info.ciphertextOffset))
        var payloadMAC = HMACStream(key: dataKey)
        let decryptor = try CBCStream(operation: CCOperation(kCCDecrypt), key: dataKey, iv: dataIV)

        var held = Data()
        func consume(_ plaintext: Data) throws {
            guard !plaintext.isEmpty else { return }
            held.append(plaintext)
            guard held.count > 16 else { return }
            try writer.write(contentsOf: held.dropLast(16))
            held = Data(held.suffix(16))
        }

        let total = info.ciphertextLength
        var completed: Int64 = 0
        progress?(AESCryptProgress(completed: 0, total: total))

        while completed < total {
            if isCancelled() {
                throw AESCryptError.cancelled
            }
            let count = Int(min(Int64(64 * 1024), total - completed))
            let chunk = try readExactly(input, count)
            payloadMAC.update(chunk)
            try consume(decryptor.update(chunk))
            completed += Int64(count)
            progress?(AESCryptProgress(completed: completed, total: total))
        }

        try consume(decryptor.finalize())

        guard constantTimeEquals(payloadMAC.finalize(), storedPayloadMAC) else {
            throw AESCryptError.authenticationFailed
        }

        if held.isEmpty {
            guard info.version != .v3 else {
                throw AESCryptError.corrupt("missing padding block")
            }
        } else {
            let keep: Int
            if info.version == .v3 {
                guard let padding = held.last, (1...16).contains(padding) else {
                    throw AESCryptError.corrupt("invalid padding")
                }
                let paddingLength = Int(padding)
                guard held.count >= paddingLength,
                      held.suffix(paddingLength).allSatisfy({ $0 == padding }) else {
                    throw AESCryptError.corrupt("invalid padding")
                }
                keep = held.count - paddingLength
            } else {
                guard held.count == 16 else {
                    throw AESCryptError.corrupt("missing final block")
                }
                keep = modulo == 0 ? 16 : Int(modulo)
            }
            try writer.write(contentsOf: held.prefix(keep))
        }

        try writer.synchronize()
        try writer.close()

        do {
            try FileManager.default.moveItem(at: tempURL, to: outputURL)
            moved = true
        } catch {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                throw AESCryptError.outputExists(outputURL.path)
            }
            throw AESCryptError.io(error.localizedDescription)
        }
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: outputURL.path
        )
    }
}
