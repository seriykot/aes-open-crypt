import CommonCrypto
import CryptoKit
import Foundation

enum KeyDerivation {
    /// AES Crypt's original KDF, used by stream formats 0, 1 and 2.
    static func legacy(password: String, iv: Data) -> Data {
        var digest = [UInt8](iv)
        digest.append(contentsOf: [UInt8](repeating: 0, count: 16))
        let passwordBytes = utf16LE(password)

        for _ in 0..<8192 {
            var hasher = SHA256()
            hasher.update(data: Data(digest))
            hasher.update(data: passwordBytes)
            digest = Array(hasher.finalize())
        }
        return Data(digest)
    }

    /// Stream format 3 uses PBKDF2-HMAC-SHA512 with the IV as salt.
    static func pbkdf2(password: String, salt: Data, iterations: UInt32) throws -> Data {
        var derived = Data(count: 32)
        let derivedCount = derived.count
        let passwordLength = password.utf8.count
        let status = derived.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                password.withCString { passwordCString in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordCString,
                        passwordLength,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                        iterations,
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        derivedCount
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw AESCryptError.corrupt("PBKDF2 failed with status \(status)")
        }
        return derived
    }

    static func utf16LE(_ string: String) -> Data {
        var bytes = [UInt8]()
        bytes.reserveCapacity(string.utf16.count * 2)
        for unit in string.utf16 {
            bytes.append(UInt8(unit & 0xFF))
            bytes.append(UInt8(unit >> 8))
        }
        return Data(bytes)
    }
}

struct HMACStream {
    private var hmac: HMAC<SHA256>

    init(key: Data) {
        hmac = HMAC<SHA256>(key: SymmetricKey(data: key))
    }

    mutating func update(_ data: Data) {
        hmac.update(data: data)
    }

    mutating func finalize() -> Data {
        Data(hmac.finalize())
    }
}

func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
    guard lhs.count == rhs.count else { return false }
    var difference: UInt8 = 0
    for (left, right) in zip(lhs, rhs) {
        difference |= left ^ right
    }
    return difference == 0
}
