import AppKit
import Foundation

/// Best-effort installation of the bundled `aesopen` command line tool.
///
/// The `.pkg` installer creates the link as root. This type covers the
/// portable `.zip` path: first launch tries the same link, and the menu item
/// repairs it after the app moves. It never overwrites an unrelated binary.
@MainActor
enum CLIInstaller {
    private static let binDirectory = URL(fileURLWithPath: "/usr/local/bin", isDirectory: true)
    private static let toolName = "aesopen"

    static var bundledCLI: URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let cli = resources.appendingPathComponent("bin/\(toolName)")
        return FileManager.default.isExecutableFile(atPath: cli.path) ? cli : nil
    }

    static func ensureInstalled() {
        guard let cli = bundledCLI else { return }
        let link = binDirectory.appendingPathComponent(toolName)

        if pointsTo(link, cli: cli) {
            return
        }

        if exists(link) {
            showOnce(
                key: "cliInstaller.conflict.\(link.path)",
                title: "Command line tool not installed",
                message: """
                \(link.path) already exists and does not point to this app.

                To replace it yourself, run:

                \(manualCommand(cli: cli, link: link, administrator: true))
                """
            )
            return
        }

        if isWritable(binDirectory) {
            install(cli: cli, link: link)
            return
        }

        if let localBin = localBinDirectory(), isWritable(localBin), isOnPath(localBin) {
            let localLink = localBin.appendingPathComponent(toolName)
            if pointsTo(localLink, cli: cli) {
                return
            }
            if exists(localLink) {
                showOnce(
                    key: "cliInstaller.conflict.\(localLink.path)",
                    title: "Command line tool not installed",
                    message: """
                    \(localLink.path) already exists and does not point to this app.

                    To replace it yourself, run:

                    \(manualCommand(cli: cli, link: localLink, administrator: false))
                    """
                )
                return
            }
            install(cli: cli, link: localLink)
            return
        }

        showOnce(
            key: "cliInstaller.manual",
            title: "Install the command line tool",
            message: """
            aesopen was not installed automatically because /usr/local/bin is not writable.

            To install it yourself, run:

            \(manualCommand(cli: cli, link: link, administrator: true))
            """
        )
    }

    static func repair() {
        guard let cli = bundledCLI else {
            alert(
                title: "Command line tool unavailable",
                message: "This copy of AES Open Crypt does not contain the bundled aesopen tool."
            )
            return
        }

        let link = binDirectory.appendingPathComponent(toolName)

        if pointsTo(link, cli: cli) {
            alert(
                title: "Command line tool is installed",
                message: "\(link.path) already points to this app."
            )
            return
        }

        if exists(link), !isStaleAppLink(link) {
            alert(
                title: "Cannot replace \(link.path)",
                message: """
                That path already exists and does not point to this app. It was left untouched.

                To replace it yourself, run:

                \(manualCommand(cli: cli, link: link, administrator: true))
                """
            )
            return
        }

        if isWritable(binDirectory) {
            do {
                try replaceLink(link, with: cli)
                alert(
                    title: "Command line tool repaired",
                    message: "\(link.path) now points to this app."
                )
            } catch {
                alert(
                    title: "Could not repair the command line tool",
                    message: """
                    \(error.localizedDescription)

                    You can run:

                    \(manualCommand(cli: cli, link: link, administrator: true))
                    """
                )
            }
            return
        }

        installWithAdministrator(cli: cli, link: link)
    }

    private static func install(cli: URL, link: URL) {
        do {
            try replaceLink(link, with: cli)
            showOnce(
                key: "cliInstaller.installed.\(link.path)",
                title: "Command line tool installed",
                message: "aesopen is now available at \(link.path)."
            )
        } catch {
            showOnce(
                key: "cliInstaller.failed.\(link.path)",
                title: "Could not install the command line tool",
                message: """
                \(error.localizedDescription)

                To install it yourself, run:

                \(manualCommand(cli: cli, link: link, administrator: true))
                """
            )
        }
    }

    private static func installWithAdministrator(cli: URL, link: URL) {
        let directory = link.deletingLastPathComponent().path
        let script = """
        do shell script "/bin/mkdir -p " & quoted form of \(appleScriptString(directory)) & " && /bin/ln -sfn " & quoted form of \(appleScriptString(cli.path)) & " " & quoted form of \(appleScriptString(link.path)) with administrator privileges
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                alert(
                    title: "Command line tool repaired",
                    message: "\(link.path) now points to this app."
                )
            } else {
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let detail = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                alert(
                    title: "Could not repair the command line tool",
                    message: detail.isEmpty
                        ? "osascript exited with status \(process.terminationStatus)."
                        : detail
                )
            }
        } catch {
            alert(
                title: "Could not repair the command line tool",
                message: error.localizedDescription
            )
        }
    }

    private static func replaceLink(_ link: URL, with cli: URL) throws {
        if exists(link) {
            try FileManager.default.removeItem(at: link)
        }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: cli)
    }

    private static func pointsTo(_ link: URL, cli: URL) -> Bool {
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else {
            return false
        }
        let resolved = URL(fileURLWithPath: destination, relativeTo: link.deletingLastPathComponent())
        return resolved.resolvingSymlinksInPath().path == cli.resolvingSymlinksInPath().path
    }

    /// A dangling link left by an earlier copy of this app is safe to replace.
    private static func isStaleAppLink(_ link: URL) -> Bool {
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else {
            return false
        }
        return destination.hasSuffix("/AES Open Crypt.app/Contents/Resources/bin/aesopen")
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path) || isSymlink(url)
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private static func isWritable(_ directory: URL) -> Bool {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            return isDirectory.boolValue && FileManager.default.isWritableFile(atPath: directory.path)
        }
        return FileManager.default.isWritableFile(atPath: directory.deletingLastPathComponent().path)
    }

    private static func localBinDirectory() -> URL? {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin", isDirectory: true)
    }

    private static func isOnPath(_ directory: URL) -> Bool {
        let target = directory.standardizedFileURL.path
        let entries = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        return entries.contains { URL(fileURLWithPath: $0).standardizedFileURL.path == target }
    }

    private static func manualCommand(cli: URL, link: URL, administrator: Bool) -> String {
        let prefix = administrator ? "sudo " : ""
        let directory = link.deletingLastPathComponent().path
        return "\(prefix)mkdir -p \(shellQuote(directory)) && \(prefix)ln -sfn \(shellQuote(cli.path)) \(shellQuote(link.path))"
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func showOnce(key: String, title: String, message: String) {
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        alert(title: title, message: message)
    }

    private static func alert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
