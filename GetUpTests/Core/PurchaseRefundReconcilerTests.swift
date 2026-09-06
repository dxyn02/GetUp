import Foundation
import Testing
@testable import GetUp

@Suite("Purchase refund reconciler")
struct PurchaseRefundReconcilerTests {
    @Test("A verified revocation removes all unused coins and records one adjustment")
    func revokedPurchaseRemovesUnusedCoins() throws {
        let transaction = Self.transaction(revocationDate: Self.revocationDate)
        let grant = try Self.grant(quantity: 5)
        let account = try Self.account(available: 5, revision: 7)

        let result = try PurchaseRefundReconciler.reconcile(
            transaction: transaction,
            grant: grant,
            account: account,
            existingEvents: [],
            processedAt: Self.processedAt
        )

        #expect(result.updatedGrant.adjustedQuantity == 5)
        #expect(result.updatedGrant.remainingQuantity == 0)
        #expect(result.updatedAccount.purchasedAvailable == 0)
        #expect(result.updatedAccount.purchasedReserved == 0)
        #expect(result.updatedAccount.revision == 8)
        #expect(result.updatedAccount.updatedAt == Self.processedAt)
        #expect(result.event?.eventID == CoinLedgerDeterministicID.refund(
            transactionID: transaction.id,
            revocationDate: Self.revocationDate
        ))
        #expect(result.event?.kind == .refundAdjustment)
        #expect(result.event?.source == .purchased)
        #expect(result.event?.quantity == 5)
        #expect(result.event?.relatedTransactionID == transaction.id)
        #expect(result.event?.createdAt == Self.processedAt)
    }

    @Test("Refund adjustment is limited to the currently unused purchased balance")
    func partiallyUsedPurchaseAdjustsOnlyUnusedCoins() throws {
        let transaction = Self.transaction(revocationDate: Self.revocationDate)
        let grant = try Self.grant(quantity: 5)
        let account = try Self.account(available: 2, revision: 3)

        let result = try PurchaseRefundReconciler.reconcile(
            transaction: transaction,
            grant: grant,
            account: account,
            existingEvents: [],
            processedAt: Self.processedAt
        )

        #expect(result.updatedGrant.adjustedQuantity == 2)
        #expect(result.updatedGrant.remainingQuantity == 3)
        #expect(result.updatedAccount.purchasedAvailable == 0)
        #expect(result.updatedAccount.revision == 4)
        #expect(result.event?.quantity == 2)
    }

    @Test("Reserved or already spent coins are preserved and the account clamps at zero")
    func reservedBalanceIsNeverReclaimed() throws {
        let transaction = Self.transaction(revocationDate: Self.revocationDate)
        let grant = try Self.grant(quantity: 5)
        let account = try Self.account(available: 2, reserved: 2, revision: 9)

        let result = try PurchaseRefundReconciler.reconcile(
            transaction: transaction,
            grant: grant,
            account: account,
            existingEvents: [],
            processedAt: Self.processedAt
        )

        #expect(result.updatedGrant == grant)
        #expect(result.updatedAccount == account)
        #expect(result.updatedAccount.purchasedUsable == 0)
        #expect(result.event == nil)
    }

    @Test("The same refund event is idempotent")
    func duplicateRefundDoesNotAdjustTwice() throws {
        let transaction = Self.transaction(revocationDate: Self.revocationDate)
        let first = try PurchaseRefundReconciler.reconcile(
            transaction: transaction,
            grant: Self.grant(quantity: 5),
            account: Self.account(available: 2),
            existingEvents: [],
            processedAt: Self.processedAt
        )
        let adjustment = try #require(first.event)

        let duplicate = try PurchaseRefundReconciler.reconcile(
            transaction: transaction,
            grant: first.updatedGrant,
            account: first.updatedAccount,
            existingEvents: [adjustment],
            processedAt: Self.processedAt.addingTimeInterval(60)
        )

        #expect(duplicate.updatedGrant == first.updatedGrant)
        #expect(duplicate.updatedAccount == first.updatedAccount)
        #expect(duplicate.event == nil)
    }

    @Test("A refund cancellation restores exactly the prior adjustment")
    func refundCancellationCreatesReversal() throws {
        let refund = try Self.refundEvent(quantity: 2)
        let grant = try Self.grant(quantity: 5, adjusted: 2)
        let account = try Self.account(available: 4, revision: 11)

        let result = try PurchaseRefundReconciler.reconcile(
            transaction: Self.transaction(revocationDate: nil),
            grant: grant,
            account: account,
            existingEvents: [refund],
            processedAt: Self.processedAt
        )

        #expect(result.updatedGrant.adjustedQuantity == 0)
        #expect(result.updatedGrant.remainingQuantity == 5)
        #expect(result.updatedAccount.purchasedAvailable == 6)
        #expect(result.updatedAccount.purchasedReserved == 0)
        #expect(result.updatedAccount.revision == 12)
        #expect(result.event?.kind == .reversal)
        #expect(result.event?.source == .purchased)
        #expect(result.event?.quantity == 2)
        #expect(result.event?.relatedTransactionID == Self.transactionID)
        #expect(result.event?.eventID != refund.eventID)
    }

    @Test("The same refund cancellation creates at most one reversal")
    func duplicateRefundCancellationIsIdempotent() throws {
        let refund = try Self.refundEvent(quantity: 2)
        let first = try PurchaseRefundReconciler.reconcile(
            transaction: Self.transaction(revocationDate: nil),
            grant: Self.grant(quantity: 5, adjusted: 2),
            account: Self.account(available: 0),
            existingEvents: [refund],
            processedAt: Self.processedAt
        )
        let reversal = try #require(first.event)

        let duplicate = try PurchaseRefundReconciler.reconcile(
            transaction: Self.transaction(revocationDate: nil),
            grant: first.updatedGrant,
            account: first.updatedAccount,
            existingEvents: [refund, reversal],
            processedAt: Self.processedAt.addingTimeInterval(60)
        )

        #expect(duplicate.updatedGrant == first.updatedGrant)
        #expect(duplicate.updatedAccount == first.updatedAccount)
        #expect(duplicate.event == nil)
    }

    @Test("A transaction cannot adjust a different purchase grant")
    func mismatchedTransactionIsRejected() throws {
        let transaction = VerifiedCoinTransaction(
            id: Self.transactionID + 1,
            environment: .sandbox,
            productID: Self.productID,
            purchaseDate: Self.purchaseDate,
            revocationDate: Self.revocationDate
        )

        #expect(throws: PurchaseRefundReconcilerError.transactionMismatch) {
            try PurchaseRefundReconciler.reconcile(
                transaction: transaction,
                grant: Self.grant(quantity: 5),
                account: Self.account(available: 5),
                existingEvents: [],
                processedAt: Self.processedAt
            )
        }
    }

    @Test("A current transaction without a prior refund is unchanged")
    func currentTransactionWithoutRefundIsNoOp() throws {
        let grant = try Self.grant(quantity: 3)
        let account = try Self.account(available: 3, revision: 2)

        let result = try PurchaseRefundReconciler.reconcile(
            transaction: Self.transaction(revocationDate: nil),
            grant: grant,
            account: account,
            existingEvents: [],
            processedAt: Self.processedAt
        )

        #expect(result.updatedGrant == grant)
        #expect(result.updatedAccount == account)
        #expect(result.event == nil)
    }
}

private extension PurchaseRefundReconcilerTests {
    static let transactionID: UInt64 = 501
    static let productID = "com.dxyn02.GetUp.coin.5"
    static let purchaseDate = Date(timeIntervalSince1970: 1_788_192_000)
    static let revocationDate = purchaseDate.addingTimeInterval(86_400)
    static let processedAt = revocationDate.addingTimeInterval(60)

    static func transaction(revocationDate: Date?) -> VerifiedCoinTransaction {
        VerifiedCoinTransaction(
            id: transactionID,
            environment: .sandbox,
            productID: productID,
            purchaseDate: purchaseDate,
            revocationDate: revocationDate
        )
    }

    static func grant(
        quantity: Int,
        adjusted: Int = 0
    ) throws -> PurchaseGrant {
        try PurchaseGrant(
            transactionID: transactionID,
            environment: .sandbox,
            productID: productID,
            quantity: quantity,
            purchaseDate: purchaseDate,
            adjustedQuantity: adjusted
        )
    }

    static func account(
        available: Int,
        reserved: Int = 0,
        revision: Int = 0
    ) throws -> CoinAccount {
        try CoinAccount(
            purchasedAvailable: available,
            purchasedReserved: reserved,
            revision: revision,
            updatedAt: purchaseDate
        )
    }

    static func refundEvent(quantity: Int) throws -> CoinLedgerEvent {
        try CoinLedgerEvent(
            eventID: CoinLedgerDeterministicID.refund(
                transactionID: transactionID,
                revocationDate: revocationDate
            ),
            kind: .refundAdjustment,
            source: .purchased,
            quantity: quantity,
            relatedTransactionID: transactionID,
            relatedCommandID: nil,
            occurrenceID: nil,
            createdAt: processedAt.addingTimeInterval(-60)
        )
    }
}
