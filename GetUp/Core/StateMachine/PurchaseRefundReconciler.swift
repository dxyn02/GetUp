import Foundation

enum PurchaseRefundReconcilerError: Error, Equatable, Sendable {
    case transactionMismatch
    case invalidLedgerState
}

struct PurchaseRefundReconciliation: Equatable, Sendable {
    let updatedGrant: PurchaseGrant
    let updatedAccount: CoinAccount
    let event: CoinLedgerEvent?
}

enum PurchaseRefundReconciler {
    static func reconcile(
        transaction: VerifiedCoinTransaction,
        grant: PurchaseGrant,
        account: CoinAccount,
        existingEvents: [CoinLedgerEvent],
        processedAt: Date
    ) throws -> PurchaseRefundReconciliation {
        guard
            transaction.id == grant.transactionID,
            transaction.environment == grant.environment,
            transaction.productID == grant.productID,
            transaction.purchaseDate == grant.purchaseDate
        else {
            throw PurchaseRefundReconcilerError.transactionMismatch
        }

        if let revocationDate = transaction.revocationDate {
            return try reconcileRevocation(
                transaction: transaction,
                revocationDate: revocationDate,
                grant: grant,
                account: account,
                existingEvents: existingEvents,
                processedAt: processedAt
            )
        }

        return try reconcileRefundCancellation(
            transaction: transaction,
            grant: grant,
            account: account,
            existingEvents: existingEvents,
            processedAt: processedAt
        )
    }

    private static func reconcileRevocation(
        transaction: VerifiedCoinTransaction,
        revocationDate: Date,
        grant: PurchaseGrant,
        account: CoinAccount,
        existingEvents: [CoinLedgerEvent],
        processedAt: Date
    ) throws -> PurchaseRefundReconciliation {
        let eventID = CoinLedgerDeterministicID.refund(
            transactionID: transaction.id,
            revocationDate: revocationDate
        )
        guard !existingEvents.contains(where: { $0.eventID == eventID }) else {
            return unchanged(grant: grant, account: account)
        }

        let adjustment = min(grant.remainingQuantity, account.purchasedUsable)
        guard adjustment > 0 else {
            return unchanged(grant: grant, account: account)
        }

        let updatedGrant = try PurchaseGrant(
            schemaVersion: grant.schemaVersion,
            transactionID: grant.transactionID,
            environment: grant.environment,
            productID: grant.productID,
            quantity: grant.quantity,
            purchaseDate: grant.purchaseDate,
            adjustedQuantity: try adding(grant.adjustedQuantity, adjustment)
        )
        let updatedAccount = try CoinAccount(
            schemaVersion: account.schemaVersion,
            purchasedAvailable: account.purchasedAvailable - adjustment,
            purchasedReserved: account.purchasedReserved,
            revision: try adding(account.revision, 1),
            updatedAt: processedAt
        )
        let event = try CoinLedgerEvent(
            eventID: eventID,
            kind: .refundAdjustment,
            source: .purchased,
            quantity: adjustment,
            relatedTransactionID: transaction.id,
            relatedCommandID: nil,
            occurrenceID: nil,
            createdAt: processedAt
        )

        return PurchaseRefundReconciliation(
            updatedGrant: updatedGrant,
            updatedAccount: updatedAccount,
            event: event
        )
    }

    private static func reconcileRefundCancellation(
        transaction: VerifiedCoinTransaction,
        grant: PurchaseGrant,
        account: CoinAccount,
        existingEvents: [CoinLedgerEvent],
        processedAt: Date
    ) throws -> PurchaseRefundReconciliation {
        let refunds = existingEvents.filter {
            $0.kind == .refundAdjustment
                && $0.source == .purchased
                && $0.relatedTransactionID == transaction.id
        }
        let unreversedRefunds = refunds.filter { refund in
            !existingEvents.contains(where: {
                $0.eventID == reversalEventID(for: refund.eventID)
            })
        }

        guard !unreversedRefunds.isEmpty else {
            return unchanged(grant: grant, account: account)
        }
        guard unreversedRefunds.count == 1, let refund = unreversedRefunds.first,
              refund.quantity <= grant.adjustedQuantity else {
            throw PurchaseRefundReconcilerError.invalidLedgerState
        }

        let updatedGrant = try PurchaseGrant(
            schemaVersion: grant.schemaVersion,
            transactionID: grant.transactionID,
            environment: grant.environment,
            productID: grant.productID,
            quantity: grant.quantity,
            purchaseDate: grant.purchaseDate,
            adjustedQuantity: grant.adjustedQuantity - refund.quantity
        )
        let updatedAccount = try CoinAccount(
            schemaVersion: account.schemaVersion,
            purchasedAvailable: try adding(account.purchasedAvailable, refund.quantity),
            purchasedReserved: account.purchasedReserved,
            revision: try adding(account.revision, 1),
            updatedAt: processedAt
        )
        let event = try CoinLedgerEvent(
            eventID: reversalEventID(for: refund.eventID),
            kind: .reversal,
            source: .purchased,
            quantity: refund.quantity,
            relatedTransactionID: transaction.id,
            relatedCommandID: nil,
            occurrenceID: nil,
            createdAt: processedAt
        )

        return PurchaseRefundReconciliation(
            updatedGrant: updatedGrant,
            updatedAccount: updatedAccount,
            event: event
        )
    }

    private static func unchanged(
        grant: PurchaseGrant,
        account: CoinAccount
    ) -> PurchaseRefundReconciliation {
        PurchaseRefundReconciliation(
            updatedGrant: grant,
            updatedAccount: account,
            event: nil
        )
    }

    private static func reversalEventID(for refundEventID: String) -> String {
        "reversal:\(refundEventID)"
    }

    private static func adding(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else {
            throw PurchaseRefundReconcilerError.invalidLedgerState
        }
        return result
    }
}
