import Foundation
import Testing
@testable import GetUp

@Suite("Coin ledger lifecycle")
struct CoinLedgerLifecycleTests {
    @Test(
        "Every non-current ledger state blocks StoreKit before the purchase API",
        arguments: [
            MonthlyAllowanceLedgerState.setupRequired,
            .syncing,
            .stale,
            .unavailable,
            .deletionConfirmed,
            .resetRequired,
        ]
    )
    func nonCurrentLedgerNeverCallsPurchaseAPI(
        ledgerState: MonthlyAllowanceLedgerState
    ) async throws {
        let storefront = CoinStorefrontFake(purchases: [.success(.userCancelled)])
        let repository = CoinLedgerRepositoryFake()
        let service = CoinPurchaseService(
            catalog: try CoinProductCatalog(infoDictionary: Self.catalogInfoDictionary),
            storefront: storefront,
            repository: repository,
            fetchLedgerState: { ledgerState }
        )

        do {
            _ = try await service.purchase(productID: Self.productID)
            Issue.record("A non-current ledger started a StoreKit purchase")
        } catch {
            #expect((error as? any StableLiveActivityCoinError)?.errorCode == .ledgerNotCurrent)
        }

        #expect(await storefront.purchaseRequests.isEmpty)
        #expect(await storefront.finishRequests.isEmpty)
        #expect(await repository.operations.isEmpty)
    }

    @Test("A transient outage remains unavailable and never becomes confirmed deletion")
    func transientFailureIsNotDeletion() async throws {
        let adapter = CoinLedgerSyncAdapter(accountSessionID: Self.accountSessionID)
        let localMirror = try Self.localMirror(purchasedAvailable: 5, freeAvailable: 1)

        let outcome = try await adapter.applyInitialFetch(
            .unavailable,
            accountSessionID: Self.accountSessionID,
            localMirror: localMirror,
            currentMonthID: Self.monthID,
            fetchedAt: ContinuousClock().now,
            syncedAt: Self.now
        )

        #expect(outcome.mirror.syncState == .unavailable)
        #expect(outcome.mirror.purchasedAvailable == 5)
        #expect(outcome.mirror.freeAvailable == 1)
        #expect(!outcome.recoveredFromRemote)
    }

    @Test("A confirmed zone deletion discards local balances without restoring them")
    func confirmedDeletionDoesNotRestoreLocalMirror() async throws {
        let adapter = CoinLedgerSyncAdapter(accountSessionID: Self.accountSessionID)
        let localMirror = try Self.localMirror(purchasedAvailable: 5, freeAvailable: 2)

        let outcome = try await adapter.applyInitialFetch(
            .noLedger(deletionConfirmed: true),
            accountSessionID: Self.accountSessionID,
            localMirror: localMirror,
            currentMonthID: Self.monthID,
            fetchedAt: ContinuousClock().now,
            syncedAt: Self.now
        )

        #expect(outcome.mirror.syncState == .deletionConfirmed)
        #expect(outcome.mirror.purchasedAvailable == 0)
        #expect(outcome.mirror.freeAvailable == 0)
        #expect(outcome.mirror.ledgerEpochID == nil)
        #expect(outcome.mirror.hadConfirmedLedger)
        #expect(!outcome.recoveredFromRemote)
    }

    @Test("Ledger absence without deletion evidence requires setup instead of reset")
    func firstActivationAbsenceIsNotDeletion() async throws {
        let adapter = CoinLedgerSyncAdapter(accountSessionID: Self.accountSessionID)

        let outcome = try await adapter.applyInitialFetch(
            .noLedger(deletionConfirmed: false),
            accountSessionID: Self.accountSessionID,
            localMirror: nil,
            currentMonthID: Self.monthID,
            fetchedAt: ContinuousClock().now,
            syncedAt: Self.now
        )

        #expect(outcome.mirror.syncState == .setupRequired)
        #expect(outcome.mirror.purchasedAvailable == 0)
        #expect(outcome.mirror.freeAvailable == 0)
        #expect(!outcome.mirror.hadConfirmedLedger)
        #expect(!outcome.recoveredFromRemote)
    }

    @Test("Reset rejects every state except confirmed deletion without writing")
    func resetRequiresConfirmedDeletion() async throws {
        let resetStore = CoinLedgerResetStoreSpy()
        let service = CoinLedgerResetService(
            performAtomicReset: { request in
                try await resetStore.reset(request)
            }
        )
        let request = Self.resetRequest

        for state in [
            CoinBalanceSyncState.setupRequired,
            .current,
            .syncing,
            .stale,
            .unavailable,
            .resetRequired,
        ] {
            await #expect(throws: CoinLedgerResetServiceError.deletionNotConfirmed) {
                try await service.resetAfterConfirmedDeletion(
                    request,
                    ledgerState: state
                )
            }
        }

        #expect(await resetStore.requests.isEmpty)
    }

    @Test("An explicit reset action is the only path that reaches atomic reset storage")
    func explicitResetInvokesStorageOnce() async throws {
        let resetStore = CoinLedgerResetStoreSpy()
        let service = CoinLedgerResetService(
            performAtomicReset: { request in
                try await resetStore.reset(request)
            }
        )

        try await service.resetAfterConfirmedDeletion(
            Self.resetRequest,
            ledgerState: .deletionConfirmed
        )

        #expect(await resetStore.requests == [Self.resetRequest])
    }
}

private extension CoinLedgerLifecycleTests {
    static let productID = "com.dxyn02.GetUp.coin.1"
    static let accountSessionID = "icloud-account-a"
    static let monthID = "2026-09"
    static let now = Date(timeIntervalSince1970: 1_788_192_000)
    static let epochID = UUID(uuidString: "00000000-0000-4000-8000-000000000801")!
    static let resetEpochID = UUID(uuidString: "00000000-0000-4000-8000-000000000802")!

    static var catalogInfoDictionary: [String: Any] {
        [
            SharedIdentifiers.coinProductCatalogInfoDictionaryKey: [[
                SharedIdentifiers.coinProductIdentifierCatalogKey: productID,
                SharedIdentifiers.coinProductQuantityCatalogKey: 1,
            ]],
        ]
    }

    static var resetRequest: CoinLedgerResetRequest {
        CoinLedgerResetRequest(
            epochID: resetEpochID,
            monthID: monthID,
            confirmedAt: now,
            disclosureVersion: 1
        )
    }

    static func localMirror(
        purchasedAvailable: Int,
        freeAvailable: Int
    ) throws -> CoinBalanceSnapshot {
        try CoinBalanceSnapshot(
            purchasedAvailable: purchasedAvailable,
            currentMonthID: monthID,
            freeAvailable: freeAvailable,
            syncState: .current,
            syncedAt: now,
            ledgerEpochID: epochID,
            hadConfirmedLedger: true
        )
    }
}

private actor CoinLedgerResetStoreSpy {
    private(set) var requests: [CoinLedgerResetRequest] = []

    func reset(_ request: CoinLedgerResetRequest) async throws -> CoinLedgerInitializationResult {
        requests.append(request)
        return try CoinLedgerInitializationResult(
            epoch: LedgerEpoch(
                epochID: request.epochID,
                createdAt: request.confirmedAt,
                reason: .userConfirmedResetAfterDeletion,
                suppressedFreeMonthID: request.monthID,
                disclosureVersion: request.disclosureVersion
            ),
            account: CoinAccount(
                purchasedAvailable: 0,
                purchasedReserved: 0,
                revision: 0,
                updatedAt: request.confirmedAt
            ),
            allowance: MonthlyAllowance(
                monthID: request.monthID,
                quota: 0,
                used: 0,
                reserved: 0,
                creationDate: request.confirmedAt,
                updatedAt: request.confirmedAt
            )
        )
    }
}
