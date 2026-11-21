import Foundation
@testable import AESOpenCLI

/// A `CLIEnvironment` that records everything and replays a script.
///
/// It is the only seam the command line has, so a test can assert on the exact
/// bytes a person would see and on how many times a prompt or a handler was
/// installed, without a terminal or a signal.
final class FakeEnvironment: CLIEnvironment {
    /// Lines handed to `writeStdout`, in order, without their newlines.
    private(set) var stdoutLines: [String] = []

    /// Every byte handed to `writeStderr`, concatenated.
    private(set) var stderr = ""

    /// Percentages handed to `writeProgress`, in order.
    private(set) var progress: [Int] = []

    /// How many times the progress indicator was cleared.
    private(set) var clearProgressCount = 0

    /// How many times an interrupt handler was installed.
    private(set) var installedHandlerCount = 0

    /// Prompts handed to `readPassword`, in order.
    private(set) var passwordPrompts: [String] = []

    /// Answers for successive `readPassword` calls. Empty or `nil` means the
    /// read failed.
    var passwords: [String?] = []

    /// Raw bytes returned by `readPasswordFileData`, keyed by the requested
    /// path. `-` stands for standard input.
    var passwordFiles: [String: Data] = [:]

    /// Thrown by `readPasswordFileData` when set, before any stored data.
    var passwordFileError: Error?

    /// Whether the environment pretends standard error is a terminal.
    var showsProgress = false

    /// The flag `isInterrupted` reports.
    var isInterrupted = false

    /// When true, the first progress write marks the run interrupted, which is
    /// how a test stages a Ctrl-C during a transfer.
    var interruptOnFirstProgress = false

    /// All stdout, joined the way a terminal would show it.
    var stdout: String {
        stdoutLines.joined(separator: "\n")
    }

    func writeStdout(_ text: String) {
        stdoutLines.append(text)
    }

    func writeStderr(_ text: String) {
        stderr += text
    }

    func writeProgress(_ percent: Int) {
        progress.append(percent)
        if interruptOnFirstProgress {
            isInterrupted = true
        }
    }

    func clearProgress() {
        clearProgressCount += 1
    }

    func readPassword(prompt: String) -> String? {
        passwordPrompts.append(prompt)
        guard !passwords.isEmpty else { return nil }
        return passwords.removeFirst()
    }

    func readPasswordFileData(_ path: String) throws -> Data {
        if let error = passwordFileError {
            throw error
        }
        guard let data = passwordFiles[path] else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return data
    }

    func installInterruptHandler() {
        installedHandlerCount += 1
    }
}
