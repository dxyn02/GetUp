import Foundation

enum DependencyContainerError: Error, Equatable, Sendable {
    case missingAppGroupIdentifier
    case appGroupContainerUnavailable
}

struct DependencyContainer: Sendable {
    typealias MonthlyAllowanceForegroundContextProvider = @Sendable () async throws ->
        MonthlyAllowanceForegroundContext?

    let sharedSnapshotRepository: SharedSnapshotRepository
    let diagnostics: any DiagnosticsLogging
    let monthlyAllowanceService: MonthlyAllowanceService?
    let ensureMonthlyAllowanceOnForeground: @Sendable () async throws -> Void

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
            MonthlyAllowanceForegroundContextProvider? = nil
    ) {
        sharedSnapshotRepository = SharedSnapshotRepository(
            containerURL: containerURL,
            fileWriter: fileWriter
        )
        self.diagnostics = diagnostics

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
        fileManager: FileManager = .default
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
            containerURL: containerURL
        )
    }
}
