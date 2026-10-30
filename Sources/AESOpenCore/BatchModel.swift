import AESCryptKit
import Combine
import Foundation

@MainActor
public final class BatchModel: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case ready
        case working
        case finished
    }

    public enum RowStatus: Equatable {
        case pending
        case running
        case succeeded
        case failed(String)
        case cancelled
    }

    public struct Row: Identifiable, Equatable {
        public let id: UUID
        public let item: AESCryptBatchItem
        public var status: RowStatus
        public var fraction: Double
    }

    public static let shared = BatchModel()

    @Published public private(set) var rows: [Row] = []
    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var overallProgress: Double = 0
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var notice: String?
    @Published public private(set) var hasMixedInputs = false

    @Published public var password = ""
    @Published public var confirmation = ""
    @Published public var showPassword = false

    @Published public var mode: AESCryptBatchMode = .encrypt {
        didSet {
            guard !isUpdatingMode, oldValue != mode else { return }
            replanForMode()
        }
    }

    @Published public var format: AESFormatVersion = .v2 {
        didSet {
            UserDefaults.standard.set(Int(format.rawValue), forKey: "outputFormat")
        }
    }

    private(set) var activeTask: Task<Void, Never>?
    private(set) var runGeneration = 0
    private var cancellation: BatchCancellationFlag?
    private var isUpdatingMode = false

    public init() {
        let saved = UserDefaults.standard.integer(forKey: "outputFormat")
        format = saved == 3 ? .v3 : .v2
    }

    public var canStart: Bool {
        guard phase == .ready, !rows.isEmpty else { return false }
        guard rows.allSatisfy({ $0.item.issue == nil }) else { return false }
        guard !password.isEmpty else { return false }
        if mode == .encrypt, password != confirmation { return false }
        return true
    }

    public var completedOutputs: [URL] {
        rows.compactMap { row in
            row.status == .succeeded ? row.item.output : nil
        }
    }

    public func add(
        urls: [URL],
        preferredMode: AESCryptBatchMode?,
        unreadableCount: Int = 0
    ) {
        guard !urls.isEmpty else {
            if let message = Self.unreadableDropMessage(unreadableCount) {
                notice = message
            }
            return
        }

        if phase == .working {
            let base = "Finish the current batch first."
            if let message = Self.unreadableDropMessage(unreadableCount) {
                notice = "\(base) \(message)"
            } else {
                notice = base
            }
            return
        }
        if phase == .finished {
            clear()
        }

        let combined = rows.map(\.item.input) + urls

        do {
            let plan = try AESCryptBatch.plan(
                urls: combined,
                mode: preferredMode,
                outputPolicy: .unique
            )
            guard !plan.items.isEmpty else { return }

            let plannedModes = Set(plan.items.map(\.mode))
            let isMixed = preferredMode == nil
                && plannedModes.contains(.encrypt)
                && plannedModes.contains(.decrypt)

            let desiredMode: AESCryptBatchMode
            if let preferredMode {
                desiredMode = preferredMode
            } else if plannedModes == [.decrypt] {
                desiredMode = .decrypt
            } else {
                desiredMode = .encrypt
            }

            isUpdatingMode = true
            mode = desiredMode
            isUpdatingMode = false

            let effectivePlan: AESCryptBatchPlan
            if isMixed {
                effectivePlan = try AESCryptBatch.plan(
                    urls: combined,
                    mode: desiredMode,
                    outputPolicy: .unique
                )
            } else {
                effectivePlan = plan
            }

            rows = effectivePlan.items.map {
                Row(id: UUID(), item: $0, status: .pending, fraction: 0)
            }
            hasMixedInputs = isMixed
            phase = .ready
            overallProgress = 0
            errorMessage = nil
            notice = Self.unreadableDropMessage(unreadableCount)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    public func remove(_ id: UUID) {
        guard phase != .working else { return }
        rows.removeAll { $0.id == id }
        if rows.isEmpty {
            clear()
        } else {
            refreshMixedFlag()
            phase = .ready
            overallProgress = 0
        }
    }

    public func clear() {
        cancellation?.cancel()
        activeTask?.cancel()
        cancellation = nil
        activeTask = nil
        runGeneration += 1
        rows = []
        phase = .idle
        overallProgress = 0
        errorMessage = nil
        notice = nil
        password = ""
        confirmation = ""
        hasMixedInputs = false
    }

    public func start() {
        guard canStart else { return }

        let plan: AESCryptBatchPlan
        do {
            plan = try AESCryptBatch.plan(
                urls: rows.map(\.item.input),
                mode: mode,
                outputPolicy: .unique
            )
        } catch {
            errorMessage = Self.message(for: error)
            return
        }
        guard !plan.items.isEmpty else { return }

        rows = plan.items.map { Row(id: UUID(), item: $0, status: .pending, fraction: 0) }
        beginRun(plan: plan)
    }

    public func retryFailed() {
        guard phase == .finished || phase == .ready else { return }

        let failedRows = rows.filter { row in
            if case .failed = row.status { return true }
            return false
        }
        guard !failedRows.isEmpty else { return }

        let plan: AESCryptBatchPlan
        do {
            plan = try AESCryptBatch.plan(
                urls: failedRows.map(\.item.input),
                mode: mode,
                outputPolicy: .unique
            )
        } catch {
            errorMessage = Self.message(for: error)
            return
        }
        guard plan.items.count == failedRows.count else { return }

        var items = plan.items.makeIterator()
        var newRows: [Row] = []
        newRows.reserveCapacity(rows.count)
        for row in rows {
            if case .failed = row.status, let item = items.next() {
                newRows.append(Row(id: UUID(), item: item, status: .pending, fraction: 0))
            } else {
                newRows.append(row)
            }
        }

        rows = newRows
        phase = .ready
        beginRun(plan: plan)
    }

    public func cancel() {
        guard phase == .working else { return }
        cancellation?.cancel()
        activeTask?.cancel()
        cancellation = nil

        for index in rows.indices {
            switch rows[index].status {
            case .pending, .running:
                rows[index].status = .cancelled
            case .succeeded, .failed, .cancelled:
                break
            }
        }
        phase = .finished
    }

    private func beginRun(plan: AESCryptBatchPlan) {
        let rowIDs = rows.filter { $0.status == .pending }.map(\.id)
        guard rowIDs.count == plan.items.count else { return }

        phase = .working
        overallProgress = 0
        errorMessage = nil
        notice = nil

        let password = self.password
        let format = self.format
        self.password = ""
        self.confirmation = ""

        runGeneration += 1
        let generation = runGeneration
        let flag = BatchCancellationFlag()
        cancellation = flag

        activeTask = Task.detached(priority: .userInitiated) { [weak self] in
            var lastIndex = -1
            var lastOverall = -1.0

            let results = AESCryptBatch.run(
                plan: plan,
                password: password,
                format: format,
                progress: { update in
                    let newItem = update.itemIndex != lastIndex
                    let moved = update.overallFraction - lastOverall >= 0.005
                    guard newItem || moved || update.overallFraction >= 1 else { return }
                    lastIndex = update.itemIndex
                    lastOverall = update.overallFraction
                    Task { @MainActor [weak self] in
                        self?.applyProgress(update, rowIDs: rowIDs, generation: generation)
                    }
                },
                isCancelled: { flag.isCancelled }
            )

            await MainActor.run { [weak self] in
                self?.applyResults(results, rowIDs: rowIDs, generation: generation)
            }
        }
    }

    func applyProgress(
        _ update: AESCryptBatchProgress,
        rowIDs: [UUID],
        generation: Int
    ) {
        guard generation == runGeneration,
              phase == .working,
              update.itemIndex >= 0,
              update.itemIndex < rowIDs.count else { return }

        let id = rowIDs[update.itemIndex]
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }

        if rows[index].status == .pending {
            rows[index].status = .running
        }
        if rows[index].status == .running {
            rows[index].fraction = update.itemFraction
            overallProgress = update.overallFraction
        }
    }

    func applyResults(
        _ results: [AESCryptBatchResult],
        rowIDs: [UUID],
        generation: Int
    ) {
        guard generation == runGeneration else { return }

        for (offset, result) in results.enumerated() where offset < rowIDs.count {
            guard let index = rows.firstIndex(where: { $0.id == rowIDs[offset] }) else {
                continue
            }

            switch result.failure {
            case .none:
                rows[index].status = .succeeded
                rows[index].fraction = 1
            case .some(.issue(let issue)):
                rows[index].status = .failed(Self.message(for: issue))
            case .some(.crypto(.cancelled)):
                rows[index].status = .cancelled
            case .some(.crypto(let error)):
                rows[index].status = .failed(Self.message(for: error))
            }
        }

        overallProgress = 1
        phase = .finished
        cancellation = nil
    }

    private func replanForMode() {
        guard !isUpdatingMode, !rows.isEmpty, phase != .working else { return }

        let inputs = rows.map(\.item.input)
        guard let plan = try? AESCryptBatch.plan(
            urls: inputs,
            mode: mode,
            outputPolicy: .unique
        ) else {
            return
        }

        var newRows: [Row] = []
        newRows.reserveCapacity(plan.items.count)
        for (index, item) in plan.items.enumerated() {
            let id = index < rows.count ? rows[index].id : UUID()
            newRows.append(Row(id: id, item: item, status: .pending, fraction: 0))
        }

        rows = newRows
        phase = .ready
        overallProgress = 0
        errorMessage = nil
    }

    private func refreshMixedFlag() {
        guard let plan = try? AESCryptBatch.plan(
            urls: rows.map(\.item.input),
            outputPolicy: .unique
        ) else {
            return
        }
        let modes = Set(plan.items.map(\.mode))
        hasMixedInputs = modes.contains(.encrypt) && modes.contains(.decrypt)
    }

    private static func unreadableDropMessage(_ count: Int) -> String? {
        count > 0 ? "Could not read \(count) of the dropped files." : nil
    }

    private static func message(for error: Error) -> String {
        if let issue = error as? AESCryptBatchIssue {
            return message(for: issue)
        }
        if let aesError = error as? AESCryptError {
            return message(for: aesError)
        }
        return error.localizedDescription
    }

    private static func message(for issue: AESCryptBatchIssue) -> String {
        switch issue {
        case .tooManyFiles(let maximum):
            return "Up to \(maximum) files at a time."
        case .notAFile:
            return "That item is a folder, not a file."
        case .alreadyEncrypted:
            return "This file is already encrypted."
        case .notEncrypted:
            return "This is not an AES Crypt file."
        case .invalidAESFile:
            return "This .aes file is not a valid AES Crypt file."
        case .unsupportedVersion(let version):
            return "AES Crypt stream format \(version) is not supported."
        case .outputExists:
            return "An output file with that name already exists."
        case .sameFile:
            return "The input and output would be the same file."
        case .inspectFailed(let detail):
            return "Could not read the file: \(detail)"
        }
    }

    private static func message(for error: AESCryptError) -> String {
        switch error {
        case .wrongPassword:
            return "Wrong password. Try again."
        case .authenticationFailed:
            return "The file is corrupt or was modified. Nothing was written."
        case .outputExists:
            return "An output file with that name already exists."
        case .cancelled:
            return "Cancelled."
        default:
            return error.errorDescription ?? "Something went wrong."
        }
    }
}

final class BatchCancellationFlag: @unchecked Sendable {
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
