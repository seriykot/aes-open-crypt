import Foundation

/// Everything the command line does that touches the process, behind a seam.
///
/// `CLIRunner` owns the decisions; an implementation owns the terminal. The
/// real one is a thin wrapper over `FileHandle`, `getpass`, and `signal` in the
/// `aesopen` executable. Tests pass a fake that records writes and replays a
/// script for the password prompts.
public protocol CLIEnvironment: AnyObject {
    /// Write one line of ordinary output: the terminal gets `text` plus a
    /// trailing newline.
    func writeStdout(_ text: String)

    /// Write `text` to standard error exactly as given, with no added newline.
    func writeStderr(_ text: String)

    /// Redraw the in-place progress indicator as `\rNN%`.
    func writeProgress(_ percent: Int)

    /// Erase the progress indicator with a carriage return.
    func clearProgress()

    /// Whether the error stream is a terminal that can show progress.
    var showsProgress: Bool { get }

    /// Ask for a password and read it without echoing. `nil` means the read
    /// failed; an empty string means the user pressed return.
    func readPassword(prompt: String) -> String?

    /// Read the raw bytes of a password file. `-` means standard input.
    func readPasswordFileData(_ path: String) throws -> Data

    /// Arrange for `isInterrupted` to become true on `SIGINT`.
    func installInterruptHandler()

    /// Whether the user has asked to cancel since the handler was installed.
    var isInterrupted: Bool { get }
}
