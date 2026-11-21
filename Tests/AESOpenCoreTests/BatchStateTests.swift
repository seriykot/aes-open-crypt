import Foundation
import XCTest
@testable import AESCryptKit
@testable import AESOpenCore

/// The batch session is a pure value with an explicit reducer. These tests pin
/// the transition rules directly, without files, tasks, or `@Published` state.
final class BatchStateTests: XCTestCase {
    // MARK: - Start

    func testStartFromReadyMovesToWorkingAndReturnsRunEffect() {
        var state = readyState(count: 2)
        state.format = .v2
        state.hint = "  ga" + String(repeating: "r", count: 400) + "  "
        state.overallProgress = 0.25
        state.errorMessage = "Something went wrong."
        state.passwordError = "Wrong password. Try again."
        state.notice = "Could not read 2 of the dropped files."

        let (next, effects) = BatchReducer.reduce(state: state, event: .start)

        XCTAssertEqual(next.phase, .working)
        XCTAssertEqual(next.overallProgress, 0)
        XCTAssertEqual(next.password, "")
        XCTAssertEqual(next.confirmation, "")
        XCTAssertEqual(next.hint, "")
        XCTAssertNil(next.errorMessage)
        XCTAssertNil(next.passwordError)
        XCTAssertNil(next.notice)
        XCTAssertEqual(next.runGeneration, state.runGeneration + 1)
        XCTAssertEqual(next.rows.map(\.status), [.pending, .pending])

        XCTAssertEqual(effects.count, 1)
        guard case .run(let plan, let password, let format, let hint, let generation) = effects[0] else {
            return XCTFail("expected a run effect, got \(effects)")
        }
        XCTAssertEqual(plan.items, state.rows.map(\.item))
        XCTAssertEqual(password, "apples")
        XCTAssertEqual(format, .v2)
        XCTAssertEqual(
            hint,
            "ga" + String(repeating: "r", count: BatchModel.maximumHintLength - 2)
        )
        XCTAssertEqual(generation, next.runGeneration)
    }

    func testStartWithoutPasswordIsIgnored() {
        let state = readyState(password: "")

        let (next, effects) = BatchReducer.reduce(state: state, event: .start)

        XCTAssertEqual(next, state)
        XCTAssertTrue(effects.isEmpty)
    }

    // MARK: - Retry

    func testRetryWithoutPasswordIsIgnored() {
        var state = readyState(count: 2)
        state.phase = .finished
        state.rows[0].status = .succeeded
        state.rows[1].status = .failed("disk full")
        state.password = ""
        state.confirmation = ""

        let (next, effects) = BatchReducer.reduce(
            state: state,
            event: .retry(items: [item("again.txt")])
        )

        XCTAssertEqual(next, state)
        XCTAssertTrue(effects.isEmpty)
    }

    func testRetryEncryptRequiresMatchingConfirmation() {
        var state = readyState(count: 2)
        state.phase = .finished
        state.rows[0].status = .succeeded
        state.rows[1].status = .wrongPassword
        state.password = "apples"
        state.confirmation = "pears"

        let ignored = BatchReducer.reduce(
            state: state,
            event: .retry(items: [item("again.txt")])
        )
        XCTAssertEqual(ignored.0, state)
        XCTAssertTrue(ignored.1.isEmpty)

        state.confirmation = "apples"
        let replacement = item("again.txt")
        let (next, effects) = BatchReducer.reduce(
            state: state,
            event: .retry(items: [replacement])
        )

        XCTAssertEqual(next.phase, .working)
        XCTAssertEqual(next.overallProgress, 0)
        XCTAssertEqual(next.rows[0].status, .succeeded, "only the failed row is replaced")
        XCTAssertEqual(next.rows[1].status, .pending)
        XCTAssertEqual(next.rows[1].item, replacement)
        XCTAssertEqual(next.password, "")
        XCTAssertEqual(next.confirmation, "")
        XCTAssertEqual(next.runGeneration, state.runGeneration + 1)

        XCTAssertEqual(effects.count, 1)
        guard case .run(let plan, let password, _, _, let generation) = effects[0] else {
            return XCTFail("expected a run effect, got \(effects)")
        }
        XCTAssertEqual(plan.items, [replacement])
        XCTAssertEqual(password, "apples")
        XCTAssertEqual(generation, next.runGeneration)
    }

    func testRetryWithTheWrongItemCountIsIgnored() {
        var state = readyState(count: 2)
        state.phase = .finished
        state.rows[0].status = .succeeded
        state.rows[1].status = .failed("disk full")

        let (next, effects) = BatchReducer.reduce(
            state: state,
            event: .retry(items: [item("again.txt"), item("extra.txt")])
        )

        XCTAssertEqual(next, state)
        XCTAssertTrue(effects.isEmpty)
    }

    // MARK: - Cancel

    func testCancelMarksPendingAndRunningCancelled() {
        var state = readyState(count: 3)
        state.phase = .working
        state.rows[0].status = .succeeded
        state.rows[1].status = .running
        state.rows[1].fraction = 0.5

        let (next, effects) = BatchReducer.reduce(state: state, event: .cancel)

        XCTAssertEqual(next.phase, .finished)
        XCTAssertEqual(next.rows.map(\.status), [.succeeded, .cancelled, .cancelled])
        XCTAssertEqual(next.rows[1].fraction, 0.5, "a cancelled row keeps its progress")
        XCTAssertTrue(effects.isEmpty)

        let ready = readyState()
        XCTAssertEqual(
            BatchReducer.reduce(state: ready, event: .cancel).0,
            ready,
            "cancel outside a run changes nothing"
        )
    }

    // MARK: - Remove

    func testRemoveDuringWorkingIsIgnored() {
        var state = readyState(count: 2)
        state.phase = .working

        let (next, effects) = BatchReducer.reduce(
            state: state,
            event: .remove(state.rows[0].id)
        )

        XCTAssertEqual(next, state)
        XCTAssertTrue(effects.isEmpty)
    }

    func testRemoveLastRowResetsToIdle() {
        var state = readyState(count: 1)
        state.overallProgress = 0.4
        state.notice = "Finish the current batch first."
        state.errorMessage = "Something went wrong."
        state.passwordError = "Wrong password. Try again."
        state.hint = "garden"
        state.showPassword = true
        state.format = .v2
        let generation = state.runGeneration

        let (next, effects) = BatchReducer.reduce(
            state: state,
            event: .remove(state.rows[0].id)
        )

        XCTAssertEqual(next.phase, .idle)
        XCTAssertTrue(next.rows.isEmpty)
        XCTAssertEqual(next.overallProgress, 0)
        XCTAssertNil(next.errorMessage)
        XCTAssertNil(next.passwordError)
        XCTAssertNil(next.notice)
        XCTAssertEqual(next.password, "")
        XCTAssertEqual(next.confirmation, "")
        XCTAssertEqual(next.hint, "")
        XCTAssertFalse(next.showPassword)
        XCTAssertEqual(next.runGeneration, generation + 1)
        XCTAssertEqual(next.mode, .encrypt, "the mode survives a row removal")
        XCTAssertEqual(next.format, .v2, "the format survives a row removal")
        XCTAssertTrue(effects.isEmpty)
    }

    func testRemoveAfterFinishedKeepsFinished() {
        var state = readyState(count: 2)
        state.phase = .finished
        state.rows[0].status = .succeeded
        state.rows[1].status = .succeeded
        state.overallProgress = 1

        let (next, effects) = BatchReducer.reduce(
            state: state,
            event: .remove(state.rows[1].id)
        )

        XCTAssertEqual(next.phase, .finished, "removing a row must not reopen a finished batch")
        XCTAssertEqual(next.rows.count, 1)
        XCTAssertEqual(next.rows[0].status, .succeeded)
        XCTAssertEqual(next.overallProgress, 0)
        XCTAssertTrue(effects.isEmpty)
    }

    func testRemoveWrongPasswordRowClearsPasswordError() {
        var state = readyState(count: 2, mode: .decrypt)
        state.phase = .finished
        state.rows[0].status = .succeeded
        state.rows[1].status = .wrongPassword
        state.passwordError = "Wrong password. Try again."
        state.overallProgress = 1

        let (next, effects) = BatchReducer.reduce(
            state: state,
            event: .remove(state.rows[1].id)
        )

        XCTAssertNil(next.passwordError)
        XCTAssertEqual(next.phase, .finished)
        XCTAssertEqual(next.rows.count, 1)
        XCTAssertEqual(next.rows[0].status, .succeeded)
        XCTAssertTrue(effects.isEmpty)

        // A wrong-password row that stays keeps its message.
        var kept = readyState(count: 3, mode: .decrypt)
        kept.phase = .finished
        kept.rows[0].status = .wrongPassword
        kept.rows[1].status = .succeeded
        kept.rows[2].status = .failed("disk full")
        kept.passwordError = "Wrong password. Try again."

        let (afterRemoval, _) = BatchReducer.reduce(
            state: kept,
            event: .remove(kept.rows[1].id)
        )

        XCTAssertEqual(afterRemoval.passwordError, "Wrong password. Try again.")
        XCTAssertEqual(afterRemoval.phase, .finished)
    }

    // MARK: - Clear

    func testClearResetsShowPassword() {
        var state = readyState(count: 2)
        state.phase = .finished
        state.showPassword = true
        state.overallProgress = 1
        state.notice = "Could not read 2 of the dropped files."
        state.format = .v2

        let (next, effects) = BatchReducer.reduce(state: state, event: .clear)

        XCTAssertFalse(next.showPassword)
        XCTAssertEqual(next.phase, .idle)
        XCTAssertTrue(next.rows.isEmpty)
        XCTAssertEqual(next.overallProgress, 0)
        XCTAssertNil(next.notice)
        XCTAssertEqual(next.password, "")
        XCTAssertEqual(next.confirmation, "")
        XCTAssertEqual(next.hint, "")
        XCTAssertEqual(next.runGeneration, state.runGeneration + 1)
        XCTAssertEqual(next.mode, .encrypt)
        XCTAssertEqual(next.format, .v2)
        XCTAssertTrue(effects.isEmpty)
    }

    // MARK: - Install plan

    func testInstallPlanResetsRowsAndKeepsCredentials() {
        var state = BatchState()
        state.password = "apples"
        state.showPassword = true
        state.phase = .finished
        state.rows = [row(item("old.txt"), status: .succeeded)]
        state.overallProgress = 1
        state.errorMessage = "Something went wrong."
        state.passwordError = "Wrong password. Try again."

        let plan = [item("first.txt"), item("second.txt")]
        let (next, effects) = BatchReducer.reduce(
            state: state,
            event: .installPlan(
                items: plan,
                mode: .encrypt,
                notice: "Could not read 2 of the dropped files."
            )
        )

        XCTAssertEqual(next.rows.map(\.item), plan)
        XCTAssertEqual(next.rows.map(\.status), [.pending, .pending])
        XCTAssertEqual(next.phase, .ready)
        XCTAssertEqual(next.overallProgress, 0)
        XCTAssertNil(next.errorMessage)
        XCTAssertNil(next.passwordError)
        XCTAssertEqual(next.notice, "Could not read 2 of the dropped files.")
        XCTAssertEqual(next.password, "apples")
        XCTAssertTrue(next.showPassword)
        XCTAssertTrue(effects.isEmpty)

        let empty = BatchReducer.reduce(
            state: state,
            event: .installPlan(items: [], mode: .decrypt, notice: nil)
        )
        XCTAssertEqual(empty.0.phase, .idle)
        XCTAssertTrue(empty.0.rows.isEmpty)
        XCTAssertEqual(empty.0.mode, .decrypt)
    }

    // MARK: - Progress

    func testProgressOnlyUpdatesInWorkingAndMatchingGeneration() {
        var state = readyState(count: 2)
        state.runGeneration = 3
        let ids = state.rows.map(\.id)
        let update = AESCryptBatchProgress(
            itemIndex: 1,
            itemCount: 2,
            itemFraction: 0.5,
            overallFraction: 0.75
        )

        let notWorking = BatchReducer.reduce(
            state: state,
            event: .progress(update, rowIDs: ids, generation: 3)
        )
        XCTAssertEqual(notWorking.0, state, "progress outside a run is ignored")
        XCTAssertTrue(notWorking.1.isEmpty)

        state.phase = .working
        let stale = BatchReducer.reduce(
            state: state,
            event: .progress(update, rowIDs: ids, generation: 2)
        )
        XCTAssertEqual(stale.0, state, "progress from a stale run is ignored")

        let (next, effects) = BatchReducer.reduce(
            state: state,
            event: .progress(update, rowIDs: ids, generation: 3)
        )
        XCTAssertEqual(next.rows[0].status, .pending)
        XCTAssertEqual(next.rows[1].status, .running)
        XCTAssertEqual(next.rows[1].fraction, 0.5)
        XCTAssertEqual(next.overallProgress, 0.75)
        XCTAssertTrue(effects.isEmpty)

        let outOfRange = AESCryptBatchProgress(
            itemIndex: 9,
            itemCount: 2,
            itemFraction: 1,
            overallFraction: 1
        )
        XCTAssertEqual(
            BatchReducer.reduce(state: state, event: .progress(outOfRange, rowIDs: ids, generation: 3)).0,
            state,
            "an out-of-range item index is ignored"
        )
    }

    // MARK: - Results

    func testResultsClearNoticeAndFinish() {
        var state = readyState(count: 2)
        state.phase = .working
        let rows = state.rows
        state.notice = "Finish the current batch first."
        let results = rows.map { AESCryptBatchResult(item: $0.item, failure: nil) }

        let (next, effects) = BatchReducer.reduce(
            state: state,
            event: .results(results, rowIDs: rows.map(\.id), generation: state.runGeneration)
        )

        XCTAssertEqual(next.phase, .finished)
        XCTAssertNil(next.notice, "finishing a run clears the working notice")
        XCTAssertEqual(next.overallProgress, 1)
        XCTAssertEqual(next.rows.map(\.status), [.succeeded, .succeeded])
        XCTAssertTrue(effects.isEmpty)
    }

    func testResultsMapFailuresToStatusesAndMessages() {
        var state = readyState(count: 3, mode: .decrypt)
        state.phase = .working
        let rows = state.rows
        let results = [
            AESCryptBatchResult(item: rows[0].item, failure: .crypto(.wrongPassword)),
            AESCryptBatchResult(item: rows[1].item, failure: .issue(.invalidAESFile)),
            AESCryptBatchResult(item: rows[2].item, failure: .crypto(.cancelled)),
        ]

        let (next, _) = BatchReducer.reduce(
            state: state,
            event: .results(results, rowIDs: rows.map(\.id), generation: state.runGeneration)
        )

        XCTAssertEqual(next.rows[0].status, .wrongPassword)
        XCTAssertEqual(next.rows[1].status, .failed("This .aes file is not a valid AES Crypt file."))
        XCTAssertEqual(next.rows[2].status, .cancelled)
        XCTAssertEqual(next.passwordError, "Wrong password. Try again.")
        XCTAssertEqual(next.phase, .finished)
    }

    func testStaleGenerationResultsAreIgnored() {
        var state = readyState(count: 1)
        state.phase = .working
        state.runGeneration = 2
        let rows = state.rows
        let results = rows.map { AESCryptBatchResult(item: $0.item, failure: nil) }

        let (next, effects) = BatchReducer.reduce(
            state: state,
            event: .results(results, rowIDs: rows.map(\.id), generation: 1)
        )

        XCTAssertEqual(next, state)
        XCTAssertTrue(effects.isEmpty)
    }

    // MARK: - Helpers

    private func item(
        _ name: String,
        mode: AESCryptBatchMode = .encrypt,
        issue: AESCryptBatchIssue? = nil
    ) -> AESCryptBatchItem {
        let base = URL(fileURLWithPath: "/tmp/aesopen-batch-state", isDirectory: true)
        let input = base.appendingPathComponent(name)
        let output: URL
        switch mode {
        case .encrypt:
            output = input.appendingPathExtension("aes")
        case .decrypt:
            output = input.deletingPathExtension()
        }
        return AESCryptBatchItem(input: input, output: output, mode: mode, issue: issue)
    }

    private func row(
        _ item: AESCryptBatchItem,
        status: BatchModel.RowStatus = .pending,
        fraction: Double = 0
    ) -> BatchModel.Row {
        BatchModel.Row(id: UUID(), item: item, status: status, fraction: fraction)
    }

    /// A ready batch of `count` pending rows the reducer can start.
    private func readyState(
        count: Int = 1,
        mode: AESCryptBatchMode = .encrypt,
        password: String = "apples"
    ) -> BatchState {
        var state = BatchState()
        state.rows = (0..<count).map { index in
            row(item("file-\(index).txt", mode: mode))
        }
        state.phase = .ready
        state.mode = mode
        state.password = password
        state.confirmation = mode == .encrypt ? password : ""
        return state
    }
}
