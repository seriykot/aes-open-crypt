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
    public static let maximumDisplayScalars = 256

    /// Bound text shown in the UI without changing the stored hint.
    public static func displayText(_ hint: String, maximumScalars: Int = maximumDisplayScalars) -> String {
        guard maximumScalars > 0 else { return "" }
        let scalars = hint.unicodeScalars
        guard scalars.count > maximumScalars else { return hint }
        return String(String.UnicodeScalarView(scalars.prefix(maximumScalars - 1))) + "…"
    }

    /// Make untrusted hint text safe for a terminal while preserving its value
    /// visibly. JSON output should use JSON serialization instead.
    public static func terminalSafeText(_ text: String) -> String {
        var result = String()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x09:
                result += "\\t"
            case 0x0A:
                result += "\\n"
            case 0x0D:
                result += "\\r"
            case 0x00...0x1F, 0x7F...0x9F:
                result += String(format: "\\u{%04X}", scalar.value)
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
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
