import Foundation

struct CoinLedgerSetupRequest: Equatable, Sendable {
    let epochID: UUID
    let monthID: String
    let confirmedAt: Date
    let disclosureVersion: Int
}

enum CoinLedgerInitializationResultError: Error, Equatable, Sendable {
    case invalidInitialState
}

struct CoinLedgerInitializationResult: Equatable, Sendable {
    let epoch: LedgerEpoch
    let account: CoinAccount
    let allowance: MonthlyAllowance

    init(
        epoch: LedgerEpoch,
        account: CoinAccount,
        allowance: MonthlyAllowance
    ) throws {
        guard
            account.purchasedAvailable == 0,
            account.purchasedReserved == 0,
            account.revision == 0,
            allowance.used == 0,
            allowance.reserved == 0,
            Self.matchesInitializationPolicy(epoch: epoch, allowance: allowance)
        else {
            throw CoinLedgerInitializationResultError.invalidInitialState
        }

        self.epoch = epoch
        self.account = account
        self.allowance = allowance
    }

    private static func matchesInitializationPolicy(
        epoch: LedgerEpoch,
        allowance: MonthlyAllowance
    ) -> Bool {
        switch epoch.reason {
        case .initialSetup:
            epoch.suppressedFreeMonthID == nil
                && allowance.quota == MonthlyAllowancePolicy.monthlyQuota
        case .userConfirmedResetAfterDeletion:
            epoch.suppressedFreeMonthID == allowance.monthID
                && allowance.quota == 0
        }
    }
}

enum CoinLedgerSetupServiceError: Error, Equatable, Sendable {
    case setupNotRequired
    case invalidRequest
    case invalidInitializationResult
}

struct CoinLedgerSetupService: Sendable {
    typealias PerformAtomicSetup = @Sendable (
        CoinLedgerSetupRequest
    ) async throws -> CoinLedgerInitializationResult

    private let performAtomicSetup: PerformAtomicSetup

    init(performAtomicSetup: @escaping PerformAtomicSetup) {
        self.performAtomicSetup = performAtomicSetup
    }

    func activate(
        _ request: CoinLedgerSetupRequest,
        ledgerState: CoinBalanceSyncState
    ) async throws -> CoinLedgerInitializationResult {
        guard ledgerState == .setupRequired else {
            throw CoinLedgerSetupServiceError.setupNotRequired
        }
        guard Self.isValid(request) else {
            throw CoinLedgerSetupServiceError.invalidRequest
        }

        let result = try await performAtomicSetup(request)
        guard Self.matches(request: request, result: result) else {
            throw CoinLedgerSetupServiceError.invalidInitializationResult
        }
        return result
    }

    private static func isValid(_ request: CoinLedgerSetupRequest) -> Bool {
        request.confirmedAt.timeIntervalSince1970.isFinite
            && request.disclosureVersion > 0
            && request.monthID == MonthlyAllowancePolicy.monthID(containing: request.confirmedAt)
    }

    private static func matches(
        request: CoinLedgerSetupRequest,
        result: CoinLedgerInitializationResult
    ) -> Bool {
        result.epoch.epochID == request.epochID
            && result.epoch.createdAt == request.confirmedAt
            && result.epoch.reason == .initialSetup
            && result.epoch.suppressedFreeMonthID == nil
            && result.epoch.disclosureVersion == request.disclosureVersion
            && result.account.updatedAt == request.confirmedAt
            && result.allowance.monthID == request.monthID
            && result.allowance.creationDate == request.confirmedAt
            && result.allowance.updatedAt == request.confirmedAt
    }
}
