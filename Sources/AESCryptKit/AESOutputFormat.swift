/// The stream format written by the encrypt path.
///
/// Reading still accepts every format in ``AESFormatVersion``; writing is
/// limited to the two formats this project produces.
public enum AESOutputFormat: UInt8, CaseIterable, Hashable, Sendable {
    case v2 = 2
    case v3 = 3

    /// The read-side version this format writes.
    public var streamVersion: AESFormatVersion {
        switch self {
        case .v2:
            return .v2
        case .v3:
            return .v3
        }
    }

    /// Parses the `--format` spellings accepted on the command line.
    ///
    /// Matching ignores case. `v2` and `2` mean format 2; `v3` and `3` mean
    /// format 3. Anything else, including the read-only formats 0 and 1, is
    /// rejected.
    public init?(cliText: String) {
        switch cliText.lowercased() {
        case "v2", "2":
            self = .v2
        case "v3", "3":
            self = .v3
        default:
            return nil
        }
    }
}
