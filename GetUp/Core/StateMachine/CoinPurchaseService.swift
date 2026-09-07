import Foundation

enum CoinPurchaseOutcome: Equatable, Sendable {
    case granted(PurchaseGrant)
    case pending
    case cancelled
}

enum CoinPurchaseServiceError: Error, Equatable, Sendable,
    StableLiveActivityCoinError
{
    case ledgerNotCurrent
    case productUnavailable
    case productMismatch
    case revokedTransaction

    var errorCode: LiveActivityCoinErrorCode {
        switch self {
        case .ledgerNotCurrent:
            .ledgerNotCurrent
        case .productUnavailable:
            .storeProductUnavailable
        case .productMismatch, .revokedTransaction:
            .storeTransactionUnverified
        }
    }
}

struct CoinPurchaseService: Sendable {
    typealias FetchLedgerState = @Sendable () async throws -> MonthlyAllowanceLedgerState

    private let catalog: CoinProductCatalog
    private let storefront: any CoinStorefront
    private let repository: any CoinLedgerRepository
    private let fetchLedgerState: FetchLedgerState

    init(
        catalog: CoinProductCatalog,
        storefront: any CoinStorefront,
        repository: any CoinLedgerRepository,
        fetchLedgerState: @escaping FetchLedgerState
    ) {
        self.catalog = catalog
        self.storefront = storefront
        self.repository = repository
        self.fetchLedgerState = fetchLedgerState
    }

    func purchase(productID: String) async throws -> CoinPurchaseOutcome {
        guard catalog.quantity(for: productID) != nil else {
            throw CoinPurchaseServiceError.productUnavailable
        }

        try await requireCurrentLedger()

        switch try await storefront.purchase(productID: productID) {
        case .verified(let transaction):
            guard transaction.productID == productID else {
                throw CoinPurchaseServiceError.productMismatch
            }
            return .granted(try await processVerifiedTransaction(transaction))
        case .unverified:
            throw CoinStoreError.transactionUnverified
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        }
    }

    func processVerifiedTransaction(
        _ transaction: VerifiedCoinTransaction
    ) async throws -> PurchaseGrant {
        try await requireCurrentLedger()

        guard transaction.revocationDate == nil else {
            throw CoinPurchaseServiceError.revokedTransaction
        }
        guard let quantity = catalog.quantity(for: transaction.productID) else {
            throw CoinPurchaseServiceError.productUnavailable
        }

        let grant = try await repository.grantPurchase(
            PurchaseGrantRequest(transaction: transaction, quantity: quantity)
        )

        // The repository's successful return is the CloudKit commit boundary.
        // Leaving finish after it keeps failed or unknown commits retryable.
        try await storefront.finish(transactionID: transaction.id)
        return grant
    }

    private func requireCurrentLedger() async throws {
        guard case .current = try await fetchLedgerState() else {
            throw CoinPurchaseServiceError.ledgerNotCurrent
        }
    }
}
