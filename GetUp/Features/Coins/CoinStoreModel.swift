import Foundation
import Observation

struct CoinStoreLedgerState: Equatable, Sendable {
    let balance: CoinBalanceSnapshot
    let purchaseGrants: [PurchaseGrant]
    let events: [CoinLedgerEvent]
    let pendingProductIdentifiers: Set<String>
    let hasPendingReconciliation: Bool
}

extension CoinLedgerReconciliationSnapshot {
    var coinStoreLedgerState: CoinStoreLedgerState {
        CoinStoreLedgerState(
            balance: balance,
            purchaseGrants: purchaseGrants,
            events: events,
            pendingProductIdentifiers: pendingProductIdentifiers,
            hasPendingReconciliation: hasPendingReconciliation
        )
    }
}

enum CoinStoreAvailability: Equatable, Sendable {
    case ready
    case setupRequired
    case syncing
    case iCloudRecoveryRequired
    case ledgerResetRequired
    case reconciliationRequired
}

enum CoinStoreMonthlyAllowanceDisplay: Equatable, Sendable {
    case setupRequired(monthID: String, availableAfterSetup: Int)
    case current(monthID: String, available: Int)
    case resetRequired(monthID: String, available: Int)
    case unavailable(monthID: String, lastKnownAvailable: Int)
}

enum CoinStorePurchaseState: Equatable, Sendable {
    case idle
    case confirmationRequested(String)
    case purchasing(String)
    case pending(String)
    case purchased(PurchaseGrant)
    case cancelled
    case failed(LiveActivityCoinErrorCode)
}

enum CoinStorePurchaseExecutionResult: Equatable, Sendable {
    case granted(grant: PurchaseGrant, ledger: CoinStoreLedgerState)
    case pending
    case cancelled
}

@MainActor
@Observable
final class CoinStoreModel {
    typealias LoadProducts = @Sendable () async throws -> CoinProductCatalogLoadResult
    typealias ExecutePurchase = @Sendable (
        _ productID: String
    ) async throws -> CoinStorePurchaseExecutionResult

    @ObservationIgnored private let loadProductsAction: LoadProducts
    @ObservationIgnored private let executePurchase: ExecutePurchase

    private(set) var products: [CoinCatalogProduct] = []
    private(set) var unavailableProductIdentifiers: [String] = []
    private(set) var productLoadError: LiveActivityCoinErrorCode?
    private(set) var isLoadingProducts = false
    private(set) var balance: CoinBalanceSnapshot
    private(set) var purchaseGrants: [PurchaseGrant]
    private(set) var events: [CoinLedgerEvent]
    private(set) var pendingProductIdentifiers: Set<String>
    private(set) var hasPendingReconciliation: Bool
    private(set) var purchaseState: CoinStorePurchaseState

    var availability: CoinStoreAvailability {
        if hasPendingReconciliation {
            return .reconciliationRequired
        }
        switch balance.syncState {
        case .current:
            return .ready
        case .setupRequired:
            return .setupRequired
        case .syncing:
            return .syncing
        case .stale, .unavailable:
            return .iCloudRecoveryRequired
        case .deletionConfirmed, .resetRequired:
            return .ledgerResetRequired
        }
    }

    var monthlyAllowanceDisplay: CoinStoreMonthlyAllowanceDisplay {
        switch balance.syncState {
        case .setupRequired:
            return .setupRequired(
                monthID: balance.currentMonthID,
                availableAfterSetup: MonthlyAllowancePolicy.monthlyQuota
            )
        case .current:
            return .current(
                monthID: balance.currentMonthID,
                available: balance.freeAvailable
            )
        case .deletionConfirmed, .resetRequired:
            return .resetRequired(
                monthID: balance.currentMonthID,
                available: 0
            )
        case .syncing, .stale, .unavailable:
            return .unavailable(
                monthID: balance.currentMonthID,
                lastKnownAvailable: balance.freeAvailable
            )
        }
    }

    var hasPendingPurchases: Bool {
        !pendingProductIdentifiers.isEmpty
    }

    init(
        ledger: CoinStoreLedgerState,
        loadProducts: @escaping LoadProducts,
        executePurchase: @escaping ExecutePurchase
    ) {
        balance = ledger.balance
        purchaseGrants = Self.sortedGrants(ledger.purchaseGrants)
        events = Self.sortedEvents(ledger.events)
        pendingProductIdentifiers = ledger.pendingProductIdentifiers
        hasPendingReconciliation = ledger.hasPendingReconciliation
        purchaseState = ledger.pendingProductIdentifiers.sorted().first.map {
            .pending($0)
        } ?? .idle
        loadProductsAction = loadProducts
        self.executePurchase = executePurchase
    }

    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let result = try await loadProductsAction()
            products = result.availableProducts.sorted(by: Self.productOrder)
            unavailableProductIdentifiers = result.unavailableProductIdentifiers.sorted()
            productLoadError = nil
        } catch {
            products = []
            unavailableProductIdentifiers = []
            productLoadError = Self.errorCode(for: error)
        }
    }

    func isPurchaseEnabled(productID: String) -> Bool {
        guard canBeginPurchase(productID: productID) else { return false }
        switch purchaseState {
        case .confirmationRequested, .purchasing:
            return false
        case .idle, .pending, .purchased, .cancelled, .failed:
            return true
        }
    }

    @discardableResult
    func requestPurchaseConfirmation(productID: String) -> Bool {
        guard isPurchaseEnabled(productID: productID) else { return false }
        purchaseState = .confirmationRequested(productID)
        return true
    }

    func cancelPurchaseConfirmation() {
        guard case .confirmationRequested = purchaseState else { return }
        purchaseState = pendingProductIdentifiers.sorted().first.map {
            .pending($0)
        } ?? .idle
    }

    func confirmPurchase() async {
        guard case .confirmationRequested(let productID) = purchaseState,
              canBeginPurchase(productID: productID)
        else {
            cancelInvalidConfirmationIfNeeded()
            return
        }

        purchaseState = .purchasing(productID)
        do {
            switch try await executePurchase(productID) {
            case .granted(let grant, let ledger):
                apply(ledger)
                purchaseState = .purchased(grant)
            case .pending:
                pendingProductIdentifiers.insert(productID)
                purchaseState = .pending(productID)
            case .cancelled:
                purchaseState = .cancelled
            }
        } catch {
            purchaseState = .failed(Self.errorCode(for: error))
        }
    }

    func refreshLedger(_ ledger: CoinStoreLedgerState) {
        let wasPurchasing: Bool
        if case .purchasing = purchaseState {
            wasPurchasing = true
        } else {
            wasPurchasing = false
        }

        apply(ledger)
        guard !wasPurchasing else { return }

        if availability != .ready {
            purchaseState = .idle
        } else if let pendingProductID = pendingProductIdentifiers.sorted().first {
            purchaseState = .pending(pendingProductID)
        } else if case .pending = purchaseState {
            purchaseState = .idle
        }
    }

    private func canBeginPurchase(productID: String) -> Bool {
        availability == .ready
            && !isLoadingProducts
            && productLoadError == nil
            && products.contains(where: { $0.product.id == productID })
            && !pendingProductIdentifiers.contains(productID)
    }

    private func cancelInvalidConfirmationIfNeeded() {
        guard case .confirmationRequested = purchaseState else { return }
        purchaseState = pendingProductIdentifiers.sorted().first.map {
            .pending($0)
        } ?? .idle
    }

    private func apply(_ ledger: CoinStoreLedgerState) {
        balance = ledger.balance
        purchaseGrants = Self.sortedGrants(ledger.purchaseGrants)
        events = Self.sortedEvents(ledger.events)
        pendingProductIdentifiers = ledger.pendingProductIdentifiers
        hasPendingReconciliation = ledger.hasPendingReconciliation
    }

    private static func productOrder(
        _ lhs: CoinCatalogProduct,
        _ rhs: CoinCatalogProduct
    ) -> Bool {
        lhs.quantity == rhs.quantity
            ? lhs.product.id < rhs.product.id
            : lhs.quantity < rhs.quantity
    }

    private static func sortedGrants(_ grants: [PurchaseGrant]) -> [PurchaseGrant] {
        grants.sorted {
            $0.purchaseDate == $1.purchaseDate
                ? $0.transactionID > $1.transactionID
                : $0.purchaseDate > $1.purchaseDate
        }
    }

    private static func sortedEvents(_ events: [CoinLedgerEvent]) -> [CoinLedgerEvent] {
        events.sorted {
            $0.createdAt == $1.createdAt
                ? $0.eventID < $1.eventID
                : $0.createdAt > $1.createdAt
        }
    }

    private static func errorCode(for error: any Error) -> LiveActivityCoinErrorCode {
        (error as? any StableLiveActivityCoinError)?.errorCode ?? .unknown
    }
}
