import CommonCrypto
import Foundation

enum AES256CBC {
    static func encrypt(key: Data, iv: Data, data: Data) throws -> Data {
        try crypt(operation: CCOperation(kCCEncrypt), key: key, iv: iv, data: data)
    }

    static func decrypt(key: Data, iv: Data, data: Data) throws -> Data {
        try crypt(operation: CCOperation(kCCDecrypt), key: key, iv: iv, data: data)
    }

    private static func crypt(operation: CCOperation, key: Data, iv: Data, data: Data) throws -> Data {
        guard key.count == kCCKeySizeAES256, iv.count == kCCBlockSizeAES128 else {
            throw AESCryptError.corrupt("invalid AES key or IV length")
        }
        var output = Data(count: data.count + kCCBlockSizeAES128)
        var moved = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            data.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(0),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            inputBytes.baseAddress,
                            inputBytes.count,
                            outputBytes.baseAddress,
                            outputBytes.count,
                            &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else {
            throw AESCryptError.corrupt("AES operation failed with status \(status)")
        }
        output.removeSubrange(moved..<output.count)
        return output
    }
}

final class CBCStream {
    private var cryptor: CCCryptorRef?

    init(operation: CCOperation, key: Data, iv: Data) throws {
        guard key.count == kCCKeySizeAES256, iv.count == kCCBlockSizeAES128 else {
            throw AESCryptError.corrupt("invalid AES key or IV length")
        }
        var reference: CCCryptorRef?
        let status = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                CCCryptorCreate(
                    operation,
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(0),
                    keyBytes.baseAddress,
                    key.count,
                    ivBytes.baseAddress,
                    &reference
                )
            }
        }
        guard status == kCCSuccess, let reference else {
            throw AESCryptError.corrupt("could not start AES with status \(status)")
        }
        cryptor = reference
    }

    deinit {
        if let cryptor {
            CCCryptorRelease(cryptor)
        }
    }

    func update(_ data: Data) throws -> Data {
        guard let cryptor else {
            throw AESCryptError.corrupt("AES stream is closed")
        }
        let capacity = max(CCCryptorGetOutputLength(cryptor, data.count, false), data.count + kCCBlockSizeAES128)
        var output = Data(count: capacity)
        var moved = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            data.withUnsafeBytes { inputBytes in
                CCCryptorUpdate(
                    cryptor,
                    inputBytes.baseAddress,
                    inputBytes.count,
                    outputBytes.baseAddress,
                    outputBytes.count,
                    &moved
                )
            }
        }
        guard status == kCCSuccess else {
            throw AESCryptError.corrupt("AES update failed with status \(status)")
        }
        output.removeSubrange(moved..<output.count)
        return output
    }

    func finalize() throws -> Data {
        guard let cryptor else {
            throw AESCryptError.corrupt("AES stream is closed")
        }
        let capacity = max(CCCryptorGetOutputLength(cryptor, 0, true), kCCBlockSizeAES128)
        var output = Data(count: capacity)
        var moved = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            CCCryptorFinal(cryptor, outputBytes.baseAddress, outputBytes.count, &moved)
        }
        guard status == kCCSuccess else {
            throw AESCryptError.corrupt("AES finalize failed with status \(status)")
        }
        output.removeSubrange(moved..<output.count)
        return output
    }
}
