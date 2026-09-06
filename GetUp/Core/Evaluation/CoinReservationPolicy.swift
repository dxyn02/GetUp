import Foundation

enum CoinReservationPolicyError: Error, Equatable, Sendable {
    case ledgerNotCurrent
    case ledgerEpochMismatch
    case insufficientBalance
}

enum CoinReservationPolicy {
    /// The caller supplies freshly validated ledger state and the current month's allowance.
    /// Selection does not reserve funds; the repository must enforce it atomically.
    static func selectFundingSource(
        ledgerState: MonthlyAllowanceLedgerState,
        requestedEpochID: UUID,
        allowance: MonthlyAllowance,
        account: CoinAccount
    ) throws -> ReleaseFundingSource {
        guard case .current(let epoch) = ledgerState else {
            throw CoinReservationPolicyError.ledgerNotCurrent
        }
        guard epoch.epochID == requestedEpochID else {
            throw CoinReservationPolicyError.ledgerEpochMismatch
        }
        if allowance.available > 0 {
            return .monthlyFree
        }
        if account.purchasedUsable > 0 {
            return .purchased
        }
        throw CoinReservationPolicyError.insufficientBalance
    }
}
