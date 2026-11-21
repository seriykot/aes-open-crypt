import Foundation

/// One presentation seam for batch planning issues.
///
/// The GUI and the CLI both show these sentences, so the wording lives in
/// exactly one place. A change here is a user-visible change in both
/// frontends; `BatchIssueMessageTests` pins every case.
extension AESCryptBatchIssue: LocalizedError {
    /// The sentence shown to a person, without a trailing period beyond what
    /// is written here.
    public var userMessage: String {
        switch self {
        case .tooManyFiles(let maximum):
            return "Maximum of \(maximum) files at a time is allowed."
        case .notAFile:
            return "This is a folder or document package, not a file. Zip it first to encrypt it."
        case .alreadyEncrypted:
            return "This is already an AES Crypt file. Use decrypt instead."
        case .notEncrypted:
            return "This is not an AES Crypt file. Use encrypt instead."
        case .invalidAESFile:
            return "This .aes file is not a valid AES Crypt file."
        case .unsupportedVersion(let version):
            return "AES Crypt stream format \(version) is not supported."
        case .outputExists(let path):
            return "An output file already exists at \(path)."
        case .sameFile:
            return "The input and output are the same file. Choose a different output name."
        case .inspectFailed(let detail):
            return "Could not read the file: \(detail)"
        }
    }

    /// `LocalizedError` entry point, so a bare `AESCryptBatchIssue` shown by
    /// any standard error path reads the same way.
    public var errorDescription: String? { userMessage }
}
