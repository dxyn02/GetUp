import Foundation

enum MonthlyAllowanceLedgerState: Equatable, Sendable {
    case setupRequired
    case current(epoch: LedgerEpoch)
    case syncing
    case stale
    case unavailable
    case deletionConfirmed
    case resetRequired
}

enum MonthlyAllowanceServiceError: Error, Equatable, Sendable {
    case ledgerNotCurrent
    case ledgerEpochMismatch
    case reservationRepositoryUnavailable
}

struct MonthlyAllowanceForegroundContext: Equatable, Sendable {
    let monthID: String
    let ledgerState: MonthlyAllowanceLedgerState
    let existingAllowance: MonthlyAllowance?
}

struct MonthlyAllowanceService: Sendable {
    typealias ReserveMonthlyFree = @Sendable (
        MonthlyFreeReservationRequest
    ) async throws -> CoinReleaseReservation

    private let repository: any MonthlyAllowanceRepository
    private let reserveMonthlyFree: ReserveMonthlyFree

    init(
        repository: any MonthlyAllowanceRepository,
        reserveMonthlyFree: @escaping ReserveMonthlyFree = { _ in
            throw MonthlyAllowanceServiceError.reservationRepositoryUnavailable
        }
    ) {
        self.repository = repository
        self.reserveMonthlyFree = reserveMonthlyFree
    }

    func ensureAllowanceForAppForeground(
        monthID: String,
        ledgerState: MonthlyAllowanceLedgerState,
        existingAllowance: MonthlyAllowance?
    ) async throws -> MonthlyAllowance {
        guard case .current(let epoch) = ledgerState else {
            throw MonthlyAllowanceServiceError.ledgerNotCurrent
        }
        if let existingAllowance, existingAllowance.monthID == monthID {
            return existingAllowance
        }

        return try await repository.createAllowanceIfNeeded(
            MonthlyAllowanceCreationRequest(
                monthID: monthID,
                epochID: epoch.epochID,
                trigger: .appForeground
            )
        )
    }

    func reserveAllowanceForShield(
        _ request: MonthlyFreeReservationRequest,
        ledgerState: MonthlyAllowanceLedgerState
    ) async throws -> CoinReleaseReservation {
        guard case .current(let epoch) = ledgerState else {
            throw MonthlyAllowanceServiceError.ledgerNotCurrent
        }
        guard epoch.epochID == request.ledgerEpochID else {
            throw MonthlyAllowanceServiceError.ledgerEpochMismatch
        }

        // The repository owns the single atomic CloudKit operation that creates a
        // missing allowance and reserves one use together. A separate lazy-create
        // call here would expose a partially confirmed free grant to Shield.
        return try await reserveMonthlyFree(request)
    }
}
