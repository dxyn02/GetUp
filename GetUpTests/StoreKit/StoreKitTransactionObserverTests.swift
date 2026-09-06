import Foundation
import Testing
@testable import GetUp

@Suite("StoreKit transaction observer")
struct StoreKitTransactionObserverTests {
    @Test("A failed CloudKit commit never finishes the transaction")
    func commitFailureLeavesTransactionUnfinished() async throws {
        let recorder = PurchaseLifecycleRecorder()
        let transaction = Self.transaction(id: 401)
        let storefront = ObserverStorefrontSpy(recorder: recorder)
        let ledger = ObserverPurchaseLedgerFake(
            recorder: recorder,
            grantFailure: .database(.serverUnavailable)
        )
        let service = try Self.service(storefront: storefront, ledger: ledger)

        await #expect(throws: CoinLedgerRepositoryError.database(.serverUnavailable)) {
            try await service.processVerifiedTransaction(transaction)
        }

        #expect(await storefront.finishRequests.isEmpty)
        #expect(recorder.events == [.grantAttempt(401), .grantFailed(401)])
    }

    @Test("A finish failure is recovered from unfinished transactions without another grant")
    func finishFailureRecoversOnNextLaunch() async throws {
        let recorder = PurchaseLifecycleRecorder()
        let transaction = Self.transaction(id: 402)
        let ledger = ObserverPurchaseLedgerFake(recorder: recorder)
        let firstStorefront = ObserverStorefrontSpy(
            recorder: recorder,
            finishScripts: [.failure(.finishFailed)]
        )
        let firstService = try Self.service(storefront: firstStorefront, ledger: ledger)

        await #expect(throws: CoinStoreError.finishFailed) {
            try await firstService.processVerifiedTransaction(transaction)
        }
        #expect(await ledger.createdGrantCount == 1)
        #expect(await firstStorefront.finishRequests == [402])

        let relaunchedStorefront = ObserverStorefrontSpy(
            recorder: recorder,
            unfinished: [.verified(transaction)],
            finishScripts: [.success(())]
        )
        let observer = try Self.observer(storefront: relaunchedStorefront, ledger: ledger)
        try await observer.start()
        try await observer.waitForUpdatesToFinish()

        #expect(await ledger.createdGrantCount == 1)
        #expect(await ledger.grantRequests.count == 2)
        #expect(await relaunchedStorefront.finishRequests == [402])
        #expect(recorder.events.filter { $0 == .grantCommitted(402) }.count == 2)
    }

    @Test("Launch opens the updates listener before requesting unfinished transactions")
    func launchStartsListenerFirst() async throws {
        let recorder = PurchaseLifecycleRecorder()
        let storefront = ObserverStorefrontSpy(recorder: recorder)
        let ledger = ObserverPurchaseLedgerFake(recorder: recorder)
        let observer = try Self.observer(storefront: storefront, ledger: ledger)

        try await observer.start()
        try await observer.waitForUpdatesToFinish()

        let events = recorder.events
        let listenerIndex = try #require(events.firstIndex(of: .listenerOpened))
        let unfinishedIndex = try #require(events.firstIndex(of: .unfinishedRequested))
        #expect(listenerIndex < unfinishedIndex)
    }

    @Test("A pending purchase is granted once when a verified update arrives later")
    func pendingPurchaseCompletesFromUpdates() async throws {
        let recorder = PurchaseLifecycleRecorder()
        let transaction = Self.transaction(id: 403)
        let storefront = ObserverStorefrontSpy(
            recorder: recorder,
            purchases: [.success(.pending)],
            updates: [.verified(transaction)],
            finishScripts: [.success(())]
        )
        let ledger = ObserverPurchaseLedgerFake(recorder: recorder)
        let service = try Self.service(storefront: storefront, ledger: ledger)

        let pending = try await service.purchase(productID: Self.threeCoinProductID)
        #expect(pending == .pending)
        #expect(await ledger.grantRequests.isEmpty)

        let observer = StoreKitTransactionObserver(
            storefront: storefront,
            processVerifiedTransaction: { transaction in
                try await service.processVerifiedTransaction(transaction)
            }
        )
        try await observer.start()
        try await observer.waitForUpdatesToFinish()

        #expect(await ledger.createdGrantCount == 1)
        #expect(await storefront.finishRequests == [403])
    }

    @Test("Unverified updates never grant and do not stop later verified updates")
    func unverifiedUpdateIsIgnoredSafely() async throws {
        let recorder = PurchaseLifecycleRecorder()
        let verified = Self.transaction(id: 404)
        let storefront = ObserverStorefrontSpy(
            recorder: recorder,
            updates: [.unverified, .verified(verified)],
            finishScripts: [.success(())]
        )
        let ledger = ObserverPurchaseLedgerFake(recorder: recorder)
        let observer = try Self.observer(storefront: storefront, ledger: ledger)

        try await observer.start()
        try await observer.waitForUpdatesToFinish()

        #expect(await ledger.grantRequests.map(\.transaction.id) == [404])
        #expect(await storefront.finishRequests == [404])
    }

    @Test("The same transaction from unfinished and updates creates one grant")
    func duplicateLifecycleDeliveryIsIdempotent() async throws {
        let recorder = PurchaseLifecycleRecorder()
        let transaction = Self.transaction(id: 405)
        let storefront = ObserverStorefrontSpy(
            recorder: recorder,
            unfinished: [.verified(transaction)],
            updates: [.verified(transaction)],
            finishScripts: [.success(()), .success(())]
        )
        let ledger = ObserverPurchaseLedgerFake(recorder: recorder)
        let observer = try Self.observer(storefront: storefront, ledger: ledger)

        try await observer.start()
        try await observer.waitForUpdatesToFinish()

        #expect(await ledger.createdGrantCount == 1)
        #expect(await ledger.grantRequests.count == 2)
        #expect(await storefront.finishRequests == [405, 405])
    }

    @Test("Every finish attempt occurs after the corresponding grant commit")
    func grantAlwaysCommitsBeforeFinish() async throws {
        let recorder = PurchaseLifecycleRecorder()
        let transactions = [Self.transaction(id: 406), Self.transaction(id: 407)]
        let storefront = ObserverStorefrontSpy(
            recorder: recorder,
            unfinished: transactions.map { .verified($0) },
            finishScripts: [.success(()), .success(())]
        )
        let ledger = ObserverPurchaseLedgerFake(recorder: recorder)
        let observer = try Self.observer(storefront: storefront, ledger: ledger)

        try await observer.start()
        try await observer.waitForUpdatesToFinish()

        let events = recorder.events
        for transaction in transactions {
            let commitIndex = try #require(
                events.firstIndex(of: .grantCommitted(transaction.id))
            )
            let finishIndex = try #require(
                events.firstIndex(of: .finishAttempt(transaction.id))
            )
            #expect(commitIndex < finishIndex)
        }
    }
}

private extension StoreKitTransactionObserverTests {
    static let threeCoinProductID = "com.dxyn02.GetUp.coin.3"
    static let purchaseDate = Date(timeIntervalSince1970: 1_788_192_000)

    static func service(
        storefront: any CoinStorefront,
        ledger: any CoinLedgerRepository
    ) throws -> CoinPurchaseService {
        CoinPurchaseService(
            catalog: try CoinProductCatalog(infoDictionary: catalogInfoDictionary),
            storefront: storefront,
            repository: ledger,
            fetchLedgerState: { .current(epoch: ledgerEpoch) }
        )
    }

    static func observer(
        storefront: any CoinStorefront,
        ledger: any CoinLedgerRepository
    ) throws -> StoreKitTransactionObserver {
        let service = try service(storefront: storefront, ledger: ledger)
        return StoreKitTransactionObserver(
            storefront: storefront,
            processVerifiedTransaction: { transaction in
                try await service.processVerifiedTransaction(transaction)
            }
        )
    }

    static var ledgerEpoch: LedgerEpoch {
        LedgerEpoch(
            epochID: UUID(uuidString: "00000000-0000-4000-8000-000000000702")!,
            createdAt: purchaseDate,
            reason: .initialSetup,
            suppressedFreeMonthID: nil,
            disclosureVersion: 1
        )
    }

    static var catalogInfoDictionary: [String: Any] {
        [
            SharedIdentifiers.coinProductCatalogInfoDictionaryKey: [
                entry(productID: "com.dxyn02.GetUp.coin.1", quantity: 1),
                entry(productID: threeCoinProductID, quantity: 3),
                entry(productID: "com.dxyn02.GetUp.coin.5", quantity: 5),
            ],
        ]
    }

    static func entry(productID: String, quantity: Int) -> [String: Any] {
        [
            SharedIdentifiers.coinProductIdentifierCatalogKey: productID,
            SharedIdentifiers.coinProductQuantityCatalogKey: quantity,
        ]
    }

    static func transaction(id: UInt64) -> VerifiedCoinTransaction {
        VerifiedCoinTransaction(
            id: id,
            environment: .sandbox,
            productID: threeCoinProductID,
            purchaseDate: purchaseDate,
            revocationDate: nil
        )
    }
}

private final class PurchaseLifecycleRecorder: @unchecked Sendable {
    enum Event: Equatable, Sendable {
        case listenerOpened
        case unfinishedRequested
        case grantAttempt(UInt64)
        case grantCommitted(UInt64)
        case grantFailed(UInt64)
        case finishAttempt(UInt64)
    }

    private let lock = NSLock()
    private var storage: [Event] = []

    var events: [Event] {
        lock.withLock { storage }
    }

    func record(_ event: Event) {
        lock.withLock { storage.append(event) }
    }
}

private actor ObserverStorefrontSpy: CoinStorefront {
    private let recorder: PurchaseLifecycleRecorder
    private var purchaseScripts: [LiveActivityCoinScript<CoinStorePurchaseResult, CoinStoreError>]
    private var finishScripts: [LiveActivityCoinScript<Void, CoinStoreError>]
    private let unfinished: [CoinStoreTransactionUpdate]
    nonisolated let updates: AsyncStream<CoinStoreTransactionUpdate>

    private(set) var finishRequests: [UInt64] = []

    init(
        recorder: PurchaseLifecycleRecorder,
        purchases: [LiveActivityCoinScript<CoinStorePurchaseResult, CoinStoreError>] = [],
        unfinished: [CoinStoreTransactionUpdate] = [],
        updates: [CoinStoreTransactionUpdate] = [],
        finishScripts: [LiveActivityCoinScript<Void, CoinStoreError>] = []
    ) {
        self.recorder = recorder
        purchaseScripts = purchases
        self.unfinished = unfinished
        self.updates = AsyncStream { continuation in
            for update in updates {
                continuation.yield(update)
            }
            continuation.finish()
        }
        self.finishScripts = finishScripts
    }

    func products(for identifiers: Set<String>) async throws -> [CoinStoreProduct] {
        throw CoinStoreError.productUnavailable
    }

    func purchase(productID: String) async throws -> CoinStorePurchaseResult {
        guard !purchaseScripts.isEmpty else {
            throw CoinStoreError.purchaseFailed
        }
        return try purchaseScripts.removeFirst().get()
    }

    func unfinishedTransactions() async -> [CoinStoreTransactionUpdate] {
        recorder.record(.unfinishedRequested)
        return unfinished
    }

    nonisolated func transactionUpdates() -> AsyncStream<CoinStoreTransactionUpdate> {
        recorder.record(.listenerOpened)
        return updates
    }

    func finish(transactionID: UInt64) async throws {
        finishRequests.append(transactionID)
        recorder.record(.finishAttempt(transactionID))
        guard !finishScripts.isEmpty else {
            throw CoinStoreError.finishFailed
        }
        try finishScripts.removeFirst().get()
    }
}

private actor ObserverPurchaseLedgerFake: CoinLedgerRepository {
    private let recorder: PurchaseLifecycleRecorder
    private let grantFailure: CoinLedgerRepositoryError?
    private var grantsByKey: [String: PurchaseGrant] = [:]

    private(set) var grantRequests: [PurchaseGrantRequest] = []
    private(set) var createdGrantCount = 0

    init(
        recorder: PurchaseLifecycleRecorder,
        grantFailure: CoinLedgerRepositoryError? = nil
    ) {
        self.recorder = recorder
        self.grantFailure = grantFailure
    }

    func grantPurchase(_ request: PurchaseGrantRequest) async throws -> PurchaseGrant {
        let transaction = request.transaction
        grantRequests.append(request)
        recorder.record(.grantAttempt(transaction.id))
        if let grantFailure {
            recorder.record(.grantFailed(transaction.id))
            throw grantFailure
        }

        let key = "\(transaction.environment.rawValue):\(transaction.id)"
        if let existing = grantsByKey[key] {
            guard
                existing.productID == transaction.productID,
                existing.quantity == request.quantity
            else {
                throw CoinLedgerRepositoryError.database(.invalidRecord)
            }
            recorder.record(.grantCommitted(transaction.id))
            return existing
        }

        let grant = try PurchaseGrant(
            transactionID: transaction.id,
            environment: transaction.environment,
            productID: transaction.productID,
            quantity: request.quantity,
            purchaseDate: transaction.purchaseDate,
            adjustedQuantity: 0
        )
        grantsByKey[key] = grant
        createdGrantCount += 1
        recorder.record(.grantCommitted(transaction.id))
        return grant
    }

    func createAllowanceIfNeeded(
        _ request: MonthlyAllowanceCreationRequest
    ) async throws -> MonthlyAllowance {
        throw CoinLedgerRepositoryError.database(.unexpectedRequest)
    }

    func reserveMonthlyFree(
        _ request: MonthlyFreeReservationRequest
    ) async throws -> CoinReleaseReservation {
        throw CoinLedgerRepositoryError.database(.unexpectedRequest)
    }

    func reservePurchasedCoin(
        _ request: PurchasedCoinReservationRequest
    ) async throws -> CoinReleaseReservation {
        throw CoinLedgerRepositoryError.database(.unexpectedRequest)
    }

    func fetchReleaseCommand(commandID: UUID) async throws -> ReleaseCommand? {
        throw CoinLedgerRepositoryError.database(.unexpectedRequest)
    }

    func markReleaseApplied(commandID: UUID, at date: Date) async throws -> ReleaseCommand {
        throw CoinLedgerRepositoryError.database(.unexpectedRequest)
    }

    func commitRelease(commandID: UUID, at date: Date) async throws -> ReleaseCommand {
        throw CoinLedgerRepositoryError.database(.unexpectedRequest)
    }

    func compensateRelease(commandID: UUID, at date: Date) async throws -> ReleaseCommand {
        throw CoinLedgerRepositoryError.database(.unexpectedRequest)
    }
}
