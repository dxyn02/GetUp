import Foundation

actor StoreKitTransactionObserver {
    typealias ProcessVerifiedTransaction = @Sendable (
        VerifiedCoinTransaction
    ) async throws -> PurchaseGrant

    private let storefront: any CoinStorefront
    private let processVerifiedTransaction: ProcessVerifiedTransaction
    private var updatesTask: Task<Void, Never>?

    init(
        storefront: any CoinStorefront,
        processVerifiedTransaction: @escaping ProcessVerifiedTransaction
    ) {
        self.storefront = storefront
        self.processVerifiedTransaction = processVerifiedTransaction
    }

    func start() async throws {
        if updatesTask == nil {
            // Opening the updates stream first closes the gap in which a transaction
            // could finish between launch and the unfinished transaction query.
            let updates = storefront.transactionUpdates()
            let processVerifiedTransaction = self.processVerifiedTransaction
            updatesTask = Task {
                for await update in updates {
                    guard !Task.isCancelled else {
                        return
                    }
                    // A transient CloudKit failure must leave this transaction
                    // unfinished without terminating observation of later updates.
                    try? await Self.process(
                        update,
                        using: processVerifiedTransaction
                    )
                }
            }
        }

        // This scan intentionally runs on every start call. The lifecycle invokes
        // start again on foreground so transactions left unfinished by a transient
        // failure can recover without recreating the StoreKit updates listener.
        for update in await storefront.unfinishedTransactions() {
            try? await Self.process(
                update,
                using: processVerifiedTransaction
            )
        }
    }

    func waitForUpdatesToFinish() async throws {
        await updatesTask?.value
    }

    private static func process(
        _ update: CoinStoreTransactionUpdate,
        using processVerifiedTransaction: ProcessVerifiedTransaction
    ) async throws {
        guard case .verified(let transaction) = update else {
            return
        }
        _ = try await processVerifiedTransaction(transaction)
    }
}
