import AESCryptKit
import Darwin
import Foundation

private let usageText = """
Usage:
  aesopen info <file>
  aesopen decrypt <file> [-o <output>] [--password <password>]
  aesopen encrypt <file> [-o <output>] [--format v2|v3] [--iterations <n>]
                         [--password <password>]

Options:
  -o, --output <path>    Output path. Defaults to the input without .aes when
                         decrypting, or the input plus .aes when encrypting.
  --format <v2|v3>       Output stream format. Default: v2.
  --iterations <n>       KDF iterations for v3. Default: 600000.
  --password <password>  Password on the command line. Visible in process
                         lists. Prefer the interactive prompt.
  -h, --help             Show this help.
"""

nonisolated(unsafe) private var interrupted: sig_atomic_t = 0

private struct Options {
    var output: String?
    var password: String?
    var format: AESFormatVersion = .v2
    var iterations: UInt32 = 600_000
}

private enum Command {
    case info
    case encrypt
    case decrypt
    case help
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
    case "info":
        command = .info
    case "encrypt":
        command = .encrypt
    case "decrypt":
        command = .decrypt
    case "-h", "--help", "help":
        command = .help
    default:
        throw CLIError.usage("unknown command '\(first)'")
    }

    if command == .help {
        print(usageText)
        return
    }

    var options = Options()
    var inputPath: String?
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "-o", "--output":
            index += 1
            guard index < arguments.count else {
                throw CLIError.usage("\(argument) needs a path")
            }
            options.output = arguments[index]
        case "--password":
            index += 1
            guard index < arguments.count else {
                throw CLIError.usage("--password needs a value")
            }
            options.password = arguments[index]
        case "--format":
            index += 1
            guard index < arguments.count else {
                throw CLIError.usage("--format needs v2 or v3")
            }
            switch arguments[index].lowercased() {
            case "v2", "2":
                options.format = .v2
            case "v3", "3":
                options.format = .v3
            default:
                throw CLIError.usage("unknown format '\(arguments[index])'")
            }
        case "--iterations":
            index += 1
            guard index < arguments.count, let value = UInt32(arguments[index]) else {
                throw CLIError.usage("--iterations needs a number")
            }
            options.iterations = value
        case "-h", "--help":
            print(usageText)
            return
        default:
            if argument.hasPrefix("-") {
                throw CLIError.usage("unknown option '\(argument)'")
            }
            guard inputPath == nil else {
                throw CLIError.usage("only one input file is supported")
            }
            inputPath = argument
        }
        index += 1
    }

    guard let inputPath else {
        throw CLIError.usage("missing input file")
    }
    let input = URL(fileURLWithPath: inputPath)

    switch command {
    case .info:
        try showInfo(input)
    case .encrypt:
        let output = options.output.map { URL(fileURLWithPath: $0) }
            ?? input.appendingPathExtension("aes")
        let password = try resolvePassword(options.password, confirm: true)
        try transform(input: input, output: output, password: password, encrypt: true, options: options)
    case .decrypt:
        let output = options.output.map { URL(fileURLWithPath: $0) }
            ?? defaultDecryptOutput(for: input)
        let password = try resolvePassword(options.password, confirm: false)
        try transform(input: input, output: output, password: password, encrypt: false, options: options)
    case .help:
        break
    }
}

private func showInfo(_ url: URL) throws {
    let info = try AESCrypt.inspect(url: url)
    print("file: \(url.path)")
    print("stream format: \(info.version.rawValue)")
    print("size: \(info.fileSize) bytes")
    print("ciphertext: \(info.ciphertextLength) bytes")
    if let iterations = info.kdfIterations {
        print("kdf iterations: \(iterations)")
    }
    if !info.extensions.isEmpty {
        print("extensions:")
        for item in info.extensions where !item.identifier.isEmpty {
            let value = String(data: item.value, encoding: .utf8) ?? "<binary>"
            print("  \(item.identifier) = \(value)")
        }
    }
}

private func transform(
    input: URL,
    output: URL,
    password: String,
    encrypt: Bool,
    options: Options
) throws {
    signal(SIGINT) { _ in interrupted = 1 }

    let isTerminal = isatty(STDERR_FILENO) != 0
    var lastPercent = -1
    let progress: AESCryptProgressHandler = { update in
        guard isTerminal else { return }
        let percent = Int(update.fraction * 100)
        guard percent != lastPercent else { return }
        lastPercent = percent
        FileHandle.standardError.write(Data("\r\(percent)%".utf8))
    }

    if encrypt {
        try AESCrypt.encrypt(
            url: input,
            to: output,
            password: password,
            format: options.format,
            iterations: options.iterations,
            progress: progress,
            isCancelled: { interrupted != 0 }
        )
    } else {
        try AESCrypt.decrypt(
            url: input,
            to: output,
            password: password,
            progress: progress,
            isCancelled: { interrupted != 0 }
        )
    }

    if isTerminal {
        FileHandle.standardError.write(Data("\r".utf8))
    }
    print(output.path)
}

private func resolvePassword(_ supplied: String?, confirm: Bool) throws -> String {
    if let supplied {
        return supplied
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

private func readPassword(_ prompt: String) -> String? {
    FileHandle.standardError.write(Data(prompt.utf8))
    defer { FileHandle.standardError.write(Data("\n".utf8)) }
    guard let pointer = getpass("") else { return nil }
    return String(cString: pointer)
}

private func defaultDecryptOutput(for input: URL) -> URL {
    if input.pathExtension.lowercased() == "aes" {
        return input.deletingPathExtension()
    }
    return input.appendingPathExtension("decrypted")
}

private func message(for error: Error) -> String {
    if let cliError = error as? CLIError {
        return cliError.message
    }
    return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
}

private func exitCode(for error: Error) -> Int32 {
    if error is CLIError {
        return 1
    }
    guard let aesError = error as? AESCryptError else {
        return 1
    }
    switch aesError {
    case .wrongPassword:
        return 2
    case .notAnAESFile, .truncated, .corrupt, .authenticationFailed:
        return 3
    case .unsupportedVersion:
        return 4
    case .outputExists, .io:
        return 5
    case .cancelled:
        return 130
    }
}

private enum CLIError: Error {
    case usage(String)

    var message: String {
        switch self {
        case .usage(let detail):
            return "\(detail)\n\n\(usageText)"
        }
    }
}
