import Foundation
import Testing
@testable import GetUp

@Suite("Coin app lifecycle coordination")
struct CoinAppLifecycleCoordinatorTests {
    @Test("Launch starts transaction observation before ledger and route reconciliation")
    func launchOrdersRecoveryAndConsumesEligibleRoute() async throws {
        let recorder = CoinLifecycleRecorder()
        let ledger = try Self.ledger(syncState: .current)
        let coordinator = CoinAppLifecycleCoordinator(
            startTransactionObservation: { await recorder.record(.transaction) },
            reconcileLedger: {
                await recorder.record(.ledger)
                return ledger
            },
            loadActiveOccurrenceIDs: { _ in
                await recorder.record(.activeOccurrences)
                return ["occurrence-current"]
            },
            consumePendingRoute: { _, activeIDs in
                await recorder.record(.route(activeIDs))
                return .coinStore
            }
        )

        let result = await coordinator.refresh(trigger: .launch, now: Self.now)

        #expect(result.ledger == ledger)
        #expect(result.destination == .coinStore)
        #expect(result.failures.isEmpty)
        #expect(await recorder.events == [
            .transaction,
            .ledger,
            .activeOccurrences,
            .route(["occurrence-current"]),
        ])
    }

    @Test("Foreground keeps one listener and repeats authoritative ledger reconciliation")
    func foregroundDoesNotDuplicateTransactionListener() async {
        let recorder = CoinLifecycleRecorder()
        let coordinator = CoinAppLifecycleCoordinator(
            startTransactionObservation: { await recorder.record(.transaction) },
            reconcileLedger: {
                await recorder.record(.ledger)
                return nil
            },
            loadActiveOccurrenceIDs: { _ in [] },
            consumePendingRoute: { _, _ in nil }
        )

        _ = await coordinator.refresh(trigger: .launch, now: Self.now)
        _ = await coordinator.refresh(trigger: .foreground, now: Self.now)

        #expect(await recorder.events.filter { $0 == .transaction }.count == 1)
        #expect(await recorder.events.filter { $0 == .ledger }.count == 2)
    }

    @Test("An active snapshot failure preserves the pending route for a later retry")
    func activeOccurrenceFailureDoesNotConsumeRoute() async {
        let recorder = CoinLifecycleRecorder()
        let coordinator = CoinAppLifecycleCoordinator(
            startTransactionObservation: {},
            reconcileLedger: { nil },
            loadActiveOccurrenceIDs: { _ in throw CoinLifecycleTestError.expected },
            consumePendingRoute: { _, _ in
                await recorder.record(.route([]))
                return .coinStore
            }
        )

        let result = await coordinator.refresh(trigger: .launch, now: Self.now)

        #expect(result.destination == nil)
        #expect(result.failures == [.activeOccurrenceLoad])
        #expect(await recorder.events.isEmpty)
    }

    @Test("Transaction and ledger failures are isolated while route eligibility still runs")
    func financialFailuresRemainFailClosedWithoutBlockingRouteCleanup() async {
        let recorder = CoinLifecycleRecorder()
        let coordinator = CoinAppLifecycleCoordinator(
            startTransactionObservation: { throw CoinLifecycleTestError.expected },
            reconcileLedger: { throw CoinLifecycleTestError.expected },
            loadActiveOccurrenceIDs: { _ in ["occurrence-current"] },
            consumePendingRoute: { _, activeIDs in
                await recorder.record(.route(activeIDs))
                return .iCloudRecovery
            }
        )

        let result = await coordinator.refresh(trigger: .launch, now: Self.now)

        #expect(result.ledger == nil)
        #expect(result.destination == .iCloudRecovery)
        #expect(result.failures == [.transactionObservation, .ledgerReconciliation])
        #expect(await recorder.events == [.route(["occurrence-current"])])
    }

    @Test("A route repository failure never invents navigation")
    func routeFailureDoesNotNavigate() async {
        let coordinator = CoinAppLifecycleCoordinator(
            startTransactionObservation: {},
            reconcileLedger: { nil },
            loadActiveOccurrenceIDs: { _ in [] },
            consumePendingRoute: { _, _ in throw CoinLifecycleTestError.expected }
        )

        let result = await coordinator.refresh(trigger: .foreground, now: Self.now)

        #expect(result.destination == nil)
        #expect(result.failures == [.routeConsumption])
    }
}

private extension CoinAppLifecycleCoordinatorTests {
    static let now = Date(timeIntervalSince1970: 1_788_192_000)

    static func ledger(syncState: CoinBalanceSyncState) throws -> CoinLedgerReconciliationSnapshot {
        CoinLedgerReconciliationSnapshot(
            balance: try CoinBalanceSnapshot(
                purchasedAvailable: 3,
                currentMonthID: MonthlyAllowancePolicy.monthID(containing: now),
                freeAvailable: 1,
                syncState: syncState,
                syncedAt: now,
                ledgerEpochID: syncState == .current ? UUID() : nil,
                hadConfirmedLedger: syncState != .setupRequired
            ),
            purchaseGrants: [],
            events: [],
            pendingProductIdentifiers: [],
            hasPendingReconciliation: false
        )
    }
}

private enum CoinLifecycleTestError: Error {
    case expected
}

private actor CoinLifecycleRecorder {
    enum Event: Equatable {
        case transaction
        case ledger
        case activeOccurrences
        case route(Set<String>)
    }

    private(set) var events: [Event] = []

    func record(_ event: Event) {
        events.append(event)
    }
}
