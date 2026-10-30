import Foundation

public enum AESCryptBatchMode: String, Sendable {
    case encrypt
    case decrypt
}

public enum AESCryptBatchOutputPolicy: Sendable {
    case unique
    case strict
}

public enum AESCryptBatchIssue: Error, Equatable, Sendable {
    case tooManyFiles(Int)
    case notAFile
    case alreadyEncrypted
    case notEncrypted
    case invalidAESFile
    case unsupportedVersion(UInt8)
    case outputExists(String)
    case sameFile
    case inspectFailed(String)
}

public struct AESCryptBatchItem: Sendable, Equatable {
    public let input: URL
    public let output: URL
    public let mode: AESCryptBatchMode
    public let info: AESFileInfo?
    public let issue: AESCryptBatchIssue?

    public init(
        input: URL,
        output: URL,
        mode: AESCryptBatchMode,
        info: AESFileInfo? = nil,
        issue: AESCryptBatchIssue? = nil
    ) {
        self.input = input
        self.output = output
        self.mode = mode
        self.info = info
        self.issue = issue
    }
}

public struct AESCryptBatchPlan: Sendable {
    public let items: [AESCryptBatchItem]

    public init(items: [AESCryptBatchItem]) {
        self.items = items
    }

    public var runnableItems: [AESCryptBatchItem] {
        items.filter { $0.issue == nil }
    }
}

public enum AESCryptBatch {
    public static let maximumFileCount = 10

    public static func plan(
        urls: [URL],
        mode: AESCryptBatchMode? = nil,
        outputPolicy: AESCryptBatchOutputPolicy = .unique,
        maximum: Int = maximumFileCount
    ) throws -> AESCryptBatchPlan {
        let uniqueURLs = deduplicate(urls)
        guard uniqueURLs.count <= maximum else {
            throw AESCryptBatchIssue.tooManyFiles(maximum)
        }

        var reserved = Set<String>()
        var items: [AESCryptBatchItem] = []
        items.reserveCapacity(uniqueURLs.count)

        for url in uniqueURLs {
            items.append(planItem(url: url, mode: mode, outputPolicy: outputPolicy, reserved: &reserved))
        }

        return AESCryptBatchPlan(items: items)
    }

    private static func deduplicate(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var unique: [URL] = []
        unique.reserveCapacity(urls.count)

        for url in urls {
            let key: String
            if let identity = FileSafety.identity(of: url) {
                key = "id:\(identity.systemNumber):\(identity.fileNumber)"
            } else {
                key = "path:\(url.standardizedFileURL.path)"
            }
            if seen.insert(key).inserted {
                unique.append(url)
            }
        }

        return unique
    }

    private static func planItem(
        url: URL,
        mode: AESCryptBatchMode?,
        outputPolicy: AESCryptBatchOutputPolicy,
        reserved: inout Set<String>
    ) -> AESCryptBatchItem {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDirectory {
            let plannedMode = mode ?? .encrypt
            return AESCryptBatchItem(
                input: url,
                output: outputURL(for: url, mode: plannedMode),
                mode: plannedMode,
                issue: .notAFile
            )
        }

        var info: AESFileInfo?
        var inspectionError: Error?
        do {
            info = try AESCrypt.inspect(url: url)
        } catch {
            inspectionError = error
        }

        let isAESExtension = url.pathExtension.lowercased() == "aes"
        let plannedMode = mode ?? (info != nil || isAESExtension ? .decrypt : .encrypt)

        var issue: AESCryptBatchIssue?
        if let error = inspectionError {
            if let aesError = error as? AESCryptError {
                switch aesError {
                case .io(let detail):
                    issue = .inspectFailed(detail)
                case .unsupportedVersion(let version):
                    issue = .unsupportedVersion(version)
                case .notAnAESFile, .truncated, .corrupt:
                    issue = issueForUnreadableFile(
                        mode: mode,
                        isAESExtension: isAESExtension
                    )
                default:
                    issue = .inspectFailed(aesError.localizedDescription)
                }
            } else {
                issue = .inspectFailed(error.localizedDescription)
            }
        } else if mode == .encrypt {
            issue = .alreadyEncrypted
        }

        let output = outputURL(for: url, mode: plannedMode)

        if issue == nil,
           let inputIdentity = FileSafety.identity(of: url),
           let outputIdentity = FileSafety.identity(of: output),
           inputIdentity == outputIdentity {
            issue = .sameFile
        }

        if issue == nil {
            switch outputPolicy {
            case .strict:
                if exists(output) || reserved.contains(reservationKey(output)) {
                    issue = .outputExists(output.path)
                } else {
                    reserved.insert(reservationKey(output))
                }
            case .unique:
                if let unique = uniqueOutput(for: output, reserved: &reserved) {
                    return AESCryptBatchItem(
                        input: url,
                        output: unique,
                        mode: plannedMode,
                        info: info,
                        issue: nil
                    )
                }
                issue = .outputExists(output.path)
            }
        }

        return AESCryptBatchItem(
            input: url,
            output: output,
            mode: plannedMode,
            info: info,
            issue: issue
        )
    }

    private static func issueForUnreadableFile(
        mode: AESCryptBatchMode?,
        isAESExtension: Bool
    ) -> AESCryptBatchIssue? {
        switch mode {
        case .encrypt:
            return nil
        case .decrypt:
            return isAESExtension ? .invalidAESFile : .notEncrypted
        case nil:
            return isAESExtension ? .invalidAESFile : nil
        }
    }

    private static func outputURL(for input: URL, mode: AESCryptBatchMode) -> URL {
        switch mode {
        case .encrypt:
            return input.appendingPathExtension("aes")
        case .decrypt:
            if input.pathExtension.lowercased() == "aes" {
                return input.deletingPathExtension()
            }
            return input.appendingPathExtension("decrypted")
        }
    }

    private static func uniqueOutput(for output: URL, reserved: inout Set<String>) -> URL? {
        if !exists(output), !reserved.contains(reservationKey(output)) {
            reserved.insert(reservationKey(output))
            return output
        }

        let directory = output.deletingLastPathComponent()
        let filename = output.lastPathComponent
        let pathExtension = output.pathExtension
        let stem = pathExtension.isEmpty
            ? filename
            : String(filename.dropLast(pathExtension.count + 1))

        for index in 1...999 {
            let candidateName = pathExtension.isEmpty
                ? "\(stem) (\(index))"
                : "\(stem) (\(index)).\(pathExtension)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !exists(candidate), !reserved.contains(reservationKey(candidate)) {
                reserved.insert(reservationKey(candidate))
                return candidate
            }
        }

        return nil
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private static func reservationKey(_ url: URL) -> String {
        url.standardizedFileURL.path.lowercased()
    }
}

public enum AESCryptBatchFailure: Error, Equatable, Sendable {
    case issue(AESCryptBatchIssue)
    case crypto(AESCryptError)
}

public struct AESCryptBatchResult: Sendable {
    public let item: AESCryptBatchItem
    public let failure: AESCryptBatchFailure?

    public init(item: AESCryptBatchItem, failure: AESCryptBatchFailure?) {
        self.item = item
        self.failure = failure
    }
}

public struct AESCryptBatchProgress: Sendable {
    public let itemIndex: Int
    public let itemCount: Int
    public let itemFraction: Double
    public let overallFraction: Double

    public init(itemIndex: Int, itemCount: Int, itemFraction: Double, overallFraction: Double) {
        self.itemIndex = itemIndex
        self.itemCount = itemCount
        self.itemFraction = itemFraction
        self.overallFraction = overallFraction
    }
}

extension AESCryptBatch {
    public static func run(
        plan: AESCryptBatchPlan,
        password: String,
        format: AESFormatVersion = .v2,
        iterations: UInt32 = 600_000,
        progress: ((AESCryptBatchProgress) -> Void)? = nil,
        isCancelled: @escaping () -> Bool = { false }
    ) -> [AESCryptBatchResult] {
        let items = plan.items
        var results: [AESCryptBatchResult] = []
        results.reserveCapacity(items.count)

        for (index, item) in items.enumerated() {
            if isCancelled() {
                for remaining in items[index...] {
                    results.append(
                        AESCryptBatchResult(item: remaining, failure: .crypto(.cancelled))
                    )
                }
                break
            }

            if let issue = item.issue {
                results.append(AESCryptBatchResult(item: item, failure: .issue(issue)))
                continue
            }

            let itemCount = items.count
            let handler: AESCryptProgressHandler? = progress.map { report in
                { itemProgress in
                    report(
                        AESCryptBatchProgress(
                            itemIndex: index,
                            itemCount: itemCount,
                            itemFraction: itemProgress.fraction,
                            overallFraction: (Double(index) + itemProgress.fraction) / Double(itemCount)
                        )
                    )
                }
            }

            do {
                switch item.mode {
                case .encrypt:
                    try AESCrypt.encrypt(
                        url: item.input,
                        to: item.output,
                        password: password,
                        format: format,
                        iterations: iterations,
                        progress: handler,
                        isCancelled: isCancelled
                    )
                case .decrypt:
                    try AESCrypt.decrypt(
                        url: item.input,
                        to: item.output,
                        password: password,
                        progress: handler,
                        isCancelled: isCancelled
                    )
                }
                results.append(AESCryptBatchResult(item: item, failure: nil))
            } catch let error as AESCryptError {
                results.append(AESCryptBatchResult(item: item, failure: .crypto(error)))
            } catch {
                results.append(
                    AESCryptBatchResult(
                        item: item,
                        failure: .crypto(.io(error.localizedDescription))
                    )
                )
            }
        }

        return results
    }
}
