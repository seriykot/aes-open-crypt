import AESOpenCLI
import Darwin
import Foundation

/// Set by the SIGINT handler and read by the runner, so a cancel can only ever
/// move from 0 to 1.
nonisolated(unsafe) private var interrupted: sig_atomic_t = 0

private final class StandardCLIEnvironment: CLIEnvironment {
    func writeStdout(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }

    func writeStderr(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }

    func writeProgress(_ percent: Int) {
        writeStderr("\r\(percent)%")
    }

    func clearProgress() {
        writeStderr("\r")
    }

    var showsProgress: Bool {
        isatty(STDERR_FILENO) != 0
    }

    func readPassword(prompt: String) -> String? {
        writeStderr(prompt)
        defer { writeStderr("\n") }
        guard let pointer = getpass("") else { return nil }
        return String(cString: pointer)
    }

    func readPasswordFileData(_ path: String) throws -> Data {
        if path == "-" {
            return FileHandle.standardInput.readDataToEndOfFile()
        }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    func installInterruptHandler() {
        signal(SIGINT) { _ in interrupted = 1 }
    }

    var isInterrupted: Bool {
        interrupted != 0
    }
}

exit(
    CLIRunner.run(
        arguments: Array(CommandLine.arguments.dropFirst()),
        environment: StandardCLIEnvironment()
    )
)
