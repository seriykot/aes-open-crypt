import Foundation

/// Plaintext password hint stored in an AES Crypt v2/v3 extension tag.
///
/// Extensions are neither encrypted nor authenticated (see the AES Crypt
/// stream format), so this is informational only and must never be treated as
/// trusted or secret.
public enum AESPasswordHint {
    /// URI extension identifier. The path is ours; the host is lowercase as the
    /// format requires.
    public static let extensionIdentifier =
        "https://github.com/seriykot/aes-open-crypt/extensions/password-hint"

    /// Product limit for the UI and CLI. The format itself allows much more.
    public static let maximumLength = 256
}

public extension AESFileInfo {
    /// The trimmed plaintext hint stored in this file, or nil when absent,
    /// empty, or not valid UTF-8.
    var passwordHint: String? {
        guard let extensionValue = extensions.first(where: {
            $0.identifier == AESPasswordHint.extensionIdentifier
        })?.value else {
            return nil
        }
        guard let text = String(data: extensionValue, encoding: .utf8) else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
