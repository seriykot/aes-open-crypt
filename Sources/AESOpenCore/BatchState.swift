import AESCryptKit
import Foundation

/// The whole batch session as one value: rows, phase, progress, messages,
/// credentials, and the run generation.
///
/// `BatchModel` publishes exactly one of these, and ``BatchReducer`` is the
/// only thing that changes it. Keeping the rules in a plain value makes every
/// transition — start, retry, cancel, remove, clear, progress, results — a
/// pure function that can be tested without files, tasks, or SwiftUI.
struct BatchState: Equatable {
    var rows: [BatchModel.Row] = []
    var phase: BatchModel.Phase = .idle
    var overallProgress: Double = 0
    var errorMessage: String?
    var passwordError: String?
    var notice: String?
    var password = ""
    var confirmation = ""
    var hint = ""
    var showPassword = false
    var mode: AESCryptBatchMode = .encrypt
    var format: AESOutputFormat = .v3
    var runGeneration = 0

    /// Whether Start could run this batch right now: a ready batch, rows with
    /// no planning issues, a password, and — when encrypting — a matching
    /// confirmation.
    var canStart: Bool {
        guard phase == .ready, !rows.isEmpty else { return false }
        guard rows.allSatisfy({ $0.item.issue == nil }) else { return false }
        guard !password.isEmpty else { return false }
        if mode == .encrypt, password != confirmation { return false }
        return true
    }

    /// Whether any row ended in a failure: a planning issue or a wrong
    /// password. Cancelled rows are not failures.
    var hasFailedRows: Bool {
        rows.contains { Self.countsAsFailure($0.status) }
    }

    /// Whether any row failed specifically because of a wrong password, which
    /// is the case the GUI offers to retry in place.
    var hasWrongPasswordRows: Bool {
        rows.contains { $0.status == .wrongPassword }
    }

    /// Whether a retry could start right now. The rules match ``canStart``:
    /// a failed row, a password, and — when encrypting — a matching
    /// confirmation.
    var canRetry: Bool {
        guard hasFailedRows, !password.isEmpty else { return false }
        guard mode == .encrypt else { return true }
        return password == confirmation
    }

    var completedOutputs: [URL] {
        rows.compactMap { row in
            row.status == .succeeded ? row.item.output : nil
        }
    }

    /// The one line describing how a finished batch ended, or nil when no row
    /// finished or failed yet.
    var finishedSummary: BatchSummary? {
        let completed = completedOutputs.count
        let failed = rows.filter { Self.countsAsFailure($0.status) }.count
        guard !rows.isEmpty, completed + failed > 0 else { return nil }

        if failed == 0 {
            let files = completed == 1 ? "file" : "files"
            let action = mode == .decrypt ? "decrypted" : "encrypted"
            return BatchSummary(text: "\(completed) \(files) \(action)", isWarning: false)
        }
        return BatchSummary(text: "\(completed) finished, \(failed) failed", isWarning: true)
    }

    /// The single failure predicate behind the retry button and the summary.
    static func countsAsFailure(_ status: BatchModel.RowStatus) -> Bool {
        switch status {
        case .failed, .wrongPassword: return true
        case .pending, .running, .succeeded, .cancelled: return false
        }
    }

    /// Trim the hint, treat blank text as no hint, then apply the product
    /// length limit. The trimming rule is shared with the CLI through
    /// ``AESPasswordHint/normalize(_:)``; the 256 cap is the product limit.
    static func normalizedHint(_ text: String) -> String? {
        guard let trimmed = AESPasswordHint.normalize(text) else { return nil }
        return String(trimmed.prefix(BatchModel.maximumHintLength))
    }

    static func message(for error: Error) -> String {
        if let issue = error as? AESCryptBatchIssue {
            return issue.userMessage
        }
        if let aesError = error as? AESCryptError {
            return message(for: aesError)
        }
        return error.localizedDescription
    }

    static func message(for error: AESCryptError) -> String {
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

/// Everything that can happen to a batch session.
enum BatchEvent {
    case installPlan(items: [AESCryptBatchItem], mode: AESCryptBatchMode, notice: String?, rowIDs: [UUID]?)
    case start
    case retry(items: [AESCryptBatchItem])
    case cancel
    case remove(UUID)
    case clear
    case progress(AESCryptBatchProgress, rowIDs: [UUID], generation: Int)
    case results([AESCryptBatchResult], rowIDs: [UUID], generation: Int)
    case setNotice(String?)
    case setError(String?)
}

/// Work the reducer hands back to the model. The reducer never runs a batch;
/// it only says that one should start, with every input already captured.
enum BatchEffect {
    case run(plan: AESCryptBatchPlan, password: String,
             format: AESOutputFormat, hint: String?, generation: Int)
}

enum BatchReducer {
    static func reduce(state: BatchState, event: BatchEvent) -> (BatchState, [BatchEffect]) {
        var state = state
        var effects: [BatchEffect] = []

        switch event {
        case .installPlan(let items, let mode, let notice, let rowIDs):
            install(items: items, mode: mode, notice: notice, rowIDs: rowIDs, into: &state)

        case .start:
            guard state.canStart else { break }
            guard state.rows.allSatisfy({ $0.status == .pending }) else { break }
            let plan = AESCryptBatchPlan(items: state.rows.map(\.item))
            guard !plan.items.isEmpty else { break }

            let password = state.password
            let format = state.format
            let hint = BatchState.normalizedHint(state.hint)

            state.phase = .working
            state.overallProgress = 0
            state.errorMessage = nil
            state.passwordError = nil
            state.notice = nil
            state.runGeneration += 1
            state.password = ""
            state.confirmation = ""
            state.hint = ""

            effects.append(
                .run(
                    plan: plan,
                    password: password,
                    format: format,
                    hint: hint,
                    generation: state.runGeneration
                )
            )

        case .retry(let items):
            guard state.phase == .finished || state.phase == .ready else { break }
            guard state.canRetry else { break }
            let failedCount = state.rows.filter { BatchState.countsAsFailure($0.status) }.count
            guard items.count == failedCount else { break }

            let password = state.password
            let format = state.format
            let hint = BatchState.normalizedHint(state.hint)

            var replacements = items.makeIterator()
            var newRows: [BatchModel.Row] = []
            newRows.reserveCapacity(state.rows.count)
            for row in state.rows {
                if BatchState.countsAsFailure(row.status),
                   let replacement = replacements.next() {
                    newRows.append(
                        BatchModel.Row(
                            id: UUID(),
                            item: replacement,
                            status: .pending,
                            fraction: 0
                        )
                    )
                } else {
                    newRows.append(row)
                }
            }

            state.rows = newRows
            state.phase = .working
            state.overallProgress = 0
            state.errorMessage = nil
            state.passwordError = nil
            state.notice = nil
            state.runGeneration += 1
            state.password = ""
            state.confirmation = ""
            state.hint = ""

            effects.append(
                .run(
                    plan: AESCryptBatchPlan(items: items),
                    password: password,
                    format: format,
                    hint: hint,
                    generation: state.runGeneration
                )
            )

        case .cancel:
            guard state.phase == .working else { break }
            for index in state.rows.indices {
                switch state.rows[index].status {
                case .pending, .running:
                    state.rows[index].status = .cancelled
                case .succeeded, .failed, .wrongPassword, .cancelled:
                    break
                }
            }
            state.phase = .finished

        case .remove(let id):
            guard state.phase != .working else { break }
            state.rows.removeAll { $0.id == id }
            if state.rows.isEmpty {
                resetToIdle(&state)
            } else {
                state.overallProgress = 0
                if state.phase != .finished {
                    state.phase = .ready
                }
                if !state.hasWrongPasswordRows {
                    state.passwordError = nil
                }
            }

        case .clear:
            resetToIdle(&state)

        case .progress(let update, let rowIDs, let generation):
            guard generation == state.runGeneration,
                  state.phase == .working,
                  update.itemIndex >= 0,
                  update.itemIndex < rowIDs.count else { break }

            let id = rowIDs[update.itemIndex]
            guard let index = state.rows.firstIndex(where: { $0.id == id }) else { break }

            if state.rows[index].status == .pending {
                state.rows[index].status = .running
            }
            if state.rows[index].status == .running {
                state.rows[index].fraction = update.itemFraction
                state.overallProgress = update.overallFraction
            }

        case .results(let results, let rowIDs, let generation):
            guard generation == state.runGeneration else { break }

            for (offset, result) in results.enumerated() where offset < rowIDs.count {
                guard let index = state.rows.firstIndex(where: { $0.id == rowIDs[offset] }) else {
                    continue
                }

                switch result.failure {
                case .none:
                    state.rows[index].status = .succeeded
                    state.rows[index].fraction = 1
                case .some(.issue(let issue)):
                    state.rows[index].status = .failed(BatchState.message(for: issue))
                case .some(.crypto(.wrongPassword)):
                    state.rows[index].status = .wrongPassword
                    state.passwordError = BatchState.message(for: AESCryptError.wrongPassword)
                case .some(.crypto(.cancelled)):
                    state.rows[index].status = .cancelled
                case .some(.crypto(let error)):
                    state.rows[index].status = .failed(BatchState.message(for: error))
                }
            }

            state.overallProgress = 1
            state.phase = .finished
            state.notice = nil

        case .setNotice(let notice):
            state.notice = notice

        case .setError(let error):
            state.errorMessage = error
        }

        return (state, effects)
    }

    /// New rows for a freshly planned batch. Credentials and the reveal toggle
    /// stay as they are: adding to a batch should not make someone retype a
    /// password, and a finished batch is cleared before it is replaced.
    private static func install(
        items: [AESCryptBatchItem],
        mode: AESCryptBatchMode,
        notice: String?,
        rowIDs: [UUID]?,
        into state: inout BatchState
    ) {
        state.rows = items.enumerated().map { index, item in
            let id = rowIDs.flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? UUID()
            return BatchModel.Row(id: id, item: item, status: .pending, fraction: 0)
        }
        state.phase = state.rows.isEmpty ? .idle : .ready
        state.mode = mode
        state.overallProgress = 0
        state.errorMessage = nil
        state.passwordError = nil
        state.notice = notice
    }

    /// The idle state shared by Clear and by removing the last row. The mode
    /// and the saved format preference survive.
    private static func resetToIdle(_ state: inout BatchState) {
        state.rows = []
        state.phase = .idle
        state.overallProgress = 0
        state.errorMessage = nil
        state.passwordError = nil
        state.notice = nil
        state.password = ""
        state.confirmation = ""
        state.hint = ""
        state.showPassword = false
        state.runGeneration += 1
    }
}
