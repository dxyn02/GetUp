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
    private let transactionProcessor: CoinPurchaseTransactionProcessor

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
        transactionProcessor = CoinPurchaseTransactionProcessor()
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
        try await transactionProcessor.process(transactionID: transaction.id) {
            try await performVerifiedTransaction(transaction)
        }
    }

    private func performVerifiedTransaction(
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

/// Coalesces StoreKit's direct purchase result and `Transaction.updates` delivery.
/// Both paths can receive the same verified transaction at nearly the same time;
/// allowing them to finish independently can turn a successful grant into a
/// user-visible `finishFailed` when one path finishes first.
private actor CoinPurchaseTransactionProcessor {
    private struct InFlight: Sendable {
        let token: UUID
        let task: Task<PurchaseGrant, any Error>
    }

    private var inFlightByTransactionID: [UInt64: InFlight] = [:]
    private var completedByTransactionID: [UInt64: PurchaseGrant] = [:]

    func process(
        transactionID: UInt64,
        operation: @escaping @Sendable () async throws -> PurchaseGrant
    ) async throws -> PurchaseGrant {
        if let completed = completedByTransactionID[transactionID] {
            return completed
        }
        if let existing = inFlightByTransactionID[transactionID] {
            return try await existing.task.value
        }

        let token = UUID()
        let task = Task { try await operation() }
        inFlightByTransactionID[transactionID] = InFlight(token: token, task: task)

        defer {
            if inFlightByTransactionID[transactionID]?.token == token {
                inFlightByTransactionID[transactionID] = nil
            }
        }
        let grant = try await task.value
        completedByTransactionID[transactionID] = grant
        return grant
    }
}
