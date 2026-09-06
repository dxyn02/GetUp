import Foundation
import Testing
@testable import GetUp

@Suite("Coin purchase service")
struct CoinPurchaseServiceTests {
    @Test("Verified purchases grant the exact catalog quantity and finish the transaction")
    func verifiedPurchasesGrantCatalogQuantities() async throws {
        let transactions = [
            Self.transaction(id: 101, productID: Self.oneCoinProductID),
            Self.transaction(id: 103, productID: Self.threeCoinProductID),
            Self.transaction(id: 105, productID: Self.fiveCoinProductID),
        ]
        let storefront = CoinStorefrontFake(
            purchases: transactions.map { .success(.verified($0)) },
            finishes: Array(repeating: .success(()), count: transactions.count)
        )
        let ledger = IdempotentPurchaseLedgerFake()
        let service = try Self.service(storefront: storefront, ledger: ledger)

        let outcomes = [
            try await service.purchase(productID: Self.oneCoinProductID),
            try await service.purchase(productID: Self.threeCoinProductID),
            try await service.purchase(productID: Self.fiveCoinProductID),
        ]

        #expect(outcomes == [
            .granted(try Self.grant(transaction: transactions[0], quantity: 1)),
            .granted(try Self.grant(transaction: transactions[1], quantity: 3)),
            .granted(try Self.grant(transaction: transactions[2], quantity: 5)),
        ])
        #expect(await ledger.grantRequests.map(\.quantity) == [1, 3, 5])
        #expect(await storefront.finishRequests == [101, 103, 105])
    }

    @Test("Unverified purchases never grant or finish")
    func unverifiedPurchaseIsRejected() async throws {
        let storefront = CoinStorefrontFake(purchases: [.success(.unverified)])
        let ledger = IdempotentPurchaseLedgerFake()
        let service = try Self.service(storefront: storefront, ledger: ledger)

        await #expect(throws: CoinStoreError.transactionUnverified) {
            try await service.purchase(productID: Self.oneCoinProductID)
        }

        #expect(await ledger.grantRequests.isEmpty)
        #expect(await storefront.finishRequests.isEmpty)
    }

    @Test("Pending purchases expose pending state without granting or finishing")
    func pendingPurchaseWaitsForTransactionUpdate() async throws {
        let storefront = CoinStorefrontFake(purchases: [.success(.pending)])
        let ledger = IdempotentPurchaseLedgerFake()
        let service = try Self.service(storefront: storefront, ledger: ledger)

        let outcome = try await service.purchase(productID: Self.threeCoinProductID)

        #expect(outcome == .pending)
        #expect(await ledger.grantRequests.isEmpty)
        #expect(await storefront.finishRequests.isEmpty)
    }

    @Test("Cancelled purchases return to the store without changing the ledger")
    func cancelledPurchasePreservesBalance() async throws {
        let storefront = CoinStorefrontFake(purchases: [.success(.userCancelled)])
        let ledger = IdempotentPurchaseLedgerFake()
        let service = try Self.service(storefront: storefront, ledger: ledger)

        let outcome = try await service.purchase(productID: Self.fiveCoinProductID)

        #expect(outcome == .cancelled)
        #expect(await ledger.grantRequests.isEmpty)
        #expect(await storefront.finishRequests.isEmpty)
    }

    @Test("StoreKit errors preserve the ledger and remain retryable")
    func storeKitErrorPreservesBalance() async throws {
        let storefront = CoinStorefrontFake(purchases: [.failure(.purchaseFailed)])
        let ledger = IdempotentPurchaseLedgerFake()
        let service = try Self.service(storefront: storefront, ledger: ledger)

        await #expect(throws: CoinStoreError.purchaseFailed) {
            try await service.purchase(productID: Self.oneCoinProductID)
        }

        #expect(await ledger.grantRequests.isEmpty)
        #expect(await storefront.finishRequests.isEmpty)
    }

    @Test("A verified transaction must match the product the user selected")
    func mismatchedVerifiedProductIsRejected() async throws {
        let transaction = Self.transaction(id: 201, productID: Self.fiveCoinProductID)
        let storefront = CoinStorefrontFake(purchases: [.success(.verified(transaction))])
        let ledger = IdempotentPurchaseLedgerFake()
        let service = try Self.service(storefront: storefront, ledger: ledger)

        await #expect(throws: CoinPurchaseServiceError.productMismatch) {
            try await service.purchase(productID: Self.oneCoinProductID)
        }

        #expect(await ledger.grantRequests.isEmpty)
        #expect(await storefront.finishRequests.isEmpty)
    }

    @Test("The same verified transaction delivered 100 times creates one grant")
    func duplicateVerifiedTransactionIsIdempotent() async throws {
        let transaction = Self.transaction(id: 301, productID: Self.threeCoinProductID)
        let storefront = CoinStorefrontFake(
            finishes: Array(repeating: .success(()), count: 100)
        )
        let ledger = IdempotentPurchaseLedgerFake()
        let service = try Self.service(storefront: storefront, ledger: ledger)

        let grants = try await withThrowingTaskGroup(of: PurchaseGrant.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    try await service.processVerifiedTransaction(transaction)
                }
            }

            var results: [PurchaseGrant] = []
            for try await grant in group {
                results.append(grant)
            }
            return results
        }

        #expect(grants.count == 100)
        #expect(Set(grants).count == 1)
        #expect(grants.allSatisfy { $0.quantity == 3 })
        #expect(await ledger.createdGrantCount == 1)
        #expect(await ledger.grantRequests.count == 100)
        #expect(await storefront.finishRequests.count == 100)
    }
}

private extension CoinPurchaseServiceTests {
    static let oneCoinProductID = "com.dxyn02.GetUp.coin.1"
    static let threeCoinProductID = "com.dxyn02.GetUp.coin.3"
    static let fiveCoinProductID = "com.dxyn02.GetUp.coin.5"
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

    static var ledgerEpoch: LedgerEpoch {
        LedgerEpoch(
            epochID: UUID(uuidString: "00000000-0000-4000-8000-000000000701")!,
            createdAt: purchaseDate,
            reason: .initialSetup,
            suppressedFreeMonthID: nil,
            disclosureVersion: 1
        )
    }

    static var catalogInfoDictionary: [String: Any] {
        [
            SharedIdentifiers.coinProductCatalogInfoDictionaryKey: [
                entry(productID: oneCoinProductID, quantity: 1),
                entry(productID: threeCoinProductID, quantity: 3),
                entry(productID: fiveCoinProductID, quantity: 5),
            ],
        ]
    }

    static func entry(productID: String, quantity: Int) -> [String: Any] {
        [
            SharedIdentifiers.coinProductIdentifierCatalogKey: productID,
            SharedIdentifiers.coinProductQuantityCatalogKey: quantity,
        ]
    }

    static func transaction(id: UInt64, productID: String) -> VerifiedCoinTransaction {
        VerifiedCoinTransaction(
            id: id,
            environment: .sandbox,
            productID: productID,
            purchaseDate: purchaseDate,
            revocationDate: nil
        )
    }

    static func grant(
        transaction: VerifiedCoinTransaction,
        quantity: Int
    ) throws -> PurchaseGrant {
        try PurchaseGrant(
            transactionID: transaction.id,
            environment: transaction.environment,
            productID: transaction.productID,
            quantity: quantity,
            purchaseDate: transaction.purchaseDate,
            adjustedQuantity: 0
        )
    }
}

private actor IdempotentPurchaseLedgerFake: CoinLedgerRepository {
    private var grantsByKey: [String: PurchaseGrant] = [:]
    private(set) var grantRequests: [PurchaseGrantRequest] = []
    private(set) var createdGrantCount = 0

    func grantPurchase(_ request: PurchaseGrantRequest) async throws -> PurchaseGrant {
        grantRequests.append(request)
        let key = "\(request.transaction.environment.rawValue):\(request.transaction.id)"
        if let existing = grantsByKey[key] {
            guard
                existing.productID == request.transaction.productID,
                existing.quantity == request.quantity
            else {
                throw CoinLedgerRepositoryError.database(.invalidRecord)
            }
            return existing
        }

        let grant = try PurchaseGrant(
            transactionID: request.transaction.id,
            environment: request.transaction.environment,
            productID: request.transaction.productID,
            quantity: request.quantity,
            purchaseDate: request.transaction.purchaseDate,
            adjustedQuantity: 0
        )
        grantsByKey[key] = grant
        createdGrantCount += 1
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
