import Foundation

enum DependencyContainerError: Error, Equatable, Sendable {
    case missingAppGroupIdentifier
    case appGroupContainerUnavailable
}

enum CoinAppLifecycleTrigger: Equatable, Sendable {
    case launch
    case foreground
}

enum CoinAppLifecycleFailure: Equatable, Sendable {
    case transactionObservation
    case ledgerReconciliation
    case activeOccurrenceLoad
    case routeConsumption
}

struct CoinAppLifecycleRefreshResult: Equatable, Sendable {
    let ledger: CoinLedgerReconciliationSnapshot?
    let destination: PendingAppRouteDestination?
    let failures: [CoinAppLifecycleFailure]
}

struct CoinLedgerReconciliationSnapshot: Equatable, Sendable {
    let balance: CoinBalanceSnapshot
    let purchaseGrants: [PurchaseGrant]
    let events: [CoinLedgerEvent]
    let pendingProductIdentifiers: Set<String>
    let hasPendingReconciliation: Bool
}

enum MonthlyAllowanceUITestFixtureMode: String, Sendable {
    case persistedOneRemaining = "persisted-one-remaining"
    case firstApp = "first-app"
    case firstShield = "first-shield"
    case firstSetup = "first-setup"
    case deletionReset = "deletion-reset"
}

struct MonthlyAllowanceUITestFixtureStore {
    private struct PersistedState: Codable {
        var monthID: String
        var purchasedAvailable: Int
        var freeAvailable: Int
    }

    private let fileURL: URL

    init(containerURL: URL) {
        fileURL = containerURL.appendingPathComponent("ui-test-monthly-allowance.json")
    }

    func balance(
        mode: MonthlyAllowanceUITestFixtureMode?,
        syncState: CoinBalanceSyncState,
        now: Date
    ) throws -> CoinBalanceSnapshot {
        let currentMonthID = MonthlyAllowancePolicy.monthID(containing: now)
        let state: PersistedState

        switch (mode, syncState) {
        case (.firstSetup, .setupRequired):
            state = PersistedState(
                monthID: currentMonthID,
                purchasedAvailable: 0,
                freeAvailable: 0
            )
        case (.deletionReset, .deletionConfirmed), (.deletionReset, .resetRequired):
            state = PersistedState(
                monthID: currentMonthID,
                purchasedAvailable: 0,
                freeAvailable: 0
            )
        case (.some(let mode), .current):
            if let persisted = try load(), persisted.monthID == currentMonthID {
                state = persisted
            } else if let persisted = try load() {
                state = PersistedState(
                    monthID: currentMonthID,
                    purchasedAvailable: persisted.purchasedAvailable,
                    freeAvailable: MonthlyAllowancePolicy.monthlyQuota
                )
            } else {
                state = Self.initialState(for: mode, monthID: currentMonthID)
            }
        default:
            state = PersistedState(
                monthID: currentMonthID,
                purchasedAvailable: syncState == .current ? 3 : 0,
                freeAvailable: syncState == .current ? 1 : 0
            )
        }

        if mode != nil {
            try save(state)
        }
        return try snapshot(from: state, syncState: syncState, now: now)
    }

    func save(_ balance: CoinBalanceSnapshot) throws {
        try save(PersistedState(
            monthID: balance.currentMonthID,
            purchasedAvailable: balance.purchasedAvailable,
            freeAvailable: balance.freeAvailable
        ))
    }

    private func snapshot(
        from state: PersistedState,
        syncState: CoinBalanceSyncState,
        now: Date
    ) throws -> CoinBalanceSnapshot {
        try CoinBalanceSnapshot(
            purchasedAvailable: state.purchasedAvailable,
            currentMonthID: state.monthID,
            freeAvailable: state.freeAvailable,
            syncState: syncState,
            syncedAt: now,
            ledgerEpochID: syncState == .current
                ? UUID(uuidString: "00000000-0000-4000-8000-000000000901")
                : nil,
            hadConfirmedLedger: syncState != .setupRequired
        )
    }

    private func load() throws -> PersistedState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(PersistedState.self, from: Data(contentsOf: fileURL))
    }

    private func save(_ state: PersistedState) throws {
        try JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
    }

    private static func initialState(
        for mode: MonthlyAllowanceUITestFixtureMode,
        monthID: String
    ) -> PersistedState {
        switch mode {
        case .persistedOneRemaining:
            PersistedState(monthID: monthID, purchasedAvailable: 3, freeAvailable: 1)
        case .firstApp, .firstShield:
            PersistedState(
                monthID: monthID,
                purchasedAvailable: 3,
                freeAvailable: MonthlyAllowancePolicy.monthlyQuota
            )
        case .firstSetup:
            PersistedState(
                monthID: monthID,
                purchasedAvailable: 0,
                freeAvailable: MonthlyAllowancePolicy.monthlyQuota
            )
        case .deletionReset:
            PersistedState(monthID: monthID, purchasedAvailable: 0, freeAvailable: 0)
        }
    }
}

actor CoinAppLifecycleCoordinator {
    typealias StartTransactionObservation = @Sendable () async throws -> Void
    typealias ReconcileLedger = @Sendable () async throws -> CoinLedgerReconciliationSnapshot?
    typealias LoadActiveOccurrenceIDs = @Sendable (Date) async throws -> Set<String>
    typealias ConsumePendingRoute = @Sendable (
        Date,
        Set<String>
    ) async throws -> PendingAppRouteDestination?

    private let startTransactionObservation: StartTransactionObservation
    private let reconcileLedger: ReconcileLedger
    private let loadActiveOccurrenceIDs: LoadActiveOccurrenceIDs
    private let consumePendingRoute: ConsumePendingRoute
    private var transactionObservationStarted = false

    init(
        startTransactionObservation: @escaping StartTransactionObservation,
        reconcileLedger: @escaping ReconcileLedger,
        loadActiveOccurrenceIDs: @escaping LoadActiveOccurrenceIDs,
        consumePendingRoute: @escaping ConsumePendingRoute
    ) {
        self.startTransactionObservation = startTransactionObservation
        self.reconcileLedger = reconcileLedger
        self.loadActiveOccurrenceIDs = loadActiveOccurrenceIDs
        self.consumePendingRoute = consumePendingRoute
    }

    func refresh(
        trigger: CoinAppLifecycleTrigger,
        now: Date
    ) async -> CoinAppLifecycleRefreshResult {
        var failures: [CoinAppLifecycleFailure] = []

        if !transactionObservationStarted {
            transactionObservationStarted = true
            do {
                try await startTransactionObservation()
            } catch {
                failures.append(.transactionObservation)
            }
        }

        let ledger: CoinLedgerReconciliationSnapshot?
        do {
            ledger = try await reconcileLedger()
        } catch {
            ledger = nil
            failures.append(.ledgerReconciliation)
        }

        let activeOccurrenceIDs: Set<String>
        do {
            activeOccurrenceIDs = try await loadActiveOccurrenceIDs(now)
        } catch {
            failures.append(.activeOccurrenceLoad)
            return CoinAppLifecycleRefreshResult(
                ledger: ledger,
                destination: nil,
                failures: failures
            )
        }

        let destination: PendingAppRouteDestination?
        do {
            destination = try await consumePendingRoute(now, activeOccurrenceIDs)
        } catch {
            destination = nil
            failures.append(.routeConsumption)
        }

        _ = trigger
        return CoinAppLifecycleRefreshResult(
            ledger: ledger,
            destination: destination,
            failures: failures
        )
    }
}

struct DependencyContainer: Sendable {
    typealias MonthlyAllowanceForegroundContextProvider = @Sendable () async throws ->
        MonthlyAllowanceForegroundContext?

    let sharedSnapshotRepository: SharedSnapshotRepository
    let diagnostics: any DiagnosticsLogging
    let monthlyAllowanceService: MonthlyAllowanceService?
    let ensureMonthlyAllowanceOnForeground: @Sendable () async throws -> Void
    let coordinationDirectory: URL
    let startCoinTransactionObservation: CoinAppLifecycleCoordinator.StartTransactionObservation
    let reconcileCoinLedgerOnForeground: CoinAppLifecycleCoordinator.ReconcileLedger

    var ruleRepository: any RuleRepository {
        sharedSnapshotRepository
    }

    var savedPlaceRepository: any SavedPlaceRepository {
        sharedSnapshotRepository
    }

    var locationConditionRepository: any LocationConditionRepository {
        sharedSnapshotRepository
    }

    init(
        containerURL: URL,
        fileWriter: any SnapshotFileWriting = AtomicSnapshotFileWriter(),
        diagnostics: any DiagnosticsLogging = DiagnosticsLogger(),
        coinLedgerRepository: (any CoinLedgerRepository)? = nil,
        monthlyAllowanceForegroundContextProvider:
            MonthlyAllowanceForegroundContextProvider? = nil,
        startCoinTransactionObservation:
            @escaping CoinAppLifecycleCoordinator.StartTransactionObservation = {},
        reconcileCoinLedgerOnForeground:
            @escaping CoinAppLifecycleCoordinator.ReconcileLedger = { nil }
    ) {
        coordinationDirectory = containerURL
        sharedSnapshotRepository = SharedSnapshotRepository(
            containerURL: containerURL,
            fileWriter: fileWriter
        )
        self.diagnostics = diagnostics
        self.startCoinTransactionObservation = startCoinTransactionObservation
        self.reconcileCoinLedgerOnForeground = reconcileCoinLedgerOnForeground

        if let coinLedgerRepository {
            let service = MonthlyAllowanceService(
                repository: coinLedgerRepository,
                reserveMonthlyFree: { request in
                    try await coinLedgerRepository.reserveMonthlyFree(request)
                }
            )
            monthlyAllowanceService = service
            ensureMonthlyAllowanceOnForeground = {
                guard let context = try await monthlyAllowanceForegroundContextProvider?() else {
                    return
                }
                _ = try await service.ensureAllowanceForAppForeground(
                    monthID: context.monthID,
                    ledgerState: context.ledgerState,
                    existingAllowance: context.existingAllowance
                )
            }
        } else {
            monthlyAllowanceService = nil
            ensureMonthlyAllowanceOnForeground = {}
        }
    }

    static func live(
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        startCoinTransactionObservation:
            @escaping CoinAppLifecycleCoordinator.StartTransactionObservation = {},
        reconcileCoinLedgerOnForeground:
            @escaping CoinAppLifecycleCoordinator.ReconcileLedger = { nil }
    ) throws -> DependencyContainer {
        guard let appGroupIdentifier = SharedIdentifiers.appGroupIdentifier(in: bundle) else {
            throw DependencyContainerError.missingAppGroupIdentifier
        }
        guard
            let containerURL = fileManager.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier
            )
        else {
            throw DependencyContainerError.appGroupContainerUnavailable
        }

        return DependencyContainer(
            containerURL: containerURL,
            startCoinTransactionObservation: startCoinTransactionObservation,
            reconcileCoinLedgerOnForeground: reconcileCoinLedgerOnForeground
        )
    }
}
