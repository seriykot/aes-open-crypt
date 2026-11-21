import AESCryptKit
import Combine
import Foundation

/// The one line shown when a batch stops: what happened, and whether it is
/// worth a warning colour.
public struct BatchSummary: Equatable {
    public let text: String
    public let isWarning: Bool

    init(text: String, isWarning: Bool) {
        self.text = text
        self.isWarning = isWarning
    }
}

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
        case wrongPassword
        case cancelled
    }

    public struct Row: Identifiable, Equatable {
        public let id: UUID
        public let item: AESCryptBatchItem
        public var status: RowStatus
        public var fraction: Double
    }

    public static let shared = BatchModel()
    public nonisolated static let maximumHintLength = AESPasswordHint.maximumLength
    public static let mixedDropNotice = "Drop plain files or encrypted files separately"

    /// The one value the model publishes. Everything below reads through it,
    /// and the writable properties write through it, so SwiftUI bindings keep
    /// working while the session stays a single testable snapshot.
    @Published private var state: BatchState

    public var rows: [Row] { state.rows }
    public var phase: Phase { state.phase }
    public var overallProgress: Double { state.overallProgress }
    public var errorMessage: String? { state.errorMessage }
    public var passwordError: String? { state.passwordError }
    public var notice: String? { state.notice }
    var runGeneration: Int { state.runGeneration }

    public var password: String {
        get { state.password }
        set { state.password = newValue }
    }

    public var confirmation: String {
        get { state.confirmation }
        set { state.confirmation = newValue }
    }

    public var hint: String {
        get { state.hint }
        set { state.hint = newValue }
    }

    public var showPassword: Bool {
        get { state.showPassword }
        set { state.showPassword = newValue }
    }

    public var mode: AESCryptBatchMode {
        get { state.mode }
        set {
            guard !isUpdatingMode, state.mode != newValue else { return }
            state.mode = newValue
            replanForMode()
        }
    }

    public var format: AESOutputFormat {
        get { state.format }
        set {
            state.format = newValue
            UserDefaults.standard.set(Int(newValue.rawValue), forKey: "outputFormat")
        }
    }

    private(set) var activeTask: Task<Void, Never>?
    private var cancellation: BatchCancellationFlag?
    private var isUpdatingMode = false

    public init() {
        var state = BatchState()
        let saved = UserDefaults.standard.object(forKey: "outputFormat") as? Int
        if let saved, saved == AESOutputFormat.v2.rawValue {
            state.format = .v2
        } else {
            state.format = .v3
        }
        self.state = state
    }

    public var canStart: Bool {
        state.canStart
    }

    /// A non-blocking hint: short passwords, or ones with neither an uppercase
    /// letter nor a symbol, get a suggestion to use something stronger.
    public var isPasswordWeak: Bool {
        guard mode == .encrypt, !password.isEmpty else { return false }
        let hasUppercase = password.contains { $0.isUppercase }
        let hasSymbol = password.contains { $0.isPunctuation || $0.isSymbol }
        return password.count < 8 || (!hasUppercase && !hasSymbol)
    }

    /// Unique, non-empty password hints from decrypt rows, in row order.
    public var decryptHints: [String] {
        var seen = Set<String>()
        var hints: [String] = []
        for row in rows where row.item.mode == .decrypt {
            guard let hint = row.item.info?.passwordHint,
                  seen.insert(hint).inserted else {
                continue
            }
            hints.append(hint)
        }
        return hints
    }

    /// Whether each decrypt row has a hint and they all agree on one value.
    public var hasSharedDecryptHint: Bool {
        let decryptRows = rows.filter { $0.item.mode == .decrypt }
        guard !decryptRows.isEmpty,
              decryptRows.allSatisfy({ $0.item.info?.passwordHint != nil }) else {
            return false
        }
        return Set(decryptRows.compactMap { $0.item.info?.passwordHint }).count == 1
    }

    /// Whether row labels are needed because decrypt rows have different or
    /// partially missing hints.
    public var showsPerRowDecryptHints: Bool {
        decryptHints.count > 1 || (decryptHints.count == 1 && !hasSharedDecryptHint)
    }

    /// The hint under the password field when every decrypt row agrees on one.
    public var sharedDecryptHint: String? {
        guard hasSharedDecryptHint else { return nil }
        return decryptHints.first
    }

    public var completedOutputs: [URL] {
        state.completedOutputs
    }

    /// Whether any row ended in a failure: a planning issue or a wrong
    /// password. Cancelled rows are not failures.
    public var hasFailedRows: Bool {
        state.hasFailedRows
    }

    /// Whether any row failed specifically because of a wrong password, which
    /// is the case the GUI offers to retry in place.
    public var hasWrongPasswordRows: Bool {
        state.hasWrongPasswordRows
    }

    /// Whether a retry could start right now. The rules match ``canStart``:
    /// a failed row, a password, and — when encrypting — a matching
    /// confirmation.
    public var canRetry: Bool {
        state.canRetry
    }

    /// The one line describing how a finished batch ended, or nil when no row
    /// finished or failed yet.
    public var finishedSummary: BatchSummary? {
        state.finishedSummary
    }

    public func add(
        urls: [URL],
        preferredMode: AESCryptBatchMode?,
        unreadableCount: Int = 0
    ) {
        guard !urls.isEmpty else {
            if let message = Self.unreadableDropMessage(unreadableCount) {
                state.notice = message
            }
            return
        }

        if phase == .working {
            let base = "Finish the current batch first."
            if let message = Self.unreadableDropMessage(unreadableCount) {
                state.notice = "\(base) \(message)"
            } else {
                state.notice = base
            }
            return
        }

        let planInputs = phase == .finished ? urls : rows.map(\.item.input) + urls

        do {
            let plan = try AESCryptBatch.plan(
                urls: planInputs,
                mode: preferredMode,
                outputPolicy: .unique
            )
            guard !plan.items.isEmpty else { return }

            let plannedModes = Set(plan.items.map(\.mode))

            // One batch runs in one direction. Auto mode cannot plan a mixed
            // drop, so refuse it before touching any state: existing rows,
            // mode, phase, and statuses stay exactly as they were.
            if preferredMode == nil,
               plannedModes.contains(.encrypt),
               plannedModes.contains(.decrypt) {
                state.errorMessage = nil
                state.notice = Self.mixedDropNotice
                return
            }

            if phase == .finished {
                clear()
            }

            let desiredMode: AESCryptBatchMode
            if let preferredMode {
                desiredMode = preferredMode
            } else if plannedModes == [.decrypt] {
                desiredMode = .decrypt
            } else {
                desiredMode = .encrypt
            }

            state.mode = desiredMode

            state.rows = plan.items.map {
                Row(id: UUID(), item: $0, status: .pending, fraction: 0)
            }
            state.phase = .ready
            state.overallProgress = 0
            state.errorMessage = nil
            state.passwordError = nil
            state.notice = Self.unreadableDropMessage(unreadableCount)
        } catch {
            state.errorMessage = Self.message(for: error)
        }
    }

    public func remove(_ id: UUID) {
        guard phase != .working else { return }
        state.rows.removeAll { $0.id == id }
        if state.rows.isEmpty {
            clear()
        } else {
            state.phase = .ready
            state.overallProgress = 0
        }
    }

    public func clear() {
        cancellation?.cancel()
        activeTask?.cancel()
        cancellation = nil
        activeTask = nil
        state.runGeneration += 1
        state.rows = []
        state.phase = .idle
        state.overallProgress = 0
        state.errorMessage = nil
        state.passwordError = nil
        state.notice = nil
        state.password = ""
        state.confirmation = ""
        state.hint = ""
    }

    /// The plan the rows already hold. Start runs exactly these items, so the
    /// output shown in a row is the output that gets written. Planning happens
    /// on add, and again only on an explicit refresh: a mode switch or a retry.
    public var currentPlan: AESCryptBatchPlan {
        AESCryptBatchPlan(items: rows.map(\.item))
    }

    public func start() {
        guard canStart else { return }

        let plan = currentPlan
        guard !plan.items.isEmpty else { return }

        beginRun(plan: plan)
    }

    public func retryFailed() {
        guard phase == .finished || phase == .ready else { return }

        let failedRows = rows.filter { Self.countsAsFailure($0.status) }
        guard !failedRows.isEmpty else { return }

        let plan: AESCryptBatchPlan
        do {
            plan = try AESCryptBatch.plan(
                urls: failedRows.map(\.item.input),
                mode: mode,
                outputPolicy: .unique
            )
        } catch {
            state.errorMessage = Self.message(for: error)
            return
        }
        guard plan.items.count == failedRows.count else { return }

        var items = plan.items.makeIterator()
        var newRows: [Row] = []
        newRows.reserveCapacity(rows.count)
        for row in rows {
            if case .failed = row.status, let item = items.next() {
                newRows.append(Row(id: UUID(), item: item, status: .pending, fraction: 0))
            } else if case .wrongPassword = row.status, let item = items.next() {
                newRows.append(Row(id: UUID(), item: item, status: .pending, fraction: 0))
            } else {
                newRows.append(row)
            }
        }

        state.rows = newRows
        state.phase = .ready
        beginRun(plan: plan)
    }

    public func cancel() {
        guard phase == .working else { return }
        cancellation?.cancel()
        activeTask?.cancel()
        cancellation = nil

        for index in state.rows.indices {
            switch state.rows[index].status {
            case .pending, .running:
                state.rows[index].status = .cancelled
            case .succeeded, .failed, .wrongPassword, .cancelled:
                break
            }
        }
        state.phase = .finished
    }

    private func beginRun(plan: AESCryptBatchPlan) {
        let rowIDs = rows.filter { $0.status == .pending }.map(\.id)
        guard rowIDs.count == plan.items.count else { return }

        state.phase = .working
        state.overallProgress = 0
        state.errorMessage = nil
        state.passwordError = nil
        state.notice = nil

        let password = self.password
        let format = self.format
        let hint = Self.normalizedHint(self.hint)
        state.password = ""
        state.confirmation = ""
        state.hint = ""

        state.runGeneration += 1
        let generation = state.runGeneration
        let flag = BatchCancellationFlag()
        cancellation = flag

        activeTask = Task.detached(priority: .userInitiated) { [weak self] in
            var lastIndex = -1
            var lastOverall = -1.0

            let results = AESCryptBatch.run(
                plan: plan,
                password: password,
                format: format,
                hint: hint,
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
        guard let index = state.rows.firstIndex(where: { $0.id == id }) else { return }

        if state.rows[index].status == .pending {
            state.rows[index].status = .running
        }
        if state.rows[index].status == .running {
            state.rows[index].fraction = update.itemFraction
            state.overallProgress = update.overallFraction
        }
    }

    func applyResults(
        _ results: [AESCryptBatchResult],
        rowIDs: [UUID],
        generation: Int
    ) {
        guard generation == runGeneration else { return }

        for (offset, result) in results.enumerated() where offset < rowIDs.count {
            guard let index = state.rows.firstIndex(where: { $0.id == rowIDs[offset] }) else {
                continue
            }

            switch result.failure {
            case .none:
                state.rows[index].status = .succeeded
                state.rows[index].fraction = 1
            case .some(.issue(let issue)):
                state.rows[index].status = .failed(Self.message(for: issue))
            case .some(.crypto(.wrongPassword)):
                state.rows[index].status = .wrongPassword
                state.passwordError = Self.message(for: AESCryptError.wrongPassword)
            case .some(.crypto(.cancelled)):
                state.rows[index].status = .cancelled
            case .some(.crypto(let error)):
                state.rows[index].status = .failed(Self.message(for: error))
            }
        }

        state.overallProgress = 1
        state.phase = .finished
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

        state.rows = newRows
        state.phase = .ready
        state.overallProgress = 0
        state.errorMessage = nil
        state.passwordError = nil
    }

    private static func unreadableDropMessage(_ count: Int) -> String? {
        count > 0 ? "Could not read \(count) of the dropped files." : nil
    }

    /// The single failure predicate behind the retry button and the summary.
    private static func countsAsFailure(_ status: RowStatus) -> Bool {
        switch status {
        case .failed, .wrongPassword: return true
        case .pending, .running, .succeeded, .cancelled: return false
        }
    }

    /// Trim the hint, treat blank text as no hint, then apply the product
    /// length limit. The trimming rule is shared with the CLI through
    /// ``AESPasswordHint/normalize(_:)``; the 256 cap is the product limit.
    private static func normalizedHint(_ text: String) -> String? {
        guard let trimmed = AESPasswordHint.normalize(text) else { return nil }
        return String(trimmed.prefix(maximumHintLength))
    }

    private static func message(for error: Error) -> String {
        if let issue = error as? AESCryptBatchIssue {
            return issue.userMessage
        }
        if let aesError = error as? AESCryptError {
            return message(for: aesError)
        }
        return error.localizedDescription
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
