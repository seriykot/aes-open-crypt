import Darwin
import Foundation

struct FileIdentity: Equatable {
    let systemNumber: UInt64
    let fileNumber: UInt64
}

enum FileSafety {
    /// Refuse to run when the output path resolves to the same file as the
    /// input. Covers the same path, `..`, symlinks and hard links.
    static func ensureDistinct(input: URL, output: URL) throws {
        guard let inputIdentity = identity(of: input),
              let outputIdentity = identity(of: output) else {
            return
        }
        guard inputIdentity != outputIdentity else {
            throw AESCryptError.sameFile
        }
    }

    static func identity(of url: URL) -> FileIdentity? {
        let resolved = url.resolvingSymlinksInPath()
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path),
              let systemNumber = attributes[.systemNumber] as? NSNumber,
              let fileNumber = attributes[.systemFileNumber] as? NSNumber else {
            return nil
        }
        return FileIdentity(
            systemNumber: systemNumber.uint64Value,
            fileNumber: fileNumber.uint64Value
        )
    }
}

enum TemporaryFile {
    /// Creates a brand-new file next to the destination. `O_EXCL` guarantees
    /// that an existing file is never opened or truncated, even if the random
    /// name collides with something already on disk.
    static func create(
        nextTo outputURL: URL,
        name: String = ".aesopen-\(UUID().uuidString).tmp"
    ) throws -> (url: URL, handle: FileHandle) {
        let url = outputURL.deletingLastPathComponent().appendingPathComponent(name)
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        }
        guard descriptor >= 0 else {
            let code = errno
            throw AESCryptError.io(
                "could not create a temporary file next to \(outputURL.path): \(String(cString: strerror(code)))"
            )
        }
        guard fchmod(descriptor, 0o600) == 0 else {
            let code = errno
            close(descriptor)
            throw AESCryptError.io(
                "could not set permissions on the temporary file: \(String(cString: strerror(code)))"
            )
        }
        return (url, FileHandle(fileDescriptor: descriptor, closeOnDealloc: true))
    }
}
