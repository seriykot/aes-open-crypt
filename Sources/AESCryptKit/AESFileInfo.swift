import Foundation

public enum AESFormatVersion: UInt8, CaseIterable, Sendable {
    case v0 = 0
    case v1 = 1
    case v2 = 2
    case v3 = 3
}

public struct AESExtension: Equatable, Sendable {
    public let identifier: String
    public let value: Data

    public init(identifier: String, value: Data) {
        self.identifier = identifier
        self.value = value
    }
}

public struct AESFileInfo: Equatable, Sendable {
    public let version: AESFormatVersion
    public let kdfIterations: UInt32?
    public let extensions: [AESExtension]
    public let fileSize: Int64
    public let ciphertextLength: Int64
    public let payloadOffset: Int64
    public let ciphertextOffset: Int64
    public let trailerLength: Int64

    public init(
        version: AESFormatVersion,
        kdfIterations: UInt32?,
        extensions: [AESExtension],
        fileSize: Int64,
        ciphertextLength: Int64,
        payloadOffset: Int64,
        ciphertextOffset: Int64,
        trailerLength: Int64
    ) {
        self.version = version
        self.kdfIterations = kdfIterations
        self.extensions = extensions
        self.fileSize = fileSize
        self.ciphertextLength = ciphertextLength
        self.payloadOffset = payloadOffset
        self.ciphertextOffset = ciphertextOffset
        self.trailerLength = trailerLength
    }
}
