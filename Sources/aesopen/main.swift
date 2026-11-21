// The `aesopen` executable, and nothing else.
//
// Every decision — parsing, planning, passwords, progress, JSON, exit codes —
// lives in AESOpenCLI and is unit-tested there. This file only connects that
// module to the process: standard streams, the terminal, the password prompt,
// and SIGINT. Keep it that way; a rule that appears here cannot be tested
// without launching a binary.

import AESOpenCLI
import Darwin
import Foundation

/// Set by the SIGINT handler, read by the runner.
///
/// A run can only ever move from 0 to 1, which is why unsynchronized access is
/// safe here: the handler writes one byte, and cancellation is checked between
/// chunks rather than acted on in the handler.
nonisolated(unsafe) private var interrupted: sig_atomic_t = 0

/// The real process, behind the `CLIEnvironment` seam.
///
/// Each method is the smallest possible wrapper: no formatting, no decisions,
/// no error translation. Everything the runner needs to know about a terminal
/// or a file is answered here and nowhere else.
private final class StandardCLIEnvironment: CLIEnvironment {
    /// One line of ordinary output. The trailing newline belongs to the
    /// environment so callers only ever pass a line of text.
    func writeStdout(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }

    /// Raw standard error. Prompts, progress, and the JSON fallback share it,
    /// so the caller decides exactly what bytes and newlines appear.
    func writeStderr(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }

    /// Redraw the progress indicator in place.
    func writeProgress(_ percent: Int) {
        writeStderr("\r\(percent)%")
    }

    /// Erase the progress indicator, leaving the cursor at the line start.
    func clearProgress() {
        writeStderr("\r")
    }

    /// Progress is for terminals only, and only on the error stream, so a
    /// pipeline reading stdout never sees a carriage return.
    var showsProgress: Bool {
        isatty(STDERR_FILENO) != 0
    }

    /// Prompt on the error stream and read the answer without echo.
    ///
    /// `getpass` writes its own prompt; an empty one keeps the text and the
    /// newline under our control so the output stays byte-exact.
    func readPassword(prompt: String) -> String? {
        writeStderr(prompt)
        defer { writeStderr("\n") }
        guard let pointer = getpass("") else { return nil }
        return String(cString: pointer)
    }

    /// The bytes of a password file, or of standard input for `-`.
    ///
    /// The data is returned raw: the runner owns the UTF-8 check, the
    /// first-line rule, and the empty-line rejection.
    func readPasswordFileData(_ path: String) throws -> Data {
        if path == "-" {
            return FileHandle.standardInput.readDataToEndOfFile()
        }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    /// Turn Ctrl-C into a cancel flag the runner polls.
    func installInterruptHandler() {
        signal(SIGINT) { _ in interrupted = 1 }
    }

    /// Whether Ctrl-C has been pressed since the handler was installed.
    var isInterrupted: Bool {
        interrupted != 0
    }
}

let status = CLIRunner.run(
    arguments: Array(CommandLine.arguments.dropFirst()),
    environment: StandardCLIEnvironment()
)
exit(status)
