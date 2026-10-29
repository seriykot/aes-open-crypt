import Foundation

public enum AESCryptError: Error, Equatable, Sendable {
    case notAnAESFile
    case unsupportedVersion(UInt8)
    case truncated
    case corrupt(String)
    case wrongPassword
    case authenticationFailed
    case outputExists(String)
    case sameFile
    case cancelled
    case io(String)
}

extension AESCryptError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notAnAESFile:
            return "This is not an AES Crypt file."
        case .unsupportedVersion(let version):
            return "AES Crypt stream format \(version) is not supported."
        case .truncated:
            return "The file is truncated."
        case .corrupt(let detail):
            return "The file is corrupt: \(detail)."
        case .wrongPassword:
            return "Wrong password."
        case .authenticationFailed:
            return "The file failed its integrity check. It may have been modified or corrupted."
        case .outputExists(let path):
            return "An output file already exists at \(path)."
        case .sameFile:
            return "The input and output are the same file. Choose a different output name."
        case .cancelled:
            return "Cancelled."
        case .io(let detail):
            return "File error: \(detail)"
        }
    }
}
