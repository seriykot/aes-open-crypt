import AESCryptKit
import Foundation

/// The whole command line, with the process behind `CLIEnvironment`.
///
/// `run` never exits: it returns the status the caller should exit with. That
/// keeps the executable's `main.swift` down to the environment adapter and
/// lets the tests drive every path — including a cancelled run — in process.
public enum CLIRunner {
    /// Run one command line and return the process exit status.
    public static func run(arguments: [String], environment: CLIEnvironment) -> Int32 {
        do {
            return try perform(arguments: arguments, environment: environment)
        } catch {
            environment.writeStderr("aesopen: \(Report.message(for: error))\n")
            return Report.exitCode(for: error)
        }
    }

    private static func perform(arguments: [String], environment: CLIEnvironment) throws -> Int32 {
        switch try parse(arguments) {
        case .help:
            environment.writeStdout(usageText)
            return 0
        case .version:
            environment.writeStdout("aesopen \(AESOpenVersion.current)")
            return 0
        case .missingCommand:
            environment.writeStdout(usageText)
            return 1
        case .command(let command, let options):
            return try perform(command: command, options: options, environment: environment)
        }
    }

    private static func perform(
        command: Command,
        options: Options,
        environment: CLIEnvironment
    ) throws -> Int32 {
        let urls = options.inputs.map { URL(fileURLWithPath: $0) }
        switch command {
        case .info:
            return try Report.showInfo(urls: urls, options: options, environment: environment)
        case .encrypt, .decrypt:
            let mode: AESCryptBatchMode = command == .encrypt ? .encrypt : .decrypt
            return try transform(urls: urls, mode: mode, options: options, environment: environment)
        }
    }

    /// Encrypt or decrypt the inputs and report the results.
    static func transform(
        urls: [URL],
        mode: AESCryptBatchMode,
        options: Options,
        environment: CLIEnvironment
    ) throws -> Int32 {
        if urls.count == 1, let outputPath = options.output {
            let password = try resolvePassword(
                options,
                confirm: mode == .encrypt,
                environment: environment
            )
            environment.installInterruptHandler()
            let result = runDirect(
                input: urls[0],
                output: URL(fileURLWithPath: outputPath),
                mode: mode,
                password: password,
                options: options,
                environment: environment
            )
            try Report.emit([result], command: mode.rawValue, options: options, environment: environment)
            return Report.aggregateExitCode([result])
        }

        let plan: AESCryptBatchPlan
        do {
            plan = try AESCryptBatch.plan(urls: urls, mode: mode, outputPolicy: .strict)
        } catch AESCryptBatchIssue.tooManyFiles(let maximum) {
            throw CLIError.batchLimit("too many input files: \(urls.count) given, \(maximum) maximum")
        }

        let password: String
        if plan.runnableItems.isEmpty {
            password = ""
        } else {
            password = try resolvePassword(
                options,
                confirm: mode == .encrypt,
                environment: environment
            )
        }

        environment.installInterruptHandler()
        let results = AESCryptBatch.run(
            plan: plan,
            password: password,
            format: options.format,
            iterations: options.iterations,
            hint: options.hint,
            progress: Report.progressHandler(options, environment: environment),
            isCancelled: { environment.isInterrupted }
        )
        Report.clearProgress(options, environment: environment)
        try Report.emit(results, command: mode.rawValue, options: options, environment: environment)
        return Report.aggregateExitCode(results)
    }

    /// Run one file onto an exact output path without going through a plan.
    ///
    /// This is the pre-plan path kept for now: it prompts before it checks
    /// anything, which the plan path is about to replace.
    private static func runDirect(
        input: URL,
        output: URL,
        mode: AESCryptBatchMode,
        password: String,
        options: Options,
        environment: CLIEnvironment
    ) -> AESCryptBatchResult {
        let item = AESCryptBatchItem(input: input, output: output, mode: mode)
        do {
            switch mode {
            case .encrypt:
                try AESCrypt.encrypt(
                    url: input,
                    to: output,
                    password: password,
                    format: options.format,
                    iterations: options.iterations,
                    hint: options.hint,
                    progress: Report.directProgressHandler(options, environment: environment),
                    isCancelled: { environment.isInterrupted }
                )
            case .decrypt:
                try AESCrypt.decrypt(
                    url: input,
                    to: output,
                    password: password,
                    progress: Report.directProgressHandler(options, environment: environment),
                    isCancelled: { environment.isInterrupted }
                )
            }
            Report.clearProgress(options, environment: environment)
            return AESCryptBatchResult(item: item, failure: nil)
        } catch let error as AESCryptError {
            Report.clearProgress(options, environment: environment)
            return AESCryptBatchResult(item: item, failure: .crypto(error))
        } catch {
            Report.clearProgress(options, environment: environment)
            return AESCryptBatchResult(item: item, failure: .crypto(.io(error.localizedDescription)))
        }
    }

    // MARK: - Passwords

    /// Find the password for this run: the flag, the file, or a prompt.
    ///
    /// `confirm` asks twice, which is what an encrypt prompt does. A single
    /// decrypt prompt leaves room for a password file piped on stdin.
    static func resolvePassword(
        _ options: Options,
        confirm: Bool,
        environment: CLIEnvironment
    ) throws -> String {
        if let supplied = options.password {
            return supplied
        }
        if let path = options.passwordFile {
            return try readPasswordFile(path, environment: environment)
        }
        guard let first = environment.readPassword(prompt: "Password: ") else {
            throw CLIError.usage("could not read a password")
        }
        if confirm {
            guard let second = environment.readPassword(prompt: "Repeat password: "), first == second else {
                throw CLIError.usage("passwords do not match")
            }
        }
        return first
    }

    /// Read the first line of a password file. `-` reads standard input.
    static func readPasswordFile(_ path: String, environment: CLIEnvironment) throws -> String {
        let data: Data
        do {
            data = try environment.readPasswordFileData(path)
        } catch {
            throw CLIError.io("cannot read password file \(path): \(Report.message(for: error))")
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw CLIError.usage("password file \(path) is not valid UTF-8")
        }
        let firstLine = text.prefix { $0 != "\n" && $0 != "\r" }
        guard !firstLine.isEmpty else {
            throw CLIError.usage("password file \(path) is empty")
        }
        return String(firstLine)
    }
}
