import Foundation

/// The failures the command line raises on its own, before or around crypto.
///
/// `AESCryptError` and `AESCryptBatchIssue` come from the model; this type
/// covers the command line's own contract: bad arguments, the batch limit,
/// and files it cannot read to get a password.
public enum CLIError: Error, Equatable, Sendable {
    /// Bad arguments. The message is followed by the whole usage text.
    case usage(String)
    /// More files than one run accepts.
    case batchLimit(String)
    /// A file the command line needed but could not read.
    case io(String)

    /// The sentence printed after `aesopen: `.
    public var message: String {
        switch self {
        case .usage(let detail):
            return "\(detail)\n\n\(usageText)"
        case .batchLimit(let detail), .io(let detail):
            return detail
        }
    }

    /// The process exit status this failure maps to.
    public var code: Int32 {
        switch self {
        case .usage, .batchLimit:
            return 1
        case .io:
            return 5
        }
    }
}

/// Raised when a JSON document cannot be serialized.
///
/// The command line has already done all its work at that point, so this is a
/// broken-build signal rather than a user error. It maps to exit 1 with a
/// one-line message, like any other unexpected failure.
struct JSONEncodingFailure: Error, LocalizedError {
    var errorDescription: String? { "could not encode JSON" }
}
