import Foundation

struct CoinLedgerResetRequest: Equatable, Sendable {
    let epochID: UUID
    let monthID: String
    let confirmedAt: Date
    let disclosureVersion: Int
}

enum CoinLedgerResetServiceError: Error, Equatable, Sendable {
    case deletionNotConfirmed
    case invalidRequest
    case invalidInitializationResult
}

struct CoinLedgerResetService: Sendable {
    typealias PerformAtomicReset = @Sendable (
        CoinLedgerResetRequest
    ) async throws -> CoinLedgerInitializationResult

    private let performAtomicReset: PerformAtomicReset

    init(performAtomicReset: @escaping PerformAtomicReset) {
        self.performAtomicReset = performAtomicReset
    }

    func resetAfterConfirmedDeletion(
        _ request: CoinLedgerResetRequest,
        ledgerState: CoinBalanceSyncState
    ) async throws -> CoinLedgerInitializationResult {
        guard ledgerState == .deletionConfirmed else {
            throw CoinLedgerResetServiceError.deletionNotConfirmed
        }
        guard Self.isValid(request) else {
            throw CoinLedgerResetServiceError.invalidRequest
        }

        let result = try await performAtomicReset(request)
        guard Self.matches(request: request, result: result) else {
            throw CoinLedgerResetServiceError.invalidInitializationResult
        }
        return result
    }

    private static func isValid(_ request: CoinLedgerResetRequest) -> Bool {
        request.confirmedAt.timeIntervalSince1970.isFinite
            && request.disclosureVersion > 0
            && request.monthID == MonthlyAllowancePolicy.monthID(containing: request.confirmedAt)
    }

    private static func matches(
        request: CoinLedgerResetRequest,
        result: CoinLedgerInitializationResult
    ) -> Bool {
        result.epoch.epochID == request.epochID
            && result.epoch.createdAt == request.confirmedAt
            && result.epoch.reason == .userConfirmedResetAfterDeletion
            && result.epoch.suppressedFreeMonthID == request.monthID
            && result.epoch.disclosureVersion == request.disclosureVersion
            && result.account.updatedAt == request.confirmedAt
            && result.allowance.monthID == request.monthID
            && result.allowance.creationDate == request.confirmedAt
            && result.allowance.updatedAt == request.confirmedAt
    }
}
