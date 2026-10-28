import AESCryptKit
import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum Mode {
        case encrypt
        case decrypt
    }

    @Published private(set) var fileURL: URL?
    @Published private(set) var mode: Mode = .encrypt
    @Published private(set) var info: AESFileInfo?
    @Published private(set) var isWorking = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var completedURL: URL?
    @Published private(set) var errorMessage: String?
    @Published private(set) var notice: String?

    @Published var password = ""
    @Published var confirmation = ""
    @Published var showPassword = false
    @Published var format: AESFormatVersion = .v2 {
        didSet {
            UserDefaults.standard.set(Int(format.rawValue), forKey: "outputFormat")
        }
    }

    private var cancellation: CancellationFlag?
    private var workTask: Task<Void, Never>?

    init() {
        let saved = UserDefaults.standard.integer(forKey: "outputFormat")
        format = saved == 3 ? .v3 : .v2
    }

    var canStart: Bool {
        guard fileURL != nil, !isWorking else { return false }
        guard !password.isEmpty else { return false }
        if mode == .encrypt, password != confirmation { return false }
        return true
    }

    func open(urls: [URL]) {
        guard let first = urls.first else { return }
        open(url: first, preferredMode: nil)
        if urls.count > 1 {
            notice = "One file at a time. Opened \(first.lastPathComponent)."
        }
    }

    func open(url: URL, preferredMode: Mode?) {
        reset()
        notice = nil

        let inspection = try? AESCrypt.inspect(url: url)

        switch (preferredMode, inspection) {
        case (.encrypt, .some):
            errorMessage = "This file is already encrypted."
            return
        case (.decrypt, .none):
            errorMessage = "This is not a valid AES Crypt file."
            return
        case (_, .some(let info)):
            self.info = info
            mode = .decrypt
            fileURL = url
        case (_, .none):
            if url.pathExtension.lowercased() == "aes" {
                errorMessage = "This file has a .aes extension but is not a valid AES Crypt file."
                return
            }
            info = nil
            mode = .encrypt
            fileURL = url
        }
    }

    func clear() {
        cancel()
        reset()
        notice = nil
    }

    func start() {
        guard canStart, let input = fileURL else { return }
        errorMessage = nil
        completedURL = nil
        progress = 0
        isWorking = true

        let output = uniqueOutput(for: input)
        let password = password
        let format = format
        let mode = mode
        let flag = CancellationFlag()
        cancellation = flag

        workTask = Task.detached(priority: .userInitiated) {
            do {
                if mode == .decrypt {
                    try AESCrypt.decrypt(
                        url: input,
                        to: output,
                        password: password,
                        progress: { update in
                            DispatchQueue.main.async {
                                self.progress = update.fraction
                            }
                        },
                        isCancelled: { flag.isCancelled }
                    )
                } else {
                    try AESCrypt.encrypt(
                        url: input,
                        to: output,
                        password: password,
                        format: format,
                        progress: { update in
                            DispatchQueue.main.async {
                                self.progress = update.fraction
                            }
                        },
                        isCancelled: { flag.isCancelled }
                    )
                }
                await MainActor.run {
                    self.isWorking = false
                    self.progress = 1
                    self.completedURL = output
                    self.password = ""
                    self.confirmation = ""
                }
            } catch {
                await MainActor.run {
                    self.isWorking = false
                    if case AESCryptError.cancelled = error {
                        self.errorMessage = nil
                    } else {
                        self.errorMessage = Self.message(for: error)
                    }
                }
            }
        }
    }

    func cancel() {
        cancellation?.cancel()
        workTask?.cancel()
        cancellation = nil
        workTask = nil
        isWorking = false
    }

    func reveal() {
        guard let completedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([completedURL])
    }

    private func reset() {
        cancel()
        fileURL = nil
        info = nil
        isWorking = false
        progress = 0
        completedURL = nil
        errorMessage = nil
        password = ""
        confirmation = ""
    }

    private func uniqueOutput(for input: URL) -> URL {
        let base: URL
        if mode == .encrypt {
            base = input.appendingPathExtension("aes")
        } else if input.pathExtension.lowercased() == "aes" {
            base = input.deletingPathExtension()
        } else {
            base = input.appendingPathExtension("decrypted")
        }

        guard FileManager.default.fileExists(atPath: base.path) else { return base }

        let directory = base.deletingLastPathComponent()
        let name = base.lastPathComponent as NSString
        let extensionName = name.pathExtension
        let stem = name.deletingPathExtension
        for index in 1...999 {
            let candidateName = extensionName.isEmpty
                ? "\(stem) (\(index))"
                : "\(stem) (\(index)).\(extensionName)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return base
    }

    private static func message(for error: Error) -> String {
        if let aesError = error as? AESCryptError {
            switch aesError {
            case .wrongPassword:
                return "Wrong password. Try again."
            case .authenticationFailed:
                return "The file is corrupt or was modified. Nothing was written."
            case .outputExists:
                return "An output file with that name already exists."
            default:
                return aesError.errorDescription ?? "Something went wrong."
            }
        }
        return error.localizedDescription
    }
}

final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}
