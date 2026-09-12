@preconcurrency import CloudKit
import Foundation
@preconcurrency import ManagedSettings

private final class ShieldActionCompletion: @unchecked Sendable {
    let handler: (ShieldActionResponse) -> Void

    init(_ handler: @escaping (ShieldActionResponse) -> Void) {
        self.handler = handler
    }
}

private struct ShieldActionResponseBox: @unchecked Sendable {
    let value: ShieldActionResponse
}

private final class ShieldActionDiagnosticRecorder: @unchecked Sendable {
    private let defaults: UserDefaults?

    init(appGroupIdentifier: String) {
        defaults = UserDefaults(suiteName: appGroupIdentifier)
    }

    func record(_ stage: String, detail: String? = nil) {
        var value: [String: Any] = [
            "stage": stage,
            "recordedAt": Date().timeIntervalSince1970
        ]
        if let detail {
            value["detail"] = detail
        }
        defaults?.set(value, forKey: SharedIdentifiers.shieldActionDiagnosticDefaultsKey)
        defaults?.synchronize()
    }

    func errorDetail(_ error: any Error) -> String {
        if let error = error as? ShieldCoinActionContextReaderError {
            switch error {
            case .snapshotUnavailable: return "snapshotUnavailable"
            case .noMatchingOccurrence: return "noMatchingOccurrence"
            }
        }
        return String(describing: type(of: error))
    }
}

private actor ShieldActionRuntimeDeadlineGate {
    private var continuation: CheckedContinuation<ShieldActionResponseBox?, Never>?
    private var tasks: [Task<Void, Never>] = []
    private var resolved = false

    init(_ continuation: CheckedContinuation<ShieldActionResponseBox?, Never>) {
        self.continuation = continuation
    }

    func register(_ tasks: [Task<Void, Never>]) {
        guard !resolved else {
            tasks.forEach { $0.cancel() }
            return
        }
        self.tasks = tasks
    }

    func resolve(_ response: ShieldActionResponseBox?) {
        guard !resolved else { return }
        resolved = true
        continuation?.resume(returning: response)
        continuation = nil
        tasks.forEach { $0.cancel() }
        tasks = []
    }
}

private final class ShieldCoinActionRuntime: @unchecked Sendable {
    private let contextReader: ShieldCoinActionContextReader
    private let handler: ShieldCoinActionHandler
    private let routeRepository: PendingAppRouteRepository
    private let ledgerRuntime: CoinLedgerLiveRuntime
    private let responsePolicy = ShieldActionResponsePolicy()
    private let diagnosticRecorder: ShieldActionDiagnosticRecorder

    private init(
        contextReader: ShieldCoinActionContextReader,
        handler: ShieldCoinActionHandler,
        routeRepository: PendingAppRouteRepository,
        ledgerRuntime: CoinLedgerLiveRuntime,
        diagnosticRecorder: ShieldActionDiagnosticRecorder
    ) {
        self.contextReader = contextReader
        self.handler = handler
        self.routeRepository = routeRepository
        self.ledgerRuntime = ledgerRuntime
        self.diagnosticRecorder = diagnosticRecorder
    }

    static func live() -> ShieldCoinActionRuntime? {
        guard
            let identifier = SharedIdentifiers.appGroupIdentifier(),
            let cloudContainerIdentifier = SharedIdentifiers.iCloudContainerIdentifier(),
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: identifier
            )
        else {
            return nil
        }

        let routeRepository = PendingAppRouteRepository(containerURL: containerURL)
        let diagnosticRecorder = ShieldActionDiagnosticRecorder(appGroupIdentifier: identifier)
#if DEBUG
        diagnosticRecorder.record("runtimeReady")
#endif
        let ledgerRuntime = CoinLedgerLiveRuntime.live(
            containerURL: containerURL,
            process: .shieldAction,
            cloudContainer: CKContainer(identifier: cloudContainerIdentifier)
        )
        let container = DependencyContainer(
            containerURL: containerURL,
            coinLedgerRepository: ledgerRuntime.repository
        )
        let releaseExecutor = CoinRuleReleaseLiveExecutor(
            runtime: ledgerRuntime,
            sharedRepository: container.sharedSnapshotRepository,
            applyRestrictions: { lease in
                let provider = try await MainActor.run {
                    try container.makeRuleReleaseApplicationProvider(
                        authorizationProvider: SystemAuthorizationProvider()
                    )
                }
                return try await provider(lease)
            },
            reconcileLiveActivity: { _ in .noChange },
            coordinationDirectory: containerURL,
            clock: SystemRestrictionClock()
        )
        let handler = ShieldCoinActionHandler(
            releaseRepresentative: { occurrence in
                do {
#if DEBUG
                    diagnosticRecorder.record("releaseRefreshStarted")
#endif
                    let context = try await ledgerRuntime.refreshBeforeShieldRequest()
#if DEBUG
                    diagnosticRecorder.record(
                        "releaseRefreshCompleted",
                        detail: [
                            "state: \(context.snapshot.balance.syncState.rawValue)",
                            context.syncDiagnosticReason.map { "reason: \($0.rawValue)" },
                            context.syncDiagnosticDetail
                        ].compactMap { $0 }.joined(separator: ", ")
                    )
#endif
                    guard case .current = context.ledgerState else {
                        switch context.snapshot.balance.syncState {
                        case .deletionConfirmed, .resetRequired: return .ledgerResetRequired
                        default: return .iCloudRecoveryRequired
                        }
                    }
                    guard !context.snapshot.hasPendingReconciliation else {
                        return .reconciliationRequired
                    }
                    guard context.snapshot.balance.freeAvailable > 0
                            || context.snapshot.balance.purchasedAvailable > 0 else {
                        return .insufficientBalance
                    }
                } catch {
#if DEBUG
                    diagnosticRecorder.record(
                        "releaseRefreshFailed",
                        detail: diagnosticRecorder.errorDetail(error)
                    )
#endif
                    return .iCloudRecoveryRequired
                }
                let commandID = UUID()
                let policy = ShieldReleaseDeadlinePolicy(
                    deadline: .seconds(5),
                    monotonicNow: { ContinuousClock().now },
                    attemptRelease: { commandID in
                        .confirmed(try await releaseExecutor.reserve(
                            occurrence: occurrence,
                            commandID: commandID,
                            source: .shield
                        ))
                    },
                    applyConfirmedRelease: { reservation in
                        try await releaseExecutor.apply(
                            reservation: reservation,
                            occurrence: occurrence
                        )
                    },
                    reconcileUnapplied: { commandID in
                        if try await ledgerRuntime.repository.fetchReleaseCommand(
                            commandID: commandID
                        ) != nil {
                            try await releaseExecutor.reconcilePending([commandID])
                        }
                        return try await ledgerRuntime.repository.fetchReleaseCommand(
                            commandID: commandID
                        )
                    },
                    savePendingRoute: { route in
                        try await routeRepository.save(route)
                    },
                    makeRouteID: UUID.init,
                    wallNow: Date.init
                )
                do {
#if DEBUG
                    diagnosticRecorder.record("releaseAttemptStarted")
#endif
                    switch try await policy.perform(
                        commandID: commandID,
                        occurrenceID: occurrence.id
                    ) {
                    case .released:
#if DEBUG
                        diagnosticRecorder.record("releaseCommitted")
#endif
                        let command = try await ledgerRuntime.repository
                            .fetchReleaseCommand(commandID: commandID)
                        guard let source = command?.fundingSource else { return .rejected }
                        return .released(fundingSource: source)
                    case .reconciliationRequired:
#if DEBUG
                        diagnosticRecorder.record("releaseNeedsReconciliation")
#endif
                        return .reconciliationRequired
                    }
                } catch CoinLedgerRepositoryError.insufficientMonthlyAllowance {
#if DEBUG
                    diagnosticRecorder.record("releaseInsufficientMonthly")
#endif
                    return .insufficientBalance
                } catch CoinLedgerRepositoryError.insufficientPurchasedBalance {
#if DEBUG
                    diagnosticRecorder.record("releaseInsufficientPurchased")
#endif
                    return .insufficientBalance
                } catch CoinLedgerRepositoryError.reconciliationRequired {
#if DEBUG
                    diagnosticRecorder.record("releaseNeedsReconciliation")
#endif
                    return .reconciliationRequired
                } catch {
#if DEBUG
                    diagnosticRecorder.record(
                        "releaseFailed",
                        detail: diagnosticRecorder.errorDetail(error)
                    )
#endif
                    let state = try? await ledgerRuntime.refresh().balance.syncState
                    switch state {
                    case .deletionConfirmed, .resetRequired: return .ledgerResetRequired
                    case .current: return .rejected
                    default: return .iCloudRecoveryRequired
                    }
                }
            },
            savePendingRoute: { route in
                try await routeRepository.save(route)
            },
            discardPendingRoute: {
                try await routeRepository.discard()
            }
        )
        return ShieldCoinActionRuntime(
            contextReader: ShieldCoinActionContextReader(containerURL: containerURL),
            handler: handler,
            routeRepository: routeRepository,
            ledgerRuntime: ledgerRuntime,
            diagnosticRecorder: diagnosticRecorder
        )
    }

    func handle(applicationToken: ApplicationToken) async -> ShieldActionResponse {
        await handle { [self] in try await contextReader.context(for: applicationToken) }
    }

    func handle(categoryToken: ActivityCategoryToken) async -> ShieldActionResponse {
        await handle { [self] in try await contextReader.context(for: categoryToken) }
    }

    func handle(webDomainToken: WebDomainToken) async -> ShieldActionResponse {
        await handle { [self] in try await contextReader.context(for: webDomainToken) }
    }

    private func handle(
        loadContext: @escaping @Sendable () async throws -> ShieldCoinActionContext
    ) async -> ShieldActionResponse {
#if DEBUG
        diagnosticRecorder.record("actionStarted")
#endif
        let response = await withCheckedContinuation { continuation in
            let gate = ShieldActionRuntimeDeadlineGate(continuation)
            let operation = Task { [self] in
                await gate.resolve(ShieldActionResponseBox(
                    value: await handleWithinDeadline(loadContext: loadContext)
                ))
            }
            let timeout = Task {
                try? await Task.sleep(for: .seconds(5))
                await gate.resolve(nil)
            }
            Task { await gate.register([operation, timeout]) }
        }
        if let response { return response.value }
#if DEBUG
        diagnosticRecorder.record("actionDeadlineExceeded")
#endif
        return await saveRecoveryRoute(reason: "outerDeadline")
    }

    private func handleWithinDeadline(
        loadContext: @escaping @Sendable () async throws -> ShieldCoinActionContext
    ) async -> ShieldActionResponse {
        do {
            let localContext = try await loadContext()
#if DEBUG
            diagnosticRecorder.record(
                "localContextLoaded",
                detail: "active: \(localContext.activeRestrictionCount)"
            )
            diagnosticRecorder.record("initialRefreshStarted")
#endif
            let ledger = try await ledgerRuntime.refreshBeforeShieldRequest()
#if DEBUG
            diagnosticRecorder.record(
                "initialRefreshCompleted",
                detail: [
                    "state: \(ledger.snapshot.balance.syncState.rawValue)",
                    ledger.syncDiagnosticReason.map { "reason: \($0.rawValue)" },
                    ledger.syncDiagnosticDetail
                ].compactMap { $0 }.joined(separator: ", ")
            )
#endif
            let context = ShieldCoinActionContext(
                representative: localContext.representative,
                activeRestrictionCount: localContext.activeRestrictionCount,
                balance: ledger.snapshot.balance,
                hasPendingReconciliation: ledger.snapshot.hasPendingReconciliation
            )
            return await handler.handlePrimaryAction(
                context: context,
                operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersion
            ).response
        } catch {
#if DEBUG
            let detail = diagnosticRecorder.errorDetail(error)
            diagnosticRecorder.record("actionPreparationFailed", detail: detail)
            return await saveRecoveryRoute(reason: detail)
#else
            return await saveRecoveryRoute()
#endif
        }
    }

    private func saveRecoveryRoute(reason: String? = nil) async -> ShieldActionResponse {
#if DEBUG
        diagnosticRecorder.record("savingRecoveryRoute", detail: reason)
#endif
        do {
            try await routeRepository.save(PendingAppRoute(
                routeID: UUID(),
                destination: .iCloudRecovery,
                createdAt: Date(),
                occurrenceID: nil,
                consumedAt: nil
            ))
            return responsePolicy.responseAfterSavingRoute(
                operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersion
            )
        } catch {
#if DEBUG
            diagnosticRecorder.record(
                "savingRecoveryRouteFailed",
                detail: diagnosticRecorder.errorDetail(error)
            )
#endif
            return .defer
        }
    }
}

final class ShieldActionExtension: ShieldActionDelegate {
    private let responsePolicy = ShieldActionResponsePolicy()
    private let runtime = ShieldCoinActionRuntime.live()

    private func complete(
        action: ShieldAction,
        primaryAction: @escaping @Sendable () async -> ShieldActionResponse,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        guard action == .primaryButtonPressed, runtime != nil else {
            completionHandler(responsePolicy.response(for: action))
            return
        }

        let completion = ShieldActionCompletion(completionHandler)
#if DEBUG
        ActivityKitFeasibilityProbe.recordInvocation()
#endif
        Task { [completion] in
#if DEBUG
            async let probe: ActivityKitFeasibilityProbe.Report = ActivityKitFeasibilityProbe.run()
#endif
            completion.handler(await primaryAction())
#if DEBUG
            _ = await probe
#endif
        }
    }

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        complete(
            action: action,
            primaryAction: { [runtime] in
                await runtime?.handle(applicationToken: application) ?? .close
            },
            completionHandler: completionHandler
        )
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        complete(
            action: action,
            primaryAction: { [runtime] in
                await runtime?.handle(categoryToken: category) ?? .close
            },
            completionHandler: completionHandler
        )
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        complete(
            action: action,
            primaryAction: { [runtime] in
                await runtime?.handle(webDomainToken: webDomain) ?? .close
            },
            completionHandler: completionHandler
        )
    }
}
