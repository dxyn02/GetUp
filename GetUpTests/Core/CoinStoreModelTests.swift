import Foundation
import Testing
@testable import GetUp

@Suite("Coin store model")
@MainActor
struct CoinStoreModelTests {
    @Test(
        "Balance presentation distinguishes loading, empty, stale, and current states",
        arguments: [
            (CoinBalanceSyncState.syncing, 1, 3, CoinStoreBalanceContentState.loading),
            (.current, 0, 0, .empty),
            (.stale, 1, 3, .stale),
            (.unavailable, 1, 3, .stale),
            (.current, 1, 3, .current),
        ]
    )
    func mapsBalanceContentState(
        syncState: CoinBalanceSyncState,
        free: Int,
        purchased: Int,
        expected: CoinStoreBalanceContentState
    ) throws {
        let model = makeModel(
            ledger: try ledger(
                syncState: syncState,
                purchased: purchased,
                free: free
            )
        )

        let state = CoinStoreBalanceContentState(
            balance: model.balance,
            displayedFreeAvailable: free
        )

        #expect(state == expected)
    }

    @Test("Loading balance hides numeric mirrors while accessible values include units")
    func balanceAccessibilityValues() {
        #expect(CoinStoreBalanceContentState.loading.freeDisplayValue(2) == "—")
        #expect(CoinStoreBalanceContentState.loading.freeAccessibilityValue(2) == "확인 중")
        #expect(CoinStoreBalanceContentState.current.freeAccessibilityValue(2) == "2회")
        #expect(CoinStoreBalanceContentState.current.purchasedAccessibilityValue(3) == "3개")
    }

    @Test(
        "Every ledger state maps to a distinct store availability",
        arguments: [
            (CoinBalanceSyncState.current, CoinStoreAvailability.ready),
            (.setupRequired, .setupRequired),
            (.syncing, .syncing),
            (.stale, .iCloudRecoveryRequired),
            (.unavailable, .iCloudRecoveryRequired),
            (.deletionConfirmed, .ledgerResetRequired),
            (.resetRequired, .ledgerResetRequired),
        ]
    )
    func mapsLedgerState(
        syncState: CoinBalanceSyncState,
        expected: CoinStoreAvailability
    ) throws {
        let model = makeModel(ledger: try ledger(syncState: syncState))

        #expect(model.availability == expected)
    }

    @Test("A first setup presents the two allowances available after activation")
    func setupRequiredMonthlyAllowance() throws {
        let model = makeModel(
            ledger: try ledger(syncState: .setupRequired, free: 0)
        )

        #expect(
            model.monthlyAllowanceDisplay
                == .setupRequired(monthID: "2026-09", availableAfterSetup: 2)
        )
    }

    @Test("A current ledger presents its authoritative monthly allowance balance")
    func currentMonthlyAllowance() throws {
        let model = makeModel(
            ledger: try ledger(syncState: .current, free: 1)
        )

        #expect(
            model.monthlyAllowanceDisplay
                == .current(monthID: "2026-09", available: 1)
        )
    }

    @Test(
        "A confirmed deletion or pending reset suppresses this month's allowance",
        arguments: [
            CoinBalanceSyncState.deletionConfirmed,
            .resetRequired,
        ]
    )
    func resetMonthlyAllowance(syncState: CoinBalanceSyncState) throws {
        let model = makeModel(
            ledger: try ledger(syncState: syncState, free: 2)
        )

        #expect(
            model.monthlyAllowanceDisplay
                == .resetRequired(monthID: "2026-09", available: 0)
        )
    }

    @Test("Pending reconciliation blocks purchases before the current balance is considered")
    func reconciliationTakesPriority() throws {
        let model = makeModel(
            ledger: try ledger(hasPendingReconciliation: true)
        )

        #expect(model.availability == .reconciliationRequired)
        #expect(!model.isPurchaseEnabled(productID: Self.oneCoinProductID))
    }

    @Test(
        "A non-current ledger never starts StoreKit purchase",
        arguments: [
            CoinBalanceSyncState.setupRequired,
            .syncing,
            .stale,
            .unavailable,
            .deletionConfirmed,
            .resetRequired,
        ]
    )
    func nonCurrentLedgerBlocksPurchase(syncState: CoinBalanceSyncState) async throws {
        let executor = PurchaseExecutorSpy(result: .pending)
        let model = makeModel(
            ledger: try ledger(syncState: syncState),
            executePurchase: { productID in
                try await executor.execute(productID)
            }
        )
        await model.loadProducts()

        #expect(!model.requestPurchaseConfirmation(productID: Self.oneCoinProductID))
        await model.confirmPurchase()

        #expect(await executor.requests.isEmpty)
    }

    @Test("Products are ordered by quantity and only loaded products can be purchased")
    func loadsProducts() async throws {
        let loader = ProductLoaderSpy(results: [.success(Self.catalogResult)])
        let model = makeModel(loadProducts: { try await loader.load() })

        await model.loadProducts()

        #expect(model.products.map(\.quantity) == [1, 3, 5])
        #expect(model.unavailableProductIdentifiers == [Self.unavailableProductID])
        #expect(model.productLoadError == nil)
        #expect(model.isPurchaseEnabled(productID: Self.oneCoinProductID))
        #expect(!model.isPurchaseEnabled(productID: Self.unavailableProductID))
        #expect(await loader.requestCount == 1)
    }

    @Test("A failed reload clears stale localized prices")
    func failedReloadClearsProducts() async throws {
        let loader = ProductLoaderSpy(results: [
            .success(Self.catalogResult),
            .failure(CoinStoreError.productUnavailable),
        ])
        let model = makeModel(loadProducts: { try await loader.load() })

        await model.loadProducts()
        #expect(!model.products.isEmpty)

        await model.loadProducts()

        #expect(model.products.isEmpty)
        #expect(model.productLoadError == .storeProductUnavailable)
        #expect(!model.isPurchaseEnabled(productID: Self.oneCoinProductID))
    }

    @Test("Purchase confirmation is explicit and cancellation never executes a purchase")
    func confirmationCanBeCancelled() async throws {
        let executor = PurchaseExecutorSpy(result: .pending)
        let model = makeModel(executePurchase: { productID in
            try await executor.execute(productID)
        })
        await model.loadProducts()

        #expect(model.requestPurchaseConfirmation(productID: Self.threeCoinProductID))
        #expect(model.purchaseState == .confirmationRequested(Self.threeCoinProductID))
        model.cancelPurchaseConfirmation()

        #expect(model.purchaseState == .idle)
        #expect(await executor.requests.isEmpty)
    }

    @Test("A verified purchase replaces balance and history with authoritative ledger state")
    func grantedPurchaseUpdatesLedger() async throws {
        let grant = try Self.grant()
        let purchaseEvent = try Self.purchaseEvent()
        let updatedLedger = try ledger(
            purchased: 6,
            purchaseGrants: [grant],
            events: [purchaseEvent]
        )
        let executor = PurchaseExecutorSpy(
            result: .granted(grant: grant, ledger: updatedLedger)
        )
        let model = makeModel(executePurchase: { productID in
            try await executor.execute(productID)
        })
        await model.loadProducts()

        #expect(model.requestPurchaseConfirmation(productID: Self.threeCoinProductID))
        await model.confirmPurchase()

        #expect(model.purchaseState == .purchased(grant))
        #expect(model.balance.purchasedAvailable == 6)
        #expect(model.purchaseGrants == [grant])
        #expect(model.events == [purchaseEvent])
        #expect(await executor.requests == [Self.threeCoinProductID])
    }

    @Test("Pending, cancellation, and errors never synthesize a balance change")
    func nonGrantedOutcomesPreserveBalance() async throws {
        let initialLedger = try ledger(purchased: 3)
        let pendingExecutor = PurchaseExecutorSpy(result: .pending)
        let pendingModel = makeModel(
            ledger: initialLedger,
            executePurchase: { productID in
                try await pendingExecutor.execute(productID)
            }
        )
        await pendingModel.loadProducts()
        #expect(pendingModel.requestPurchaseConfirmation(productID: Self.oneCoinProductID))
        await pendingModel.confirmPurchase()

        #expect(pendingModel.purchaseState == .pending(Self.oneCoinProductID))
        #expect(pendingModel.pendingProductIdentifiers == [Self.oneCoinProductID])
        #expect(pendingModel.balance == initialLedger.balance)

        let cancelledExecutor = PurchaseExecutorSpy(result: .cancelled)
        let cancelledModel = makeModel(
            ledger: initialLedger,
            executePurchase: { productID in
                try await cancelledExecutor.execute(productID)
            }
        )
        await cancelledModel.loadProducts()
        #expect(cancelledModel.requestPurchaseConfirmation(productID: Self.fiveCoinProductID))
        await cancelledModel.confirmPurchase()

        #expect(cancelledModel.purchaseState == .cancelled)
        #expect(cancelledModel.balance == initialLedger.balance)

        let failingExecutor = PurchaseExecutorSpy(error: CoinStoreError.purchaseFailed)
        let failingModel = makeModel(
            ledger: initialLedger,
            executePurchase: { productID in
                try await failingExecutor.execute(productID)
            }
        )
        await failingModel.loadProducts()
        #expect(failingModel.requestPurchaseConfirmation(productID: Self.threeCoinProductID))
        await failingModel.confirmPurchase()

        #expect(failingModel.purchaseState == .failed(.storePurchaseFailed))
        #expect(failingModel.balance == initialLedger.balance)
    }

    @Test("Pending product identifiers survive model recreation and clear only from ledger refresh")
    func pendingStateSurvivesRefresh() throws {
        let pendingLedger = try ledger(
            pendingProductIdentifiers: [Self.oneCoinProductID]
        )
        let model = makeModel(ledger: pendingLedger)

        #expect(model.hasPendingPurchases)
        #expect(model.pendingProductIdentifiers == [Self.oneCoinProductID])

        model.refreshLedger(try ledger(purchased: 4))

        #expect(!model.hasPendingPurchases)
        #expect(model.pendingProductIdentifiers.isEmpty)
        #expect(model.balance.purchasedAvailable == 4)
    }

    @Test("A duplicate confirmation while purchasing executes exactly once")
    func duplicateConfirmationExecutesOnce() async throws {
        let executor = HeldPurchaseExecutor()
        let model = makeModel(executePurchase: { productID in
            await executor.execute(productID)
        })
        await model.loadProducts()
        #expect(model.requestPurchaseConfirmation(productID: Self.threeCoinProductID))

        let first = Task { await model.confirmPurchase() }
        await executor.waitUntilRequested()
        await model.confirmPurchase()
        #expect(await executor.requestCount == 1)

        await executor.finish(with: .pending)
        await first.value

        #expect(model.purchaseState == .pending(Self.threeCoinProductID))
        #expect(await executor.requestCount == 1)
    }
}

private extension CoinStoreModelTests {
    static let oneCoinProductID = "com.dxyn02.GetUp.coin.1"
    static let threeCoinProductID = "com.dxyn02.GetUp.coin.3"
    static let fiveCoinProductID = "com.dxyn02.GetUp.coin.5"
    static let unavailableProductID = "com.dxyn02.GetUp.coin.unavailable"
    static let now = Date(timeIntervalSince1970: 1_788_192_000)
    static let epochID = UUID(uuidString: "00000000-0000-4000-8000-000000000A01")!

    static var catalogResult: CoinProductCatalogLoadResult {
        CoinProductCatalogLoadResult(
            availableProducts: [
                product(Self.fiveCoinProductID, quantity: 5, price: "₩4,400"),
                product(Self.oneCoinProductID, quantity: 1, price: "₩1,100"),
                product(Self.threeCoinProductID, quantity: 3, price: "₩2,900"),
            ],
            unavailableProductIdentifiers: [Self.unavailableProductID]
        )
    }

    static func product(
        _ id: String,
        quantity: Int,
        price: String
    ) -> CoinCatalogProduct {
        CoinCatalogProduct(
            product: CoinStoreProduct(
                id: id,
                displayName: "\(quantity) Coins",
                displayDescription: "\(quantity) GetUp coins",
                displayPrice: price
            ),
            quantity: quantity
        )
    }

    func makeModel(
        ledger: CoinStoreLedgerState? = nil,
        loadProducts: CoinStoreModel.LoadProducts? = nil,
        executePurchase: CoinStoreModel.ExecutePurchase? = nil
    ) -> CoinStoreModel {
        let defaultCatalogResult = Self.catalogResult
        return CoinStoreModel(
            ledger: ledger ?? (try! self.ledger()),
            loadProducts: loadProducts ?? { defaultCatalogResult },
            executePurchase: executePurchase ?? { _ in .pending }
        )
    }

    func ledger(
        syncState: CoinBalanceSyncState = .current,
        purchased: Int = 3,
        free: Int = 1,
        purchaseGrants: [PurchaseGrant] = [],
        events: [CoinLedgerEvent] = [],
        pendingProductIdentifiers: Set<String> = [],
        hasPendingReconciliation: Bool = false
    ) throws -> CoinStoreLedgerState {
        CoinStoreLedgerState(
            balance: try CoinBalanceSnapshot(
                purchasedAvailable: purchased,
                currentMonthID: "2026-09",
                freeAvailable: free,
                syncState: syncState,
                syncedAt: Self.now,
                ledgerEpochID: syncState == .current ? Self.epochID : nil,
                hadConfirmedLedger: syncState == .current
            ),
            purchaseGrants: purchaseGrants,
            events: events,
            pendingProductIdentifiers: pendingProductIdentifiers,
            hasPendingReconciliation: hasPendingReconciliation
        )
    }

    static func grant() throws -> PurchaseGrant {
        try PurchaseGrant(
            transactionID: 10_003,
            environment: .sandbox,
            productID: Self.threeCoinProductID,
            quantity: 3,
            purchaseDate: Self.now,
            adjustedQuantity: 0
        )
    }

    static func purchaseEvent() throws -> CoinLedgerEvent {
        try CoinLedgerEvent(
            eventID: CoinLedgerDeterministicID.purchase(
                environment: .sandbox,
                transactionID: 10_003
            ),
            kind: .purchaseGrant,
            source: .purchased,
            quantity: 3,
            relatedTransactionID: 10_003,
            relatedCommandID: nil,
            occurrenceID: nil,
            createdAt: Self.now
        )
    }
}

private actor ProductLoaderSpy {
    private var results: [Result<CoinProductCatalogLoadResult, CoinStoreError>]
    private(set) var requestCount = 0

    init(results: [Result<CoinProductCatalogLoadResult, CoinStoreError>]) {
        self.results = results
    }

    func load() throws -> CoinProductCatalogLoadResult {
        requestCount += 1
        guard !results.isEmpty else {
            throw CoinStoreError.productUnavailable
        }
        return try results.removeFirst().get()
    }
}

private actor PurchaseExecutorSpy {
    private let result: CoinStorePurchaseExecutionResult?
    private let error: CoinStoreError?
    private(set) var requests: [String] = []

    init(result: CoinStorePurchaseExecutionResult) {
        self.result = result
        self.error = nil
    }

    init(error: CoinStoreError) {
        self.result = nil
        self.error = error
    }

    func execute(_ productID: String) throws -> CoinStorePurchaseExecutionResult {
        requests.append(productID)
        if let error { throw error }
        return result!
    }
}

private actor HeldPurchaseExecutor {
    private var continuation: CheckedContinuation<CoinStorePurchaseExecutionResult, Never>?
    private(set) var requestCount = 0

    func execute(_ productID: String) async -> CoinStorePurchaseExecutionResult {
        requestCount += 1
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilRequested() async {
        while requestCount == 0 {
            await Task.yield()
        }
    }

    func finish(with result: CoinStorePurchaseExecutionResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
