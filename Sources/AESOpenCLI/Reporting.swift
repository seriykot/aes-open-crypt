import AESCryptKit
import Foundation

/// Everything needed to report one failure, in every output style.
struct FailureDescription: Equatable {
    let code: Int32
    let kind: String
    let message: String
}

/// The command line's presentation layer: text, JSON, progress, and the
/// exit-code tables.
///
/// Nothing here decides what to do; it only turns model results into the bytes
/// a person or a script reads. All writes go through `CLIEnvironment`, so the
/// same code is exercised by the unit tests and by the real executable.
enum Report {
    // MARK: - Exit codes and kinds

    /// The documented priority order for a batch with several failures.
    static func preferredCode(in codes: Set<Int32>) -> Int32 {
        for code: Int32 in [130, 2, 3, 4, 5] where codes.contains(code) {
            return code
        }
        return codes.isEmpty ? 0 : 1
    }

    /// Collapse a run's results into one exit status.
    static func aggregateExitCode(_ results: [AESCryptBatchResult]) -> Int32 {
        var codes = Set<Int32>()
        for result in results {
            if let failure = result.failure {
                codes.insert(describe(failure).code)
            }
        }
        return preferredCode(in: codes)
    }

    static func describe(_ failure: AESCryptBatchFailure) -> FailureDescription {
        switch failure {
        case .crypto(let error):
            return FailureDescription(
                code: exitCode(for: error),
                kind: kind(for: error),
                message: message(for: error)
            )
        case .issue(let issue):
            return FailureDescription(
                code: exitCode(for: issue),
                kind: kind(for: issue),
                message: issue.userMessage
            )
        }
    }

    static func exitCode(for error: Error) -> Int32 {
        if let cliError = error as? CLIError {
            return cliError.code
        }
        guard let aesError = error as? AESCryptError else {
            return 1
        }
        return exitCode(for: aesError)
    }

    static func exitCode(for error: AESCryptError) -> Int32 {
        switch error {
        case .wrongPassword:
            return 2
        case .notAnAESFile, .truncated, .corrupt, .authenticationFailed:
            return 3
        case .unsupportedVersion:
            return 4
        case .outputExists, .sameFile, .io:
            return 5
        case .cancelled:
            return 130
        }
    }

    static func exitCode(for issue: AESCryptBatchIssue) -> Int32 {
        switch issue {
        case .tooManyFiles:
            return 1
        case .alreadyEncrypted, .notEncrypted, .invalidAESFile:
            return 3
        case .unsupportedVersion:
            return 4
        case .notAFile, .outputExists, .sameFile, .inspectFailed:
            return 5
        }
    }

    static func kind(for error: AESCryptError) -> String {
        switch error {
        case .notAnAESFile:
            return "notAnAESFile"
        case .unsupportedVersion:
            return "unsupportedVersion"
        case .truncated:
            return "truncated"
        case .corrupt:
            return "corrupt"
        case .wrongPassword:
            return "wrongPassword"
        case .authenticationFailed:
            return "authenticationFailed"
        case .outputExists:
            return "outputExists"
        case .sameFile:
            return "sameFile"
        case .cancelled:
            return "cancelled"
        case .io:
            return "io"
        }
    }

    static func kind(for issue: AESCryptBatchIssue) -> String {
        switch issue {
        case .tooManyFiles:
            return "tooManyFiles"
        case .notAFile:
            return "notAFile"
        case .alreadyEncrypted:
            return "alreadyEncrypted"
        case .notEncrypted:
            return "notEncrypted"
        case .invalidAESFile:
            return "invalidAESFile"
        case .unsupportedVersion:
            return "unsupportedVersion"
        case .outputExists:
            return "outputExists"
        case .sameFile:
            return "sameFile"
        case .inspectFailed:
            return "inspectFailed"
        }
    }

    // MARK: - Messages

    static func message(for error: Error) -> String {
        if let cliError = error as? CLIError {
            return cliError.message
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    static func message(for error: AESCryptError) -> String {
        error.errorDescription ?? "Unknown encryption error."
    }

    // MARK: - Progress

    /// Progress is shown unless the run asked for machine-readable output,
    /// asked for quiet, or standard error is not a terminal.
    static func showsProgress(_ options: Options, environment: CLIEnvironment) -> Bool {
        !options.json && !options.quiet && environment.showsProgress
    }

    static func progressHandler(
        _ options: Options,
        environment: CLIEnvironment
    ) -> ((AESCryptBatchProgress) -> Void)? {
        guard showsProgress(options, environment: environment) else { return nil }
        var lastPercent = -1
        return { update in
            let percent = Int(update.overallFraction * 100)
            guard percent != lastPercent else { return }
            lastPercent = percent
            environment.writeProgress(percent)
        }
    }

    static func clearProgress(_ options: Options, environment: CLIEnvironment) {
        if showsProgress(options, environment: environment) {
            environment.clearProgress()
        }
    }

    // MARK: - Results

    static func emit(
        _ results: [AESCryptBatchResult],
        command: String,
        options: Options,
        environment: CLIEnvironment
    ) throws {
        if options.json {
            try printJSON(
                [
                    "version": AESOpenVersion.current,
                    "command": command,
                    "results": results.map(jsonResult),
                ],
                environment: environment
            )
            return
        }

        for result in results {
            if let failure = result.failure {
                writeError(
                    url: result.item.input,
                    message: describe(failure).message,
                    environment: environment
                )
            } else {
                environment.writeStdout(AESPasswordHint.terminalSafeText(result.item.output.path))
            }
        }
    }

    static func jsonResult(_ result: AESCryptBatchResult) -> [String: Any] {
        var row: [String: Any] = [
            "input": result.item.input.path,
            "output": result.failure == nil
                ? result.item.output.path
                : NSNull(),
            "mode": result.item.mode.rawValue,
            "status": result.failure == nil ? "ok" : "error",
            "error": NSNull(),
        ]

        if let failure = result.failure {
            let detail = describe(failure)
            row["error"] = [
                "code": Int(detail.code),
                "kind": detail.kind,
                "message": detail.message,
            ]
        }
        return row
    }

    /// Write one JSON document as a single line with sorted keys.
    static func printJSON(_ object: [String: Any], environment: CLIEnvironment) throws {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            throw JSONEncodingFailure()
        }
        environment.writeStdout(text)
    }

    static func writeError(url: URL, message: String, environment: CLIEnvironment) {
        let safePath = AESPasswordHint.terminalSafeText(url.path)
        let safeMessage = AESPasswordHint.terminalSafeText(message)
        environment.writeStderr("aesopen: \(safePath): \(safeMessage)\n")
    }

    // MARK: - Info

    static func showInfo(
        urls: [URL],
        options: Options,
        environment: CLIEnvironment
    ) throws -> Int32 {
        if options.json {
            var rows: [[String: Any]] = []
            var codes = Set<Int32>()

            for url in urls {
                do {
                    let info = try AESCrypt.inspect(url: url)
                    rows.append(infoJSON(url: url, info: info))
                } catch let error as AESCryptError {
                    codes.insert(exitCode(for: error))
                    rows.append(infoErrorJSON(url: url, failure: .crypto(error)))
                } catch {
                    codes.insert(5)
                    rows.append(
                        infoErrorJSON(url: url, failure: .crypto(.io(error.localizedDescription)))
                    )
                }
            }

            try printJSON(
                [
                    "version": AESOpenVersion.current,
                    "command": "info",
                    "results": rows,
                ],
                environment: environment
            )
            return preferredCode(in: codes)
        }

        var codes = Set<Int32>()
        for (index, url) in urls.enumerated() {
            if index > 0 {
                environment.writeStdout("")
            }
            do {
                try printInfo(url, environment: environment)
            } catch let error as AESCryptError {
                codes.insert(exitCode(for: error))
                writeError(url: url, message: message(for: error), environment: environment)
            } catch {
                codes.insert(5)
                writeError(url: url, message: message(for: error), environment: environment)
            }
        }
        return preferredCode(in: codes)
    }

    static func printInfo(_ url: URL, environment: CLIEnvironment) throws {
        let info = try AESCrypt.inspect(url: url)
        environment.writeStdout("file: \(AESPasswordHint.terminalSafeText(url.path))")
        environment.writeStdout("stream format: \(info.version.rawValue)")
        environment.writeStdout("size: \(info.fileSize) bytes")
        environment.writeStdout("ciphertext: \(info.ciphertextLength) bytes")
        if let iterations = info.kdfIterations {
            environment.writeStdout("kdf iterations: \(iterations)")
        }
        if let hint = info.passwordHint {
            environment.writeStdout("password hint: \(AESPasswordHint.terminalSafeText(hint))")
        }
        let otherExtensions = info.extensions.filter {
            !$0.identifier.isEmpty && $0.identifier != AESPasswordHint.extensionIdentifier
        }
        if !otherExtensions.isEmpty {
            environment.writeStdout("extensions:")
            for item in otherExtensions {
                let value = String(data: item.value, encoding: .utf8) ?? "<binary>"
                let identifier = AESPasswordHint.terminalSafeText(item.identifier)
                environment.writeStdout("  \(identifier) = \(AESPasswordHint.terminalSafeText(value))")
            }
        }
    }

    static func infoJSON(url: URL, info: AESFileInfo) -> [String: Any] {
        [
            "input": url.path,
            "status": "ok",
            "format": "v\(info.version.rawValue)",
            "size": info.fileSize,
            "ciphertext": info.ciphertextLength,
            "kdfIterations": info.kdfIterations.map { Int($0) } ?? NSNull(),
            "hint": info.passwordHint ?? NSNull(),
            "extensions": info.extensions.map { item in
                [
                    "identifier": item.identifier,
                    "value": String(data: item.value, encoding: .utf8)
                        ?? item.value.base64EncodedString(),
                ] as [String: Any]
            },
        ]
    }

    static func infoErrorJSON(url: URL, failure: AESCryptBatchFailure) -> [String: Any] {
        let detail = describe(failure)
        return [
            "input": url.path,
            "status": "error",
            "format": NSNull(),
            "size": NSNull(),
            "ciphertext": NSNull(),
            "kdfIterations": NSNull(),
            "extensions": [],
            "error": [
                "code": Int(detail.code),
                "kind": detail.kind,
                "message": detail.message,
            ],
        ]
    }
}
