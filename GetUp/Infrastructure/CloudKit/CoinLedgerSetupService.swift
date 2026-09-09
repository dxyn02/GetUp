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
            && result.allowance.creationDate.timeIntervalSince1970.isFinite
            && MonthlyAllowancePolicy.monthID(containing: result.allowance.creationDate)
                == request.monthID
            && result.allowance.updatedAt == request.confirmedAt
    }
}

/// Writes a new epoch as one CloudKit transaction. The ready marker is valid for
/// a newly-created epoch because no legacy writer has ever owned that epoch.
actor CloudKitCoinLedgerInitializationProvider {
    private let database: any CoinLedgerCloudDatabase
    private let mapper = CoinLedgerRecordMapper()

    init(database: any CoinLedgerCloudDatabase) {
        self.database = database
    }

    func setup(_ request: CoinLedgerSetupRequest) async throws
        -> CoinLedgerInitializationResult
    {
        try await initialize(
            epochID: request.epochID,
            monthID: request.monthID,
            confirmedAt: request.confirmedAt,
            disclosureVersion: request.disclosureVersion,
            reason: .initialSetup
        )
    }

    func reset(_ request: CoinLedgerResetRequest) async throws
        -> CoinLedgerInitializationResult
    {
        try await initialize(
            epochID: request.epochID,
            monthID: request.monthID,
            confirmedAt: request.confirmedAt,
            disclosureVersion: request.disclosureVersion,
            reason: .userConfirmedResetAfterDeletion
        )
    }

    private func initialize(
        epochID: UUID,
        monthID: String,
        confirmedAt: Date,
        disclosureVersion: Int,
        reason: LedgerEpochReason
    ) async throws -> CoinLedgerInitializationResult {
        let suppressedMonthID = reason == .userConfirmedResetAfterDeletion ? monthID : nil
        let epoch = LedgerEpoch(
            epochID: epochID,
            createdAt: confirmedAt,
            reason: reason,
            suppressedFreeMonthID: suppressedMonthID,
            disclosureVersion: disclosureVersion
        )
        let account = try CoinAccount(
            purchasedAvailable: 0,
            purchasedReserved: 0,
            revision: 0,
            updatedAt: confirmedAt
        )
        let quota = reason == .initialSetup ? MonthlyAllowancePolicy.monthlyQuota : 0
        let proposedAllowance = try MonthlyAllowance(
            monthID: monthID,
            quota: quota,
            used: 0,
            reserved: 0,
            creationDate: confirmedAt,
            updatedAt: confirmedAt
        )
        let marker = try ReservationMigrationMarker(
            ledgerEpochID: epochID,
            state: .ready,
            legacyWritersRetiredAt: confirmedAt,
            evidenceVersion: 1,
            updatedAt: confirmedAt
        )

        var entities: [CoinLedgerRecordEntity] = [
            .ledgerEpoch(epoch),
            .coinAccount(account),
            .monthlyAllowance(proposedAllowance),
            .reservationMigrationMarker(marker),
        ]
        if quota > 0 {
            entities.append(.event(try CoinLedgerEvent(
                eventID: CoinLedgerDeterministicID.freeGrant(monthID: monthID),
                kind: .freeGrant,
                source: .monthlyFree,
                quantity: quota,
                relatedTransactionID: nil,
                relatedCommandID: nil,
                occurrenceID: nil,
                createdAt: confirmedAt
            )))
        }

        let saved: [CloudKitRecordSnapshot]
        do {
            saved = try await database.modify(CoinLedgerModifyRequest(
                recordsToSave: try entities.map(mapper.record(for:)),
                isAtomic: true
            ))
        } catch CoinLedgerDatabaseError.resultUnknown {
            saved = try await database.fetch(CoinLedgerFetchRequest(recordNames: [
                CoinLedgerRecordID.ledgerEpoch,
                CoinLedgerRecordID.coinAccount,
                CoinLedgerRecordID.allowance(monthID: monthID),
                CoinLedgerRecordID.reservationMigrationMarker(epochID: epochID),
            ]))
        }

        var confirmedEpoch: LedgerEpoch?
        var confirmedAccount: CoinAccount?
        var confirmedAllowance: MonthlyAllowance?
        var confirmedMarker: ReservationMigrationMarker?
        for record in saved {
            switch try mapper.entity(from: record) {
            case .ledgerEpoch(let value): confirmedEpoch = value
            case .coinAccount(let value): confirmedAccount = value
            case .monthlyAllowance(let value) where value.monthID == monthID:
                confirmedAllowance = value
            case .reservationMigrationMarker(let value): confirmedMarker = value
            default: break
            }
        }
        guard let confirmedEpoch, let confirmedAccount, let confirmedAllowance,
              confirmedEpoch == epoch, confirmedAccount == account,
              confirmedMarker?.ledgerEpochID == epochID,
              confirmedMarker?.state == .ready else {
            throw CoinLedgerInitializationResultError.invalidInitialState
        }
        return try CoinLedgerInitializationResult(
            epoch: confirmedEpoch,
            account: confirmedAccount,
            allowance: confirmedAllowance
        )
    }
}
