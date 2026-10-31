import AESCryptKit
import Darwin
import Foundation

private let toolVersion = "0.2.0"

private let usageText = """
aesopen - AES Crypt compatible encryption

Usage:
  aesopen encrypt [options] <file>...
  aesopen decrypt [options] <file>...
  aesopen info [options] <file>...
  aesopen --help
  aesopen --version

Files:
  Up to 10 input files per run, counted after duplicates are removed. An
  eleventh file is an error (exit 1); files are never silently dropped. One
  password applies to the whole batch.

Default output names:
  encrypt  <file>       -> <file>.aes
  decrypt  <file>.aes   -> <file>
  decrypt  <file>       -> <file>.decrypted
  Existing files are never overwritten. Use -o to choose an exact output path;
  -o is valid only with a single input file.

Options:
  -o, --output <path>     Exact output path. Single input only. Default: above.
  --format <v2|v3>        Output stream format. Default: v3.
  --hint <text>           Plaintext password hint. Encrypt only, up to 256
                          characters. Default: none.
  --iterations <n>        KDF iterations for v3. Default: 600000.
  --password <password>   Password on the command line. Visible in process
                          lists and shell history. Default: prompt.
  --password-file <path>  Read the password from the first line of <path>.
                          Use - for stdin. Prevents all prompts. Default: none.
  --json                  JSON on stdout. Suppresses progress. Default: off.
  --quiet                 Suppress progress. Output paths are still printed.
                          Default: off.
  -v, --version           Print the version and exit.
  -h, --help              Print this help and exit.

Examples:
  aesopen encrypt report.pdf notes.txt
  aesopen decrypt --password-file ~/.aesopen-password secret.aes
  aesopen info --json backup.aes | python3 -m json.tool

Exit codes:
  0    Every file succeeded.
  1    Usage error, or more than 10 input files.
  2    Wrong password.
  3    Corrupt file, not an AES Crypt file, or a file that does not match the
       requested direction.
  4    Unsupported AES Crypt stream version.
  5    File error, existing output, or input and output are the same file.
  130  Cancelled.
  When a batch has several failures, the first matching code in the order
  130, 2, 3, 4, 5 is returned.

JSON schema:
  {
    "version": "0.2.0",
    "command": "encrypt",
    "results": [
      {"input": "/abs/a.txt", "output": "/abs/a.txt.aes", "mode": "encrypt",
       "status": "ok", "error": null},
      {"input": "/abs/b.aes", "output": null, "mode": "decrypt",
       "status": "error",
       "error": {"code": 2, "kind": "wrongPassword", "message": "Wrong password."}}
    ]
  }
  "command" is encrypt, decrypt, or info. info results also carry "format",
  "size", "ciphertext", "kdfIterations", "hint", and "extensions". Error codes
  match the exit-code table.

Security:
  Passwords passed with --password appear in process lists and shell history.
  Prefer the interactive prompt or --password-file with a file readable only
  by you. aesopen never stores, logs, or transmits passwords. Password hints
  are stored as plaintext extensions in the file and are not authenticated;
  anyone can read or change them without the password.
"""

nonisolated(unsafe) private var interrupted: sig_atomic_t = 0

private struct Options {
    var output: String?
    var password: String?
    var passwordFile: String?
    var format: AESFormatVersion = .v3
    var hint: String?
    var iterations: UInt32 = 600_000
    var json = false
    var quiet = false
    var inputs: [String] = []
}

private enum Command: String {
    case info
    case encrypt
    case decrypt
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("aesopen: \(message(for: error))\n".utf8))
    exit(exitCode(for: error))
}

private func run() throws {
    var arguments = Array(CommandLine.arguments.dropFirst())
    guard let first = arguments.first else {
        print(usageText)
        exit(1)
    }
    arguments.removeFirst()

    let command: Command
    switch first {
    case "-h", "--help", "help":
        print(usageText)
        return
    case "-v", "--version", "version":
        print("aesopen \(toolVersion)")
        return
    default:
        guard let parsed = Command(rawValue: first) else {
            throw CLIError.usage("unknown command '\(first)'")
        }
        command = parsed
    }

    var options = Options()
    try parse(arguments, into: &options)

    guard !options.inputs.isEmpty else {
        throw CLIError.usage("missing input file")
    }
    if options.password != nil, options.passwordFile != nil {
        throw CLIError.usage("--password and --password-file cannot be combined")
    }
    if options.output != nil {
        if command == .info {
            throw CLIError.usage("info does not write an output file")
        }
        if options.inputs.count > 1 {
            throw CLIError.usage("-o/--output is valid only with a single input file")
        }
    }
    if let hint = options.hint {
        guard command == .encrypt else {
            throw CLIError.usage("--hint is valid only with encrypt")
        }
        let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > AESPasswordHint.maximumLength {
            throw CLIError.usage(
                "--hint is limited to \(AESPasswordHint.maximumLength) characters"
            )
        }
        options.hint = trimmed.isEmpty ? nil : trimmed
    }

    let urls = options.inputs.map { URL(fileURLWithPath: $0) }
    switch command {
    case .info:
        let code = showInfo(urls: urls, options: options)
        if code != 0 {
            exit(code)
        }
    case .encrypt, .decrypt:
        let mode: AESCryptBatchMode = command == .encrypt ? .encrypt : .decrypt
        let code = try transform(urls: urls, mode: mode, options: options)
        if code != 0 {
            exit(code)
        }
    }
}

private func parse(_ arguments: [String], into options: inout Options) throws {
    var index = 0
    var positionalOnly = false

    while index < arguments.count {
        let argument = arguments[index]
        if positionalOnly {
            options.inputs.append(argument)
            index += 1
            continue
        }

        switch argument {
        case "--":
            positionalOnly = true
        case "-o", "--output":
            options.output = try value(after: &index, in: arguments, name: argument)
        case "--password":
            options.password = try value(after: &index, in: arguments, name: argument)
        case "--password-file":
            options.passwordFile = try value(after: &index, in: arguments, name: argument)
        case "--format":
            let raw = try value(after: &index, in: arguments, name: argument).lowercased()
            switch raw {
            case "v2", "2":
                options.format = .v2
            case "v3", "3":
                options.format = .v3
            default:
                throw CLIError.usage("unknown format '\(raw)'")
            }
        case "--hint":
            options.hint = try value(after: &index, in: arguments, name: argument)
        case "--iterations":
            let raw = try value(after: &index, in: arguments, name: argument)
            guard let value = UInt32(raw), value > 0 else {
                throw CLIError.usage("--iterations needs a positive number")
            }
            options.iterations = value
        case "--json":
            options.json = true
        case "--quiet":
            options.quiet = true
        case "-v", "--version":
            print("aesopen \(toolVersion)")
            exit(0)
        case "-h", "--help":
            print(usageText)
            exit(0)
        default:
            if argument.hasPrefix("-"), argument != "-" {
                throw CLIError.usage("unknown option '\(argument)'")
            }
            options.inputs.append(argument)
        }
        index += 1
    }
}

private func value(after index: inout Int, in arguments: [String], name: String) throws -> String {
    index += 1
    guard index < arguments.count else {
        throw CLIError.usage("\(name) needs a value")
    }
    return arguments[index]
}

private func transform(urls: [URL], mode: AESCryptBatchMode, options: Options) throws -> Int32 {
    if urls.count == 1, let outputPath = options.output {
        let password = try resolvePassword(options, confirm: mode == .encrypt)
        installInterruptHandler()
        let result = runDirect(
            input: urls[0],
            output: URL(fileURLWithPath: outputPath),
            mode: mode,
            password: password,
            options: options
        )
        emit([result], command: mode.rawValue, options: options)
        return aggregateExitCode([result])
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
        password = try resolvePassword(options, confirm: mode == .encrypt)
    }

    installInterruptHandler()
    let results = AESCryptBatch.run(
        plan: plan,
        password: password,
        format: options.format,
        iterations: options.iterations,
        hint: options.hint,
        progress: batchProgressHandler(options),
        isCancelled: { interrupted != 0 }
    )
    clearProgress(options)
    emit(results, command: mode.rawValue, options: options)
    return aggregateExitCode(results)
}

private func runDirect(
    input: URL,
    output: URL,
    mode: AESCryptBatchMode,
    password: String,
    options: Options
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
                progress: directProgressHandler(options),
                isCancelled: { interrupted != 0 }
            )
        case .decrypt:
            try AESCrypt.decrypt(
                url: input,
                to: output,
                password: password,
                progress: directProgressHandler(options),
                isCancelled: { interrupted != 0 }
            )
        }
        clearProgress(options)
        return AESCryptBatchResult(item: item, failure: nil)
    } catch let error as AESCryptError {
        clearProgress(options)
        return AESCryptBatchResult(item: item, failure: .crypto(error))
    } catch {
        clearProgress(options)
        return AESCryptBatchResult(item: item, failure: .crypto(.io(error.localizedDescription)))
    }
}

private func showInfo(urls: [URL], options: Options) -> Int32 {
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
                rows.append(infoErrorJSON(url: url, failure: .crypto(.io(error.localizedDescription))))
            }
        }

        printJSON(["version": toolVersion, "command": "info", "results": rows])
        return preferredCode(in: codes)
    }

    var codes = Set<Int32>()
    for (index, url) in urls.enumerated() {
        if index > 0 {
            print("")
        }
        do {
            try printInfo(url)
        } catch let error as AESCryptError {
            codes.insert(exitCode(for: error))
            writeError(url: url, message: message(for: error))
        } catch {
            codes.insert(5)
            writeError(url: url, message: message(for: error))
        }
    }
    return preferredCode(in: codes)
}

private func printInfo(_ url: URL) throws {
    let info = try AESCrypt.inspect(url: url)
    print("file: \(url.path)")
    print("stream format: \(info.version.rawValue)")
    print("size: \(info.fileSize) bytes")
    print("ciphertext: \(info.ciphertextLength) bytes")
    if let iterations = info.kdfIterations {
        print("kdf iterations: \(iterations)")
    }
    if let hint = info.passwordHint {
        print("password hint: \(hint)")
    }
    let otherExtensions = info.extensions.filter {
        !$0.identifier.isEmpty && $0.identifier != AESPasswordHint.extensionIdentifier
    }
    if !otherExtensions.isEmpty {
        print("extensions:")
        for item in otherExtensions {
            let value = String(data: item.value, encoding: .utf8) ?? "<binary>"
            print("  \(item.identifier) = \(value)")
        }
    }
}

private func infoJSON(url: URL, info: AESFileInfo) -> [String: Any] {
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

private func infoErrorJSON(url: URL, failure: AESCryptBatchFailure) -> [String: Any] {
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

private func emit(_ results: [AESCryptBatchResult], command: String, options: Options) {
    if options.json {
        printJSON([
            "version": toolVersion,
            "command": command,
            "results": results.map(jsonResult),
        ])
        return
    }

    for result in results {
        if let failure = result.failure {
            writeError(url: result.item.input, message: describe(failure).message)
        } else {
            print(result.item.output.path)
        }
    }
}

private func jsonResult(_ result: AESCryptBatchResult) -> [String: Any] {
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

private func printJSON(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
          let text = String(data: data, encoding: .utf8) else {
        FileHandle.standardError.write(Data("aesopen: could not encode JSON\n".utf8))
        exit(1)
    }
    print(text)
}

private func writeError(url: URL, message: String) {
    FileHandle.standardError.write(
        Data("aesopen: \(url.path): \(message)\n".utf8)
    )
}

private func resolvePassword(_ options: Options, confirm: Bool) throws -> String {
    if let supplied = options.password {
        return supplied
    }
    if let path = options.passwordFile {
        return try readPasswordFile(path)
    }
    guard let first = readPassword("Password: ") else {
        throw CLIError.usage("could not read a password")
    }
    if confirm {
        guard let second = readPassword("Repeat password: "), first == second else {
            throw CLIError.usage("passwords do not match")
        }
    }
    return first
}

private func readPasswordFile(_ path: String) throws -> String {
    let data: Data
    if path == "-" {
        data = FileHandle.standardInput.readDataToEndOfFile()
    } else {
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw CLIError.io("cannot read password file \(path): \(error.localizedDescription)")
        }
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

private func readPassword(_ prompt: String) -> String? {
    FileHandle.standardError.write(Data(prompt.utf8))
    defer { FileHandle.standardError.write(Data("\n".utf8)) }
    guard let pointer = getpass("") else { return nil }
    return String(cString: pointer)
}

private func installInterruptHandler() {
    signal(SIGINT) { _ in interrupted = 1 }
}

private func showsProgress(_ options: Options) -> Bool {
    !options.json && !options.quiet && isatty(STDERR_FILENO) != 0
}

private func directProgressHandler(_ options: Options) -> AESCryptProgressHandler? {
    guard showsProgress(options) else { return nil }
    var lastPercent = -1
    return { update in
        let percent = Int(update.fraction * 100)
        guard percent != lastPercent else { return }
        lastPercent = percent
        FileHandle.standardError.write(Data("\r\(percent)%".utf8))
    }
}

private func batchProgressHandler(_ options: Options) -> ((AESCryptBatchProgress) -> Void)? {
    guard showsProgress(options) else { return nil }
    var lastPercent = -1
    return { update in
        let percent = Int(update.overallFraction * 100)
        guard percent != lastPercent else { return }
        lastPercent = percent
        FileHandle.standardError.write(Data("\r\(percent)%".utf8))
    }
}

private func clearProgress(_ options: Options) {
    if showsProgress(options) {
        FileHandle.standardError.write(Data("\r".utf8))
    }
}

private struct FailureDescription {
    let code: Int32
    let kind: String
    let message: String
}

private func describe(_ failure: AESCryptBatchFailure) -> FailureDescription {
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
            message: message(for: issue)
        )
    }
}

private func aggregateExitCode(_ results: [AESCryptBatchResult]) -> Int32 {
    var codes = Set<Int32>()
    for result in results {
        if let failure = result.failure {
            codes.insert(describe(failure).code)
        }
    }
    return preferredCode(in: codes)
}

private func preferredCode(in codes: Set<Int32>) -> Int32 {
    for code: Int32 in [130, 2, 3, 4, 5] where codes.contains(code) {
        return code
    }
    return codes.isEmpty ? 0 : 1
}

private func message(for error: Error) -> String {
    if let cliError = error as? CLIError {
        return cliError.message
    }
    return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
}

private func message(for error: AESCryptError) -> String {
    error.errorDescription ?? "Unknown encryption error."
}

private func message(for issue: AESCryptBatchIssue) -> String {
    switch issue {
    case .tooManyFiles(let maximum):
        return "Too many files. The limit is \(maximum)."
    case .notAFile:
        return "This is a folder or document package, not a regular file. Zip it first to encrypt it."
    case .alreadyEncrypted:
        return "This is already an AES Crypt file. Use decrypt instead."
    case .notEncrypted:
        return "This is not an AES Crypt file. Use encrypt instead."
    case .invalidAESFile:
        return "This is not a valid AES Crypt file."
    case .unsupportedVersion(let version):
        return "AES Crypt stream format \(version) is not supported."
    case .outputExists(let path):
        return "An output file already exists at \(path)."
    case .sameFile:
        return "The input and output are the same file."
    case .inspectFailed(let detail):
        return "Could not inspect the file: \(detail)"
    }
}

private func exitCode(for error: Error) -> Int32 {
    if let cliError = error as? CLIError {
        return cliError.code
    }
    guard let aesError = error as? AESCryptError else {
        return 1
    }
    return exitCode(for: aesError)
}

private func exitCode(for error: AESCryptError) -> Int32 {
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

private func exitCode(for issue: AESCryptBatchIssue) -> Int32 {
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

private func kind(for error: AESCryptError) -> String {
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

private func kind(for issue: AESCryptBatchIssue) -> String {
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

private enum CLIError: Error {
    case usage(String)
    case batchLimit(String)
    case io(String)

    var message: String {
        switch self {
        case .usage(let detail):
            return "\(detail)\n\n\(usageText)"
        case .batchLimit(let detail), .io(let detail):
            return detail
        }
    }

    var code: Int32 {
        switch self {
        case .usage, .batchLimit:
            return 1
        case .io:
            return 5
        }
    }
}
