import Foundation

/// The ownership and access a finished output file should carry.
///
/// The temporary file is always created owner-only; the policy is applied to
/// the destination after the finished file is moved into place.
enum OutputPermission {
    /// 0o600 — decrypted plaintext belongs to the user alone.
    case ownerOnly
    /// 0o644 — encrypted ciphertext is safe to share with the group.
    case groupReadable

    var mode: Int {
        switch self {
        case .ownerOnly:
            return 0o600
        case .groupReadable:
            return 0o644
        }
    }
}

/// The single place that turns a stream of writes into a finished output file.
///
/// Writes go to a brand-new temporary file next to the destination. The
/// destination only appears when the writer returns without throwing, so a
/// failed or cancelled run never leaves a partial plaintext or ciphertext
/// behind, and an existing destination is never replaced or truncated.
enum AtomicOutput {
    /// - Parameters:
    ///   - outputURL: the destination that appears once `body` succeeds.
    ///   - permissions: the policy applied to the destination after the move.
    ///   - body: writes the whole output; it owns the handle only for the
    ///     duration of the call and must not close it.
    static func write(
        to outputURL: URL,
        permissions: OutputPermission,
        _ body: (FileHandle) throws -> Void
    ) throws {
        let temporary = try TemporaryFile.create(nextTo: outputURL)
        let tempURL = temporary.url
        let handle = temporary.handle

        var moved = false
        defer {
            try? handle.close()
            if !moved {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }

        try body(handle)

        try handle.synchronize()
        try handle.close()

        do {
            try FileManager.default.moveItem(at: tempURL, to: outputURL)
            moved = true
        } catch {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                throw AESCryptError.outputExists(outputURL.path)
            }
            throw AESCryptError.io(error.localizedDescription)
        }

        try? FileManager.default.setAttributes(
            [.posixPermissions: permissions.mode],
            ofItemAtPath: outputURL.path
        )
    }
}
