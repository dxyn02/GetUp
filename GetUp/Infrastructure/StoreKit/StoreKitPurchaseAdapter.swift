import Foundation
import StoreKit

actor StoreKitPurchaseAdapter: CoinStorefront {
    private var productsByIdentifier: [String: Product] = [:]
    private var verifiedTransactionsByID: [UInt64: Transaction] = [:]

    func products(for identifiers: Set<String>) async throws -> [CoinStoreProduct] {
        productsByIdentifier.removeAll(keepingCapacity: true)

        let products: [Product]
        do {
            products = try await Product.products(for: identifiers)
        } catch {
            throw CoinStoreError.productUnavailable
        }

        let approvedProducts = products.filter {
            identifiers.contains($0.id) && $0.type == .consumable
        }
        productsByIdentifier = Dictionary(
            approvedProducts.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return approvedProducts.map(Self.makeStoreProduct)
    }

    func purchase(productID: String) async throws -> CoinStorePurchaseResult {
        guard let product = productsByIdentifier[productID] else {
            throw CoinStoreError.productUnavailable
        }

        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch {
            throw CoinStoreError.purchaseFailed
        }

        switch result {
        case .success(let verificationResult):
            switch verificationResult {
            case .verified(let transaction):
                guard let verifiedTransaction = Self.makeVerifiedTransaction(transaction) else {
                    return .unverified
                }
                verifiedTransactionsByID[transaction.id] = transaction
                return .verified(verifiedTransaction)

            case .unverified:
                return .unverified
            }

        case .pending:
            return .pending

        case .userCancelled:
            return .userCancelled

        @unknown default:
            throw CoinStoreError.purchaseFailed
        }
    }

    func unfinishedTransactions() async -> [CoinStoreTransactionUpdate] {
        var updates: [CoinStoreTransactionUpdate] = []

        for await result in Transaction.unfinished {
            switch result {
            case .verified(let transaction):
                guard let verifiedTransaction = Self.makeVerifiedTransaction(transaction) else {
                    updates.append(.unverified)
                    continue
                }
                verifiedTransactionsByID[transaction.id] = transaction
                updates.append(.verified(verifiedTransaction))

            case .unverified:
                updates.append(.unverified)
            }
        }

        return updates
    }

    nonisolated func transactionUpdates() -> AsyncStream<CoinStoreTransactionUpdate> {
        AsyncStream { continuation in
            let observation = Task {
                for await result in Transaction.updates {
                    guard !Task.isCancelled else {
                        break
                    }

                    switch result {
                    case .verified(let transaction):
                        guard let verifiedTransaction = Self.makeVerifiedTransaction(transaction) else {
                            continuation.yield(.unverified)
                            continue
                        }
                        await cache(transaction)
                        continuation.yield(.verified(verifiedTransaction))

                    case .unverified:
                        continuation.yield(.unverified)
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                observation.cancel()
            }
        }
    }

    func finish(transactionID: UInt64) async throws {
        if let transaction = verifiedTransactionsByID.removeValue(forKey: transactionID) {
            await transaction.finish()
            return
        }

        for await result in Transaction.unfinished {
            guard case .verified(let transaction) = result, transaction.id == transactionID else {
                continue
            }
            guard Self.makeVerifiedTransaction(transaction) != nil else {
                throw CoinStoreError.finishFailed
            }
            await transaction.finish()
            return
        }

        throw CoinStoreError.finishFailed
    }

    private func cache(_ transaction: Transaction) {
        verifiedTransactionsByID[transaction.id] = transaction
    }

    nonisolated private static func makeStoreProduct(_ product: Product) -> CoinStoreProduct {
        CoinStoreProduct(
            id: product.id,
            displayName: product.displayName,
            displayDescription: product.description,
            displayPrice: product.displayPrice
        )
    }

    nonisolated private static func makeVerifiedTransaction(
        _ transaction: Transaction
    ) -> VerifiedCoinTransaction? {
        let environment: PurchaseEnvironment
        switch transaction.environment {
        case .production:
            environment = .production
        case .sandbox, .xcode:
            environment = .sandbox
        default:
            return nil
        }

        return VerifiedCoinTransaction(
            id: transaction.id,
            environment: environment,
            productID: transaction.productID,
            purchaseDate: transaction.purchaseDate,
            revocationDate: transaction.revocationDate
        )
    }
}
