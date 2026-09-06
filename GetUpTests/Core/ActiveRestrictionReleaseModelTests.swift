import Foundation
import Testing
@testable import GetUp

@Suite("Active restriction release model")
@MainActor
struct ActiveRestrictionReleaseModelTests {
    @Test("Only current rule revisions and unexpired occurrences are available")
    func evaluatesCurrentOccurrences() throws {
        let earlier = try occurrence(ruleID: Self.firstRuleID, revision: 2, activatedOffset: -300)
        let later = try occurrence(ruleID: Self.secondRuleID, revision: 1, activatedOffset: -60)
        let staleRevision = try occurrence(ruleID: Self.thirdRuleID, revision: 1, activatedOffset: -600)
        let model = try makeModel(
            occurrences: [later, staleRevision, earlier],
            revisions: [Self.firstRuleID: 2, Self.secondRuleID: 1, Self.thirdRuleID: 2]
        )

        #expect(model.activeOccurrences == [earlier, later])
        #expect(model.selectedOccurrence == earlier)
        #expect(model.availability == .ready)
        #expect(model.previewFundingSource == .monthlyFree)
        #expect(model.canRequestConfirmation)
    }

    @Test("Purchased credit is previewed only when no monthly free use remains")
    func previewsPurchasedFallback() throws {
        let model = try makeModel(balance: balance(free: 0, purchased: 2))

        #expect(model.previewFundingSource == .purchased)
        #expect(model.availability == .ready)
    }

    @Test("Pending reconciliation blocks a new release before balance checks")
    func pendingReconciliationTakesPriority() throws {
        let model = try makeModel(
            balance: balance(free: 0, purchased: 0),
            hasPendingReconciliation: true
        )

        #expect(model.availability == .reconciliationRequired)
        #expect(!model.canRequestConfirmation)
        #expect(!model.requestConfirmation())
    }

    @Test(
        "Every non-current ledger maps to its recovery surface",
        arguments: [
            (CoinBalanceSyncState.setupRequired, ActiveRestrictionReleaseAvailability.iCloudRecoveryRequired),
            (.syncing, .iCloudRecoveryRequired),
            (.stale, .iCloudRecoveryRequired),
            (.unavailable, .iCloudRecoveryRequired),
            (.deletionConfirmed, .ledgerResetRequired),
            (.resetRequired, .ledgerResetRequired),
        ]
    )
    func mapsNonCurrentLedger(
        syncState: CoinBalanceSyncState,
        expected: ActiveRestrictionReleaseAvailability
    ) throws {
        let model = try makeModel(balance: balance(syncState: syncState))

        #expect(model.availability == expected)
        #expect(model.previewFundingSource == nil)
        #expect(!model.canRequestConfirmation)
    }

    @Test("A current zero balance routes to purchase instead of confirmation")
    func zeroBalanceRequiresPurchase() throws {
        let model = try makeModel(balance: balance(free: 0, purchased: 0))

        #expect(model.availability == .insufficientBalance)
        #expect(!model.requestConfirmation())
    }

    @Test("No current occurrence disables the release action")
    func noCurrentOccurrenceDisablesRelease() throws {
        let stale = try occurrence(
            ruleID: Self.firstRuleID,
            revision: 1,
            activatedOffset: -300
        )
        let model = try makeModel(
            occurrences: [stale],
            revisions: [Self.firstRuleID: 2]
        )

        #expect(model.activeOccurrences.isEmpty)
        #expect(model.selectedOccurrence == nil)
        #expect(model.availability == .noActiveRestriction)
        #expect(!model.canRequestConfirmation)
    }

    @Test("A selected occurrence is the only target passed after confirmation")
    func selectedOccurrenceIsReleased() async throws {
        let first = try occurrence(
            ruleID: Self.firstRuleID,
            revision: 2,
            activatedOffset: -300
        )
        let second = try occurrence(
            ruleID: Self.secondRuleID,
            revision: 1,
            activatedOffset: -60
        )
        let executor = ReleaseExecutorSpy(result: .reconciliationRequired)
        let model = try makeModel(
            occurrences: [first, second],
            revisions: [Self.firstRuleID: 2, Self.secondRuleID: 1],
            executor: executor
        )

        #expect(model.selectOccurrence(id: second.id))
        #expect(model.selectedOccurrence == second)
        #expect(model.requestConfirmation())
        await model.confirmRelease()

        #expect(executor.requests == [second])
    }

    @Test("Confirmation is separate and cancellation never executes release")
    func confirmationCanBeCancelled() throws {
        let executor = ReleaseExecutorSpy(result: .reconciliationRequired)
        let model = try makeModel(executor: executor)

        #expect(model.requestConfirmation())
        #expect(model.phase == .confirmationRequested)
        model.cancelConfirmation()
        #expect(model.phase == .idle)
        #expect(executor.requestCount == 0)
    }

    @Test("Confirmed success updates balance and the remaining active occurrences")
    func successUpdatesConfirmedState() async throws {
        let remaining = try occurrence(
            ruleID: Self.secondRuleID,
            revision: 1,
            activatedOffset: -60
        )
        let updatedBalance = balance(free: 0, purchased: 3)
        let executor = ReleaseExecutorSpy(result: .released(
            fundingSource: .monthlyFree,
            balance: updatedBalance,
            remainingOccurrences: [remaining]
        ))
        let model = try makeModel(executor: executor)

        #expect(model.requestConfirmation())
        await model.confirmRelease()

        #expect(executor.requestCount == 1)
        #expect(model.phase == .released(.monthlyFree))
        #expect(model.balance == updatedBalance)
        #expect(model.activeOccurrences == [remaining])
        #expect(model.selectedOccurrence == remaining)
    }

    @Test("A second confirmation while processing cannot execute twice")
    func duplicateConfirmationExecutesOnce() async throws {
        let gate = HeldReleaseExecutor()
        let model = try makeModel(executeRelease: { occurrence in
            await gate.execute(occurrence)
        })
        #expect(model.requestConfirmation())

        let first = Task { await model.confirmRelease() }
        await gate.waitUntilRequested()
        await model.confirmRelease()
        #expect(await gate.requestCount == 1)
        await gate.finish(with: .reconciliationRequired)
        await first.value

        #expect(model.phase == .blocked(.reconciliationRequired))
        #expect(await gate.requestCount == 1)
    }
}

private extension ActiveRestrictionReleaseModelTests {
    static let now = Date(timeIntervalSince1970: 1_788_192_000)
    static let firstRuleID = UUID(uuidString: "00000000-0000-4000-8000-000000000801")!
    static let secondRuleID = UUID(uuidString: "00000000-0000-4000-8000-000000000802")!
    static let thirdRuleID = UUID(uuidString: "00000000-0000-4000-8000-000000000803")!

    func makeModel(
        occurrences: [RestrictionOccurrence]? = nil,
        revisions: [UUID: Int]? = nil,
        balance: CoinBalanceSnapshot? = nil,
        hasPendingReconciliation: Bool = false,
        executor: ReleaseExecutorSpy? = nil,
        executeRelease: ActiveRestrictionReleaseModel.ExecuteRelease? = nil
    ) throws -> ActiveRestrictionReleaseModel {
        let defaultOccurrence = try occurrence(
            ruleID: Self.firstRuleID,
            revision: 2,
            activatedOffset: -300
        )
        let occurrences = occurrences ?? [defaultOccurrence]
        let revisions = revisions ?? [Self.firstRuleID: 2]
        let executor = executor ?? ReleaseExecutorSpy(result: .reconciliationRequired)
        let fixedNow = Self.now
        return ActiveRestrictionReleaseModel(
            snapshot: try ActiveRestrictionSnapshot(
                revision: 1,
                occurrences: occurrences,
                observedAt: Self.now
            ),
            currentRuleRevisions: revisions,
            balance: balance ?? self.balance(),
            hasPendingReconciliation: hasPendingReconciliation,
            now: { fixedNow },
            executeRelease: executeRelease ?? { occurrence in
                await executor.execute(occurrence)
            }
        )
    }

    func occurrence(
        ruleID: UUID,
        revision: Int,
        activatedOffset: TimeInterval
    ) throws -> RestrictionOccurrence {
        try RestrictionOccurrence(
            ruleID: ruleID,
            ruleRevision: revision,
            startAt: Self.now.addingTimeInterval(-900),
            endAt: Self.now.addingTimeInterval(2_700),
            activatedAt: Self.now.addingTimeInterval(activatedOffset)
        )
    }

    func balance(
        free: Int = 1,
        purchased: Int = 3,
        syncState: CoinBalanceSyncState = .current
    ) -> CoinBalanceSnapshot {
        try! CoinBalanceSnapshot(
            purchasedAvailable: purchased,
            currentMonthID: "2026-09",
            freeAvailable: free,
            syncState: syncState,
            syncedAt: Self.now,
            ledgerEpochID: syncState == .current
                ? UUID(uuidString: "00000000-0000-4000-8000-000000000804")!
                : nil,
            hadConfirmedLedger: syncState == .current
        )
    }
}

@MainActor
private final class ReleaseExecutorSpy {
    let result: ActiveRestrictionReleaseExecutionResult
    private(set) var requests: [RestrictionOccurrence] = []

    var requestCount: Int { requests.count }

    init(result: ActiveRestrictionReleaseExecutionResult) {
        self.result = result
    }

    func execute(_ occurrence: RestrictionOccurrence) -> ActiveRestrictionReleaseExecutionResult {
        requests.append(occurrence)
        return result
    }
}

private actor HeldReleaseExecutor {
    private var continuation: CheckedContinuation<ActiveRestrictionReleaseExecutionResult, Never>?
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var requestCount = 0

    func execute(_ occurrence: RestrictionOccurrence) async
        -> ActiveRestrictionReleaseExecutionResult
    {
        _ = occurrence
        requestCount += 1
        requestWaiters.forEach { $0.resume() }
        requestWaiters = []
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilRequested() async {
        if requestCount > 0 { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func finish(with result: ActiveRestrictionReleaseExecutionResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
