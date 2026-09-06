import Foundation

struct RuleReleaseRequest: Equatable, Sendable {
    /// Created once per user attempt and preserved through retries and reconciliation.
    let commandID: UUID
    let occurrenceID: String
    let ruleID: UUID
    let ruleRevision: Int
    let endsAt: Date
    let ledgerEpochID: UUID
    let monthID: String
    let requestedFrom: ReleaseRequestSource
    let requestedAt: Date
}

struct RuleReleaseReservationContext: Equatable, Sendable {
    /// The provider must perform a fresh server fetch and the monotonic current gate,
    /// including account, epoch, projection and pending-reconciliation checks.
    let ledgerState: MonthlyAllowanceLedgerState
    let occurrence: RestrictionOccurrence?
    /// Revision read from the current saved rule, not copied from the request.
    let currentRuleRevision: Int
    let hasReleaseException: Bool
    let allowance: MonthlyAllowance?
    let account: CoinAccount
}

enum RuleReleaseServiceError: Error, Equatable, Sendable {
    case invalidRequest
    case occurrenceNotActive
    case occurrenceMismatch
    case ruleRevisionMismatch
    case alreadyReleased
    case monthMismatch
}

struct RuleReleaseService: Sendable {
    typealias FetchCurrentContext = @Sendable (RuleReleaseRequest) async throws -> RuleReleaseReservationContext

    private let repository: any CoinLedgerRepository
    private let monthlyAllowanceService: MonthlyAllowanceService
    private let now: @Sendable () -> Date
    private let fetchCurrentContext: FetchCurrentContext

    init(
        repository: any CoinLedgerRepository,
        now: @escaping @Sendable () -> Date = { Date() },
        fetchCurrentContext: @escaping FetchCurrentContext
    ) {
        self.repository = repository
        self.monthlyAllowanceService = MonthlyAllowanceService(
            repository: repository, reserveMonthlyFree: { try await repository.reserveMonthlyFree($0) }
        )
        self.now = now
        self.fetchCurrentContext = fetchCurrentContext
    }

    func reserve(_ request: RuleReleaseRequest) async throws -> CoinReleaseReservation {
        // Only a definitive free-balance conflict warrants one fresh-context retry.
        // Unknown results must retain this command ID for the separate reconciler.
        for attempt in 0...1 {
            try Task.checkCancellation()
            let context = try await fetchCurrentContext(request)
            try Task.checkCancellation()
            let date = now()
            let epoch = try validate(request, context: context, at: date)
            let allowance = try context.allowance ?? MonthlyAllowancePolicy.makeAllowance(
                monthID: request.monthID, ledgerEpoch: epoch, serverCreationDate: date
            )
            let source = try CoinReservationPolicy.selectFundingSource(
                ledgerState: context.ledgerState, requestedEpochID: request.ledgerEpochID,
                allowance: allowance, account: context.account
            )
            if source == .purchased {
                return try await repository.reservePurchasedCoin(PurchasedCoinReservationRequest(
                    commandID: request.commandID, occurrenceID: request.occurrenceID,
                    ruleID: request.ruleID, ruleRevision: request.ruleRevision,
                    ledgerEpochID: request.ledgerEpochID, requestedFrom: request.requestedFrom,
                    requestedAt: request.requestedAt
                ))
            }
            do {
                // The same combined create+reserve boundary is used for app and Shield;
                // never persist a provisional missing allowance as a separate grant here.
                return try await monthlyAllowanceService.reserveAllowanceForShield(
                    MonthlyFreeReservationRequest(
                        commandID: request.commandID, occurrenceID: request.occurrenceID,
                        ruleID: request.ruleID, ruleRevision: request.ruleRevision,
                        monthID: request.monthID, ledgerEpochID: request.ledgerEpochID,
                        requestedFrom: request.requestedFrom, requestedAt: request.requestedAt
                    ), ledgerState: context.ledgerState
                )
            } catch CoinLedgerRepositoryError.insufficientMonthlyAllowance where attempt == 0 {
                continue
            }
        }
        throw CoinLedgerRepositoryError.insufficientMonthlyAllowance
    }

    private func validate(
        _ request: RuleReleaseRequest, context: RuleReleaseReservationContext, at date: Date
    ) throws -> LedgerEpoch {
        guard case .current(let epoch) = context.ledgerState else {
            throw CoinReservationPolicyError.ledgerNotCurrent
        }
        guard epoch.epochID == request.ledgerEpochID else {
            throw CoinReservationPolicyError.ledgerEpochMismatch
        }
        guard date.timeIntervalSince1970.isFinite, request.requestedAt.timeIntervalSince1970.isFinite,
              request.endsAt.timeIntervalSince1970.isFinite, !request.occurrenceID.isEmpty,
              request.ruleRevision > 0, request.requestedAt <= date else {
            throw RuleReleaseServiceError.invalidRequest
        }
        guard let occurrence = context.occurrence,
              occurrence.startAt <= date, date < occurrence.endAt else {
            throw RuleReleaseServiceError.occurrenceNotActive
        }
        guard occurrence.id == request.occurrenceID, occurrence.ruleID == request.ruleID,
              occurrence.endAt == request.endsAt else {
            throw RuleReleaseServiceError.occurrenceMismatch
        }
        guard occurrence.ruleRevision == request.ruleRevision,
              context.currentRuleRevision == request.ruleRevision else {
            throw RuleReleaseServiceError.ruleRevisionMismatch
        }
        guard !context.hasReleaseException else { throw RuleReleaseServiceError.alreadyReleased }
        guard request.monthID == MonthlyAllowancePolicy.monthID(containing: date),
              request.monthID == MonthlyAllowancePolicy.monthID(containing: request.requestedAt),
              context.allowance == nil || context.allowance?.monthID == request.monthID else {
            throw RuleReleaseServiceError.monthMismatch
        }
        return epoch
    }
}
