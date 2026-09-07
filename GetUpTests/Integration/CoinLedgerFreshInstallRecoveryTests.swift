import Foundation
import Testing
@testable import GetUp

@Suite("Coin ledger fresh-install recovery")
struct CoinLedgerFreshInstallRecoveryTests {
    @Test("A current iCloud ledger restores its balance, history, and existing grants only")
    func currentLedgerRestoresWithoutCreatingGrant() throws {
        let snapshot = try Self.currentSnapshot()
        let service = CoinLedgerRecoveryService()

        let result = try service.recoverFreshInstall(
            snapshot: snapshot,
            ledgerState: .current,
            syncedAt: Self.now
        )

        #expect(result.mirror.syncState == .current)
        #expect(result.mirror.ledgerEpochID == Self.currentEpochID)
        #expect(result.mirror.purchasedAvailable == 2)
        #expect(result.mirror.freeAvailable == 1)
        #expect(result.purchaseGrants == snapshot.purchaseGrants)
        #expect(result.events == snapshot.events)
        #expect(result.purchaseGrants.count == 1)
        #expect(result.purchaseGrants[0].transactionID == Self.transactionID)
    }

    @Test("First activation creates an initial epoch and the current-month quota in one command")
    func explicitSetupCreatesInitialLedgerAtomically() async throws {
        let store = CoinLedgerInitializationStoreSpy(result: try Self.initialSetupResult())
        let service = CoinLedgerSetupService(
            performAtomicSetup: { request in
                try await store.initialize(request)
            }
        )

        let result = try await service.activate(
            Self.setupRequest,
            ledgerState: .setupRequired
        )

        #expect(await store.setupRequests == [Self.setupRequest])
        #expect(await store.resetRequests.isEmpty)
        #expect(result.epoch.reason == .initialSetup)
        #expect(result.epoch.suppressedFreeMonthID == nil)
        #expect(result.account.purchasedAvailable == 0)
        #expect(result.allowance.monthID == Self.monthID)
        #expect(result.allowance.quota == 2)
        #expect(result.allowance.available == 2)
    }

    @Test(
        "Setup cannot run for a ledger that is not awaiting first activation",
        arguments: [
            CoinBalanceSyncState.current,
            .syncing,
            .stale,
            .unavailable,
            .deletionConfirmed,
            .resetRequired,
        ]
    )
    func setupRejectsOtherStates(ledgerState: CoinBalanceSyncState) async throws {
        let store = CoinLedgerInitializationStoreSpy(result: try Self.initialSetupResult())
        let service = CoinLedgerSetupService(
            performAtomicSetup: { request in
                try await store.initialize(request)
            }
        )

        await #expect(throws: CoinLedgerSetupServiceError.setupNotRequired) {
            try await service.activate(Self.setupRequest, ledgerState: ledgerState)
        }

        #expect(await store.setupRequests.isEmpty)
    }

    @Test("Confirmed deletion reset creates a separate zero-balance suppressed epoch atomically")
    func explicitResetStartsFromZeroForDeletionMonth() async throws {
        let store = CoinLedgerInitializationStoreSpy(result: try Self.resetResult())
        let service = CoinLedgerResetService(
            performAtomicReset: { request in
                try await store.reset(request)
            }
        )

        let result = try await service.resetAfterConfirmedDeletion(
            Self.resetRequest,
            ledgerState: .deletionConfirmed
        )

        #expect(await store.resetRequests == [Self.resetRequest])
        #expect(await store.setupRequests.isEmpty)
        #expect(result.epoch.reason == .userConfirmedResetAfterDeletion)
        #expect(result.epoch.suppressedFreeMonthID == Self.monthID)
        #expect(result.account.purchasedAvailable == 0)
        #expect(result.account.purchasedReserved == 0)
        #expect(result.allowance.monthID == Self.monthID)
        #expect(result.allowance.quota == 0)
        #expect(result.allowance.available == 0)
    }

    @Test(
        "Uncertain ledger states never recover from a local mirror",
        arguments: [
            CoinBalanceSyncState.syncing,
            .stale,
            .unavailable,
        ]
    )
    func uncertainLedgerRemainsLocked(ledgerState: CoinBalanceSyncState) throws {
        let service = CoinLedgerRecoveryService()

        #expect(throws: CoinLedgerRecoveryServiceError.ledgerNotCurrent) {
            try service.recoverFreshInstall(
                snapshot: Self.currentSnapshot(),
                ledgerState: ledgerState,
                syncedAt: Self.now
            )
        }
    }

    @Test("Missing remote data cannot be replaced by StoreKit history or a local mirror")
    func missingRemoteLedgerDoesNotRecover() throws {
        let service = CoinLedgerRecoveryService()

        #expect(throws: CoinLedgerRecoveryServiceError.remoteLedgerMissing) {
            try service.recoverFreshInstall(
                snapshot: nil,
                ledgerState: .setupRequired,
                syncedAt: Self.now
            )
        }
    }

    @Test("A stored account balance must equal the purchase event projection")
    func accountBalanceMustMatchProjection() throws {
        let snapshot = try Self.currentSnapshot()
        let mismatched = try Self.replacing(
            snapshot,
            account: CoinAccount(
                purchasedAvailable: 3,
                purchasedReserved: 0,
                revision: snapshot.account.revision,
                updatedAt: snapshot.account.updatedAt
            )
        )

        #expect(throws: CoinLedgerRecoveryServiceError.invalidProjection) {
            try CoinLedgerRecoveryService().recoverFreshInstall(
                snapshot: mismatched,
                ledgerState: .current,
                syncedAt: Self.now
            )
        }
    }

    @Test("Refund events must reference an existing purchase grant")
    func refundMustReferenceGrant() throws {
        let snapshot = try Self.currentSnapshot()
        let orphan = try Self.event(
            id: "refund:orphan",
            kind: .refundAdjustment,
            quantity: 1,
            relatedTransactionID: 99_999
        )

        #expect(throws: CoinLedgerRecoveryServiceError.invalidProjection) {
            try CoinLedgerRecoveryService().recoverFreshInstall(
                snapshot: Self.replacing(snapshot, events: snapshot.events + [orphan]),
                ledgerState: .current,
                syncedAt: Self.now
            )
        }
    }

    @Test("Grant adjustment must equal refund events minus reversals")
    func grantAdjustmentMustMatchEvents() throws {
        let snapshot = try Self.currentSnapshot()
        let grant = try #require(snapshot.purchaseGrants.first)
        let mismatchedGrant = try PurchaseGrant(
            transactionID: grant.transactionID,
            environment: grant.environment,
            productID: grant.productID,
            quantity: grant.quantity,
            purchaseDate: grant.purchaseDate,
            adjustedQuantity: 0
        )

        #expect(throws: CoinLedgerRecoveryServiceError.invalidProjection) {
            try CoinLedgerRecoveryService().recoverFreshInstall(
                snapshot: Self.replacing(snapshot, purchaseGrants: [mismatchedGrant]),
                ledgerState: .current,
                syncedAt: Self.now
            )
        }
    }

    @Test("Refund and reversal projection is independent of CloudKit event order")
    func refundProjectionIsOrderIndependent() throws {
        let snapshot = try Self.currentSnapshot()
        let purchase = try #require(snapshot.events.first { $0.kind == .purchaseGrant })
        let spend = try #require(snapshot.events.first { $0.kind == .spend })
        let activeRefund = try Self.event(
            id: "refund:sandbox:\(Self.transactionID):1",
            kind: .refundAdjustment,
            quantity: 1,
            relatedTransactionID: Self.transactionID
        )
        let reversedRefund = try Self.event(
            id: "refund:sandbox:\(Self.transactionID):2",
            kind: .refundAdjustment,
            quantity: 2,
            relatedTransactionID: Self.transactionID
        )
        let reversal = try Self.event(
            id: "reversal:\(reversedRefund.eventID)",
            kind: .reversal,
            quantity: 2,
            relatedTransactionID: Self.transactionID
        )
        let reordered = Self.replacing(
            snapshot,
            events: [purchase, reversal, spend, activeRefund, reversedRefund]
        )

        let result = try CoinLedgerRecoveryService().recoverFreshInstall(
            snapshot: reordered,
            ledgerState: .current,
            syncedAt: Self.now
        )

        #expect(result.mirror.purchasedAvailable == 2)
        #expect(result.events == reordered.events)
    }

    @Test("Duplicate event IDs invalidate recovery")
    func duplicateEventsAreRejected() throws {
        let snapshot = try Self.currentSnapshot()
        let duplicate = try #require(snapshot.events.first)

        #expect(throws: CoinLedgerRecoveryServiceError.invalidProjection) {
            try CoinLedgerRecoveryService().recoverFreshInstall(
                snapshot: Self.replacing(snapshot, events: snapshot.events + [duplicate]),
                ledgerState: .current,
                syncedAt: Self.now
            )
        }
    }
}

private extension CoinLedgerFreshInstallRecoveryTests {
    static let monthID = "2026-09"
    static let now = Date(timeIntervalSince1970: 1_788_192_000)
    static let currentEpochID = UUID(uuidString: "00000000-0000-4000-8000-000000000901")!
    static let setupEpochID = UUID(uuidString: "00000000-0000-4000-8000-000000000902")!
    static let resetEpochID = UUID(uuidString: "00000000-0000-4000-8000-000000000903")!
    static let spendCommandID = UUID(uuidString: "00000000-0000-4000-8000-000000000904")!
    static let transactionID: UInt64 = 9_001

    static var setupRequest: CoinLedgerSetupRequest {
        CoinLedgerSetupRequest(
            epochID: setupEpochID,
            monthID: monthID,
            confirmedAt: now,
            disclosureVersion: 1
        )
    }

    static var resetRequest: CoinLedgerResetRequest {
        CoinLedgerResetRequest(
            epochID: resetEpochID,
            monthID: monthID,
            confirmedAt: now,
            disclosureVersion: 1
        )
    }

    static func currentSnapshot() throws -> CoinLedgerRecoverySnapshot {
        let grant = try PurchaseGrant(
            transactionID: transactionID,
            environment: .sandbox,
            productID: "com.dxyn02.GetUp.coin.5",
            quantity: 5,
            purchaseDate: now.addingTimeInterval(-86_400),
            adjustedQuantity: 1
        )
        let events = [
            try event(
                id: "purchase:sandbox:\(transactionID)",
                kind: .purchaseGrant,
                quantity: 5,
                relatedTransactionID: transactionID
            ),
            try event(
                id: "spend:\(spendCommandID.uuidString.lowercased())",
                kind: .spend,
                quantity: 2,
                relatedCommandID: spendCommandID,
                occurrenceID: "occurrence-1"
            ),
            try event(
                id: "refund:sandbox:\(transactionID)",
                kind: .refundAdjustment,
                quantity: 1,
                relatedTransactionID: transactionID
            ),
        ]

        return CoinLedgerRecoverySnapshot(
            epoch: LedgerEpoch(
                epochID: currentEpochID,
                createdAt: now.addingTimeInterval(-172_800),
                reason: .initialSetup,
                suppressedFreeMonthID: nil,
                disclosureVersion: 1
            ),
            account: try CoinAccount(
                purchasedAvailable: 2,
                purchasedReserved: 0,
                revision: 4,
                updatedAt: now
            ),
            allowance: try MonthlyAllowance(
                monthID: monthID,
                quota: 2,
                used: 1,
                reserved: 0,
                creationDate: now.addingTimeInterval(-86_400),
                updatedAt: now
            ),
            purchaseGrants: [grant],
            events: events
        )
    }

    static func initialSetupResult() throws -> CoinLedgerInitializationResult {
        try CoinLedgerInitializationResult(
            epoch: LedgerEpoch(
                epochID: setupEpochID,
                createdAt: now,
                reason: .initialSetup,
                suppressedFreeMonthID: nil,
                disclosureVersion: 1
            ),
            account: CoinAccount(
                purchasedAvailable: 0,
                purchasedReserved: 0,
                revision: 0,
                updatedAt: now
            ),
            allowance: MonthlyAllowance(
                monthID: monthID,
                quota: 2,
                used: 0,
                reserved: 0,
                creationDate: now,
                updatedAt: now
            )
        )
    }

    static func resetResult() throws -> CoinLedgerInitializationResult {
        try CoinLedgerInitializationResult(
            epoch: LedgerEpoch(
                epochID: resetEpochID,
                createdAt: now,
                reason: .userConfirmedResetAfterDeletion,
                suppressedFreeMonthID: monthID,
                disclosureVersion: 1
            ),
            account: CoinAccount(
                purchasedAvailable: 0,
                purchasedReserved: 0,
                revision: 0,
                updatedAt: now
            ),
            allowance: MonthlyAllowance(
                monthID: monthID,
                quota: 0,
                used: 0,
                reserved: 0,
                creationDate: now,
                updatedAt: now
            )
        )
    }

    static func event(
        id: String,
        kind: CoinLedgerEventKind,
        quantity: Int,
        relatedTransactionID: UInt64? = nil,
        relatedCommandID: UUID? = nil,
        occurrenceID: String? = nil
    ) throws -> CoinLedgerEvent {
        try CoinLedgerEvent(
            eventID: id,
            kind: kind,
            source: .purchased,
            quantity: quantity,
            relatedTransactionID: relatedTransactionID,
            relatedCommandID: relatedCommandID,
            occurrenceID: occurrenceID,
            createdAt: now
        )
    }

    static func replacing(
        _ snapshot: CoinLedgerRecoverySnapshot,
        account: CoinAccount? = nil,
        purchaseGrants: [PurchaseGrant]? = nil,
        events: [CoinLedgerEvent]? = nil
    ) -> CoinLedgerRecoverySnapshot {
        CoinLedgerRecoverySnapshot(
            epoch: snapshot.epoch,
            account: account ?? snapshot.account,
            allowance: snapshot.allowance,
            purchaseGrants: purchaseGrants ?? snapshot.purchaseGrants,
            events: events ?? snapshot.events
        )
    }
}

private actor CoinLedgerInitializationStoreSpy {
    private let result: CoinLedgerInitializationResult
    private(set) var setupRequests: [CoinLedgerSetupRequest] = []
    private(set) var resetRequests: [CoinLedgerResetRequest] = []

    init(result: CoinLedgerInitializationResult) {
        self.result = result
    }

    func initialize(
        _ request: CoinLedgerSetupRequest
    ) async throws -> CoinLedgerInitializationResult {
        setupRequests.append(request)
        return result
    }

    func reset(
        _ request: CoinLedgerResetRequest
    ) async throws -> CoinLedgerInitializationResult {
        resetRequests.append(request)
        return result
    }
}
