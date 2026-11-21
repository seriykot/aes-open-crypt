import AESCryptKit
import Foundation
import XCTest
@testable import AESOpenCLI

/// The command line's grammar, with no process and no file system involved.
final class ParsingTests: XCTestCase {
    // MARK: - Top-level commands

    func testMissingCommand() throws {
        XCTAssertEqual(try parse([]), .missingCommand)
    }

    func testHelpSpellings() throws {
        for argument in ["-h", "--help", "help"] {
            XCTAssertEqual(try parse([argument]), .help, "failed for \(argument)")
        }
    }

    func testVersionSpellings() throws {
        for argument in ["-v", "--version", "version"] {
            XCTAssertEqual(try parse([argument]), .version, "failed for \(argument)")
        }
    }

    func testHelpAndVersionWinInsideOptions() throws {
        XCTAssertEqual(try parse(["encrypt", "a.txt", "-h"]), .help)
        XCTAssertEqual(try parse(["decrypt", "--version"]), .version)
        XCTAssertEqual(try parse(["info", "--json", "--help"]), .help)
    }

    func testUnknownCommandIsAUsageError() {
        assertUsageError(["frobnicate"], contains: "unknown command 'frobnicate'")
    }

    func testUnknownOptionIsAUsageError() {
        assertUsageError(["encrypt", "--bogus", "a.txt"], contains: "unknown option '--bogus'")
    }

    func testOptionNeedsAValue() {
        assertUsageError(["encrypt", "-o"], contains: "-o needs a value")
        assertUsageError(["encrypt", "--format"], contains: "--format needs a value")
    }

    func testMissingInputFile() {
        assertUsageError(["encrypt"], contains: "missing input file")
        assertUsageError(["encrypt", "--json"], contains: "missing input file")
    }

    // MARK: - Commands and defaults

    func testDefaults() throws {
        let (command, options) = try parsed(["encrypt", "a.txt"])

        XCTAssertEqual(command, .encrypt)
        XCTAssertEqual(options.inputs, ["a.txt"])
        XCTAssertEqual(options.format, .v3)
        XCTAssertEqual(options.iterations, 600_000)
        XCTAssertNil(options.output)
        XCTAssertNil(options.password)
        XCTAssertNil(options.passwordFile)
        XCTAssertNil(options.hint)
        XCTAssertFalse(options.json)
        XCTAssertFalse(options.quiet)
    }

    func testEveryCommandParses() throws {
        XCTAssertEqual(try parsed(["info", "a.aes"]).0, .info)
        XCTAssertEqual(try parsed(["encrypt", "a.txt"]).0, .encrypt)
        XCTAssertEqual(try parsed(["decrypt", "a.aes"]).0, .decrypt)
    }

    // MARK: - Output

    func testOutputWithOneInput() throws {
        let (_, options) = try parsed(["encrypt", "-o", "out.aes", "a.txt"])
        XCTAssertEqual(options.output, "out.aes")
    }

    func testOutputWithMultipleInputsIsRejected() {
        assertUsageError(
            ["encrypt", "-o", "out.aes", "a.txt", "b.txt"],
            contains: "-o/--output is valid only with a single input file"
        )
    }

    func testInfoWithOutputIsRejected() {
        assertUsageError(["info", "-o", "out", "a.aes"], contains: "info does not write an output file")
    }

    // MARK: - Format

    func testFormatAliases() throws {
        XCTAssertEqual(try parsed(["encrypt", "--format", "v2", "a.txt"]).1.format, .v2)
        XCTAssertEqual(try parsed(["encrypt", "--format", "2", "a.txt"]).1.format, .v2)
        XCTAssertEqual(try parsed(["encrypt", "--format", "v3", "a.txt"]).1.format, .v3)
        XCTAssertEqual(try parsed(["encrypt", "--format", "3", "a.txt"]).1.format, .v3)
        XCTAssertEqual(try parsed(["encrypt", "--format", "V2", "a.txt"]).1.format, .v2)
    }

    func testUnknownFormatIsRejected() {
        assertUsageError(["encrypt", "--format", "v9", "a.txt"], contains: "unknown format 'v9'")
        assertUsageError(["encrypt", "--format", "V9", "a.txt"], contains: "unknown format 'v9'")
        assertUsageError(["encrypt", "--format", "1", "a.txt"], contains: "unknown format '1'")
    }

    // MARK: - Iterations

    func testIterationsAcceptsAPositiveNumber() throws {
        XCTAssertEqual(try parsed(["encrypt", "--iterations", "1000", "a.txt"]).1.iterations, 1000)
    }

    func testIterationsRejectsZeroAndText() {
        assertUsageError(
            ["encrypt", "--iterations", "0", "a.txt"],
            contains: "--iterations needs a positive number"
        )
        assertUsageError(
            ["encrypt", "--iterations", "abc", "a.txt"],
            contains: "--iterations needs a positive number"
        )
        assertUsageError(
            ["encrypt", "--iterations", "-1", "a.txt"],
            contains: "--iterations needs a positive number"
        )
    }

    // MARK: - Password

    func testPasswordAndPasswordFileCannotBeCombined() {
        assertUsageError(
            ["encrypt", "--password", "pw", "--password-file", "f", "a.txt"],
            contains: "--password and --password-file cannot be combined"
        )
    }

    func testPasswordOptionsAreKept() throws {
        XCTAssertEqual(try parsed(["encrypt", "--password", "pw", "a.txt"]).1.password, "pw")
        XCTAssertEqual(try parsed(["decrypt", "--password-file", "p", "a.aes"]).1.passwordFile, "p")
    }

    // MARK: - Hint

    func testHintIsEncryptOnly() {
        assertUsageError(
            ["decrypt", "--hint", "pet name", "a.aes"],
            contains: "--hint is valid only with encrypt"
        )
        assertUsageError(["info", "--hint", "pet name", "a.aes"], contains: "--hint is valid only with encrypt")
    }

    func testHintIsLimitedToTheProductMaximum() {
        let tooLong = String(repeating: "a", count: AESPasswordHint.maximumLength + 1)
        assertUsageError(
            ["encrypt", "--hint", tooLong, "a.txt"],
            contains: "--hint is limited to \(AESPasswordHint.maximumLength) characters"
        )
    }

    func testHintIsTrimmedAndBlankBecomesNil() throws {
        XCTAssertEqual(try parsed(["encrypt", "--hint", "  pet name \n", "a.txt"]).1.hint, "pet name")
        XCTAssertNil(try parsed(["encrypt", "--hint", "   ", "a.txt"]).1.hint)
        XCTAssertNil(try parsed(["encrypt", "--hint", "", "a.txt"]).1.hint)
    }

    // MARK: - Positionals

    func testDoubleDashMakesEverythingPositional() throws {
        XCTAssertEqual(try parsed(["encrypt", "--", "-o"]).1.inputs, ["-o"])
        XCTAssertEqual(try parsed(["encrypt", "--", "--json", "--"]).1.inputs, ["--json", "--"])
    }

    func testSingleDashIsAnInput() throws {
        let (_, options) = try parsed(["encrypt", "-"])
        XCTAssertEqual(options.inputs, ["-"])
    }

    func testInputOrderIsKept() throws {
        let (_, options) = try parsed(["encrypt", "b.txt", "a.txt", "b.txt"])
        XCTAssertEqual(options.inputs, ["b.txt", "a.txt", "b.txt"])
    }

    // MARK: - Helpers

    private func parsed(
        _ arguments: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (Command, Options) {
        let result = try parse(arguments)
        guard case .command(let command, let options) = result else {
            XCTFail("expected a command, got \(result)", file: file, line: line)
            return (.encrypt, Options())
        }
        return (command, options)
    }

    private func assertUsageError(
        _ arguments: [String],
        contains fragment: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try parse(arguments), file: file, line: line) { error in
            guard let cliError = error as? CLIError else {
                return XCTFail("expected a CLIError, got \(error)", file: file, line: line)
            }
            guard case .usage(let detail) = cliError else {
                return XCTFail("expected .usage, got \(cliError)", file: file, line: line)
            }
            XCTAssertTrue(
                detail.contains(fragment),
                "expected '\(detail)' to contain '\(fragment)'",
                file: file,
                line: line
            )
            XCTAssertEqual(cliError.code, 1, "usage errors exit 1", file: file, line: line)
        }
    }
}
