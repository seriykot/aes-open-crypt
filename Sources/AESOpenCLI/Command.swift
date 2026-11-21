import AESCryptKit
import Foundation

/// The three things `aesopen` does with files.
public enum Command: String, Equatable, Sendable {
    case info
    case encrypt
    case decrypt
}

/// Parsed command-line options, before any of them are applied.
public struct Options: Equatable, Sendable {
    public var output: String?
    public var password: String?
    public var passwordFile: String?
    public var format: AESOutputFormat = .v3
    public var hint: String?
    public var iterations: UInt32 = 600_000
    public var json = false
    public var quiet = false
    public var inputs: [String] = []

    public init() {}
}

/// What a parsed command line asks for.
public enum CLIParseResult: Equatable, Sendable {
    /// Print the help text to standard out and exit 0.
    case help
    /// Print the version to standard out and exit 0.
    case version
    /// Print the help text to standard out and exit 1.
    case missingCommand
    /// Run `command` with `options`.
    case command(Command, Options)
}

/// Turn raw arguments into a command and its options.
///
/// Only arguments are examined here: no file is touched and no prompt is
/// shown, so every usage error surfaces before the command line does any work.
/// `-h` and `-v` win the moment they appear, exactly like the original parser.
public func parse(_ arguments: [String]) throws -> CLIParseResult {
    var arguments = arguments
    guard let first = arguments.first else {
        return .missingCommand
    }
    arguments.removeFirst()

    let command: Command
    switch first {
    case "-h", "--help", "help":
        return .help
    case "-v", "--version", "version":
        return .version
    default:
        guard let parsed = Command(rawValue: first) else {
            throw CLIError.usage("unknown command '\(first)'")
        }
        command = parsed
    }

    var options = Options()
    if let early = try parseOptions(arguments, into: &options) {
        return early
    }
    try validate(command: command, options: &options)
    return .command(command, options)
}

/// Parse the argument list into `options`.
///
/// Returns a result only when a flag asks to stop early (`-h`/`-v`); otherwise
/// returns nil and leaves the caller with the filled-in options.
private func parseOptions(_ arguments: [String], into options: inout Options) throws -> CLIParseResult? {
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
            let raw = try value(after: &index, in: arguments, name: argument)
            guard let format = AESOutputFormat(cliText: raw) else {
                throw CLIError.usage("unknown format '\(raw.lowercased())'")
            }
            options.format = format
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
            return .version
        case "-h", "--help":
            return .help
        default:
            if argument.hasPrefix("-"), argument != "-" {
                throw CLIError.usage("unknown option '\(argument)'")
            }
            options.inputs.append(argument)
        }
        index += 1
    }

    return nil
}

private func value(after index: inout Int, in arguments: [String], name: String) throws -> String {
    index += 1
    guard index < arguments.count else {
        throw CLIError.usage("\(name) needs a value")
    }
    return arguments[index]
}

/// Reject combinations the command line cannot honor.
private func validate(command: Command, options: inout Options) throws {
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
        options.hint = AESPasswordHint.normalize(hint)
    }
}
