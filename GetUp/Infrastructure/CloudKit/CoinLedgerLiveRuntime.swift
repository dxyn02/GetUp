@preconcurrency import CloudKit
import Foundation

struct CoinLedgerLiveContext: Sendable {
    let snapshot: CoinLedgerReconciliationSnapshot
    let ledgerState: MonthlyAllowanceLedgerState
    let epoch: LedgerEpoch?
    let account: CoinAccount?
    let allowance: MonthlyAllowance?
    let pendingCommandIDs: [UUID]
    let syncDiagnosticReason: CoinLedgerSyncDiagnosticReason?
    let syncDiagnosticDetail: String?
}

/// Process-local production composition for the CloudKit ledger.
/// Every public read performs the T101 initial/fresh fetch; the App Group balance
/// mirror is written by `CoinLedgerSyncProvider` before the result is returned.
actor CoinLedgerLiveRuntime {
    typealias Synchronize = @Sendable () async throws -> CoinLedgerSyncProviderResult
    typealias ReconcilePending = @Sendable ([UUID]) async throws -> Void

    nonisolated let repository: any CoinLedgerRepository

    private let synchronizeProvider: Synchronize
    private let mapper = CoinLedgerRecordMapper()

    init(
        repository: any CoinLedgerRepository,
        synchronize: @escaping Synchronize
    ) {
        self.repository = repository
        synchronizeProvider = synchronize
    }

    static func live(
        containerURL: URL,
        process: CoinLedgerSyncProcess,
        cloudContainer: CKContainer,
        ledgerNamespace: String? = nil
    ) -> CoinLedgerLiveRuntime {
        let zoneName = SharedIdentifiers.coinLedgerZoneName(
            ledgerNamespace: ledgerNamespace
        )
        let database = SystemCoinLedgerCloudDatabase(
            container: cloudContainer,
            zoneName: zoneName
        )
        let syncProvider = CoinLedgerSyncProvider(
            accountProvider: SystemCoinLedgerCloudAccountProvider(container: cloudContainer),
            engine: SystemCoinLedgerSyncEngineDriver(
                container: cloudContainer,
                zoneName: zoneName,
                subscriptionID: ledgerNamespace.map { "getup.coin-ledger.sync.\($0)" }
                    ?? "getup.coin-ledger.sync"
            ),
            checkpointRepository: FileCoinLedgerSyncCheckpointRepository(
                containerURL: containerURL,
                process: process,
                ledgerNamespace: ledgerNamespace
            ),
            balanceRepository: SharedSnapshotRepository(containerURL: containerURL)
        )
        let migrationProvider = ReservationCompatibilityMigrationProvider(
            database: database,
            fetchRemoteRecords: {
                try await syncProvider.synchronize().remoteRecords
            }
        )
        let repository = CloudKitCoinLedgerRepository(
            database: database,
            verifyReservationCompatibility: { epochID in
                try await migrationProvider.verifyReservationCompatibility(epochID: epochID)
            }
        )
        return CoinLedgerLiveRuntime(
            repository: repository,
            synchronize: { try await syncProvider.synchronize() }
        )
    }

    /// Launch/foreground path: fetch, create a missing current-month allowance,
    /// reconcile durable release commands, then return one newly fetched projection.
    func refreshForApp(
        reconcilePending: @escaping ReconcilePending = { _ in }
    ) async throws -> CoinLedgerReconciliationSnapshot {
        var context = try await synchronizeContext()
        if !context.pendingCommandIDs.isEmpty {
            try await reconcilePending(context.pendingCommandIDs)
            context = try await synchronizeContext()
        }
        if case .current(let epoch) = context.ledgerState,
           context.allowance == nil {
            _ = try await repository.createAllowanceIfNeeded(
                MonthlyAllowanceCreationRequest(
                    monthID: context.snapshot.balance.currentMonthID,
                    epochID: epoch.epochID,
                    trigger: .appForeground
                )
            )
            context = try await synchronizeContext()
        }
        return context.snapshot
    }

    /// Shield path: this must be called immediately before reservation. A cached
    /// App Group mirror is never promoted to current by this API.
    func refreshBeforeShieldRequest() async throws -> CoinLedgerLiveContext {
        try await synchronizeContext()
    }

    func refresh() async throws -> CoinLedgerReconciliationSnapshot {
        try await synchronizeContext().snapshot
    }

    private func synchronizeContext() async throws -> CoinLedgerLiveContext {
        let result = try await synchronizeProvider()
        var epoch: LedgerEpoch?
        var account: CoinAccount?
        var allowances: [MonthlyAllowance] = []
        var grants: [PurchaseGrant] = []
        var events: [CoinLedgerEvent] = []
        var commands: [ReleaseCommand] = []

        do {
            for record in result.remoteRecords {
                switch try mapper.entity(from: record) {
                case .ledgerEpoch(let value): epoch = value
                case .coinAccount(let value): account = value
                case .monthlyAllowance(let value): allowances.append(value)
                case .purchaseGrant(let value): grants.append(value)
                case .event(let value): events.append(value)
                case .releaseCommand(let value): commands.append(value)
                case .releaseOccurrenceClaim, .reservationCompatibilityStamp,
                     .reservationMigrationMarker:
                    break
                }
            }
        } catch {
            throw CoinLedgerSyncProviderError.invalidProjection
        }

        let balance = result.outcome.mirror
        let allowance = allowances.first { $0.monthID == balance.currentMonthID }
        let pendingCommandIDs = commands.compactMap { command -> UUID? in
            switch command.state {
            case .requested, .reserved, .applied, .compensating, .reconciliationRequired:
                command.commandID
            case .rejected, .committed, .compensated:
                nil
            }
        }
        let ledgerState = try makeLedgerState(balance: balance, epoch: epoch)

        if case .current = ledgerState {
            guard let epoch, let account else {
                throw CoinLedgerSyncProviderError.invalidProjection
            }
            if pendingCommandIDs.isEmpty, account.purchasedReserved == 0,
               let allowance, allowance.reserved == 0 {
                _ = try CoinLedgerRecoveryService().recoverFreshInstall(
                    snapshot: CoinLedgerRecoverySnapshot(
                        epoch: epoch,
                        account: account,
                        allowance: allowance,
                        purchaseGrants: grants,
                        events: events
                    ),
                    ledgerState: .current,
                    syncedAt: balance.syncedAt
                )
            }
        }

        let snapshot = CoinLedgerReconciliationSnapshot(
            balance: balance,
            purchaseGrants: grants,
            events: events,
            pendingProductIdentifiers: [],
            hasPendingReconciliation: !pendingCommandIDs.isEmpty
        )
        return CoinLedgerLiveContext(
            snapshot: snapshot,
            ledgerState: ledgerState,
            epoch: epoch,
            account: account,
            allowance: allowance,
            pendingCommandIDs: pendingCommandIDs,
            syncDiagnosticReason: result.diagnosticReason,
            syncDiagnosticDetail: result.diagnosticDetail
        )
    }

    private func makeLedgerState(
        balance: CoinBalanceSnapshot,
        epoch: LedgerEpoch?
    ) throws -> MonthlyAllowanceLedgerState {
        switch balance.syncState {
        case .setupRequired: return .setupRequired
        case .current:
            guard let epoch, balance.ledgerEpochID == epoch.epochID else {
                throw CoinLedgerSyncProviderError.invalidProjection
            }
            return .current(epoch: epoch)
        case .syncing: return .syncing
        case .stale: return .stale
        case .unavailable: return .unavailable
        case .deletionConfirmed: return .deletionConfirmed
        case .resetRequired: return .resetRequired
        }
    }
}

struct CoinRuleReleaseLiveResult: Sendable {
    let fundingSource: ReleaseFundingSource
    let ledger: CoinLedgerReconciliationSnapshot
    let remainingOccurrences: [RestrictionOccurrence]
}

/// Shared app/Shield release composition. The service's context provider always
/// enters through `refreshBeforeShieldRequest`, so reservation cannot trust the
/// balance mirror that was rendered before the user tapped.
struct CoinRuleReleaseLiveExecutor: Sendable {
    let runtime: CoinLedgerLiveRuntime
    let sharedRepository: SharedSnapshotRepository
    let applyRestrictions: @Sendable (RuleReleaseLocalLease) async throws
        -> RuleReleaseApplication
    let reconcileLiveActivity: @Sendable (RestrictionLiveActivitySnapshot?) async
        -> LiveActivityCoordinationResult
    let coordinationDirectory: URL
    let clock: any Clock

    func execute(
        occurrence: RestrictionOccurrence,
        commandID: UUID,
        source: ReleaseRequestSource
    ) async throws -> CoinRuleReleaseLiveResult {
        let reservation = try await reserve(
            occurrence: occurrence,
            commandID: commandID,
            source: source
        )
        let exception = try ReleaseException(
            commandID: commandID,
            occurrenceID: occurrence.id,
            ruleID: occurrence.ruleID,
            ruleRevision: occurrence.ruleRevision,
            effectiveAt: clock.now,
            expiresAt: occurrence.endAt
        )
        let coordinator = RuleReleaseCoordinator(
            exceptionRepository: sharedRepository,
            ledgerRepository: runtime.repository,
            applyRestrictions: applyRestrictions,
            reconcileLiveActivity: reconcileLiveActivity,
            clock: clock,
            coordinationDirectory: coordinationDirectory
        )
        let result = try await coordinator.coordinate(
            reservation: reservation,
            exception: exception
        )
        guard let fundingSource = result.committedCommand.fundingSource else {
            throw RuleReleaseCoordinationError.invalidReservation
        }
        let ledger = try await runtime.refresh()
        let remaining = try await activeOccurrences(at: clock.now)
        return CoinRuleReleaseLiveResult(
            fundingSource: fundingSource,
            ledger: ledger,
            remainingOccurrences: remaining
        )
    }

    func reserve(
        occurrence: RestrictionOccurrence,
        commandID: UUID,
        source: ReleaseRequestSource
    ) async throws -> CoinReleaseReservation {
        let service = RuleReleaseService(
            repository: runtime.repository,
            now: { clock.now },
            fetchCurrentContext: { request in
                try await currentContext(for: request)
            }
        )
        return try await service.reserve(RuleReleaseRequest(
            commandID: commandID,
            occurrenceID: occurrence.id,
            ruleID: occurrence.ruleID,
            ruleRevision: occurrence.ruleRevision,
            endsAt: occurrence.endAt,
            ledgerEpochID: try await requiredEpochID(),
            monthID: MonthlyAllowancePolicy.monthID(containing: clock.now),
            requestedFrom: source,
            requestedAt: clock.now
        ))
    }

    func apply(
        reservation: CoinReleaseReservation,
        occurrence: RestrictionOccurrence
    ) async throws {
        let exception = try ReleaseException(
            commandID: reservation.command.commandID,
            occurrenceID: occurrence.id,
            ruleID: occurrence.ruleID,
            ruleRevision: occurrence.ruleRevision,
            effectiveAt: clock.now,
            expiresAt: occurrence.endAt
        )
        _ = try await RuleReleaseCoordinator(
            exceptionRepository: sharedRepository,
            ledgerRepository: runtime.repository,
            applyRestrictions: applyRestrictions,
            reconcileLiveActivity: reconcileLiveActivity,
            clock: clock,
            coordinationDirectory: coordinationDirectory
        ).coordinate(reservation: reservation, exception: exception)
    }

    func reconcilePending(_ commandIDs: [UUID]) async throws {
        _ = try await RuleReleaseReconciler(
            exceptionRepository: sharedRepository,
            ledgerRepository: runtime.repository,
            applyRestrictions: applyRestrictions,
            reconcileLiveActivity: reconcileLiveActivity,
            clock: clock,
            coordinationDirectory: coordinationDirectory
        ).reconcilePending(commandIDs: commandIDs)
    }

    private func requiredEpochID() async throws -> UUID {
        let context = try await runtime.refreshBeforeShieldRequest()
        guard case .current(let epoch) = context.ledgerState else {
            throw CoinLedgerRepositoryError.ledgerNotCurrent
        }
        return epoch.epochID
    }

    private func currentContext(
        for request: RuleReleaseRequest
    ) async throws -> RuleReleaseReservationContext {
        let ledger = try await runtime.refreshBeforeShieldRequest()
        guard let account = ledger.account else {
            throw CoinLedgerRepositoryError.ledgerNotCurrent
        }
        let rules = try await sharedRepository.loadRuleCollection()?.rules ?? []
        let active = try await sharedRepository.loadActiveRestrictionSnapshot()
        let occurrences = RestrictionOccurrenceEvaluator.evaluate(
            snapshot: active,
            currentRuleRevisions: Dictionary(
                uniqueKeysWithValues: rules.map { ($0.id, $0.revision) }
            ),
            now: clock.now
        ).orderedOccurrences
        let exceptions = try await sharedRepository.loadReleaseExceptions()
        return RuleReleaseReservationContext(
            ledgerState: ledger.ledgerState,
            occurrence: occurrences.first { $0.id == request.occurrenceID },
            currentRuleRevision: rules.first { $0.id == request.ruleID }?.revision ?? -1,
            hasReleaseException: exceptions.contains { $0.occurrenceID == request.occurrenceID },
            allowance: ledger.allowance,
            account: account
        )
    }

    private func activeOccurrences(at date: Date) async throws -> [RestrictionOccurrence] {
        let rules = try await sharedRepository.loadRuleCollection()?.rules ?? []
        return RestrictionOccurrenceEvaluator.evaluate(
            snapshot: try await sharedRepository.loadActiveRestrictionSnapshot(),
            currentRuleRevisions: Dictionary(
                uniqueKeysWithValues: rules.map { ($0.id, $0.revision) }
            ),
            now: date
        ).orderedOccurrences
    }
}
