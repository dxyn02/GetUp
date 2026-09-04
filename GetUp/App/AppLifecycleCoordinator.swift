import Foundation

private struct SystemAppLifecycleClock: Clock {
    var now: Date { Date() }
}

enum AppLifecycleRecoveryFailure: Equatable, Sendable {
    case scheduleReset
    case locationReset
    case schedule(ruleID: UUID)
    case location(ruleID: UUID)
    case monthlyAllowance
    case restriction
    case liveActivity
}

struct AppLifecycleRecoveryResult: Equatable, Sendable {
    let recoveredRuleIDs: [UUID]
    let failures: [AppLifecycleRecoveryFailure]
    let authorization: AuthorizationSnapshot
    let presentationState: RestrictionPresentationState?
}

actor AppLifecycleCoordinator {
    static let maximumExtensionEvidenceAge: TimeInterval = 5 * 60

    typealias RestrictionRestore = @Sendable () async throws -> RestrictionCoordinationResult
    typealias PersistedLocationConditionLoad = @Sendable (
        [RestrictionRuleSnapshot]
    ) async throws -> [LocationConditionSnapshot]
    typealias LiveActivityReconcile = @Sendable (
        [RestrictionRuleSnapshot],
        [LocationConditionSnapshot]
    ) async throws -> Void
    typealias MonthlyAllowanceEnsure = @Sendable () async throws -> Void

    private let ruleRepository: any RuleRepository
    private let scheduleManager: any ScheduleManaging
    private let locationMonitor: any LocationMonitoring
    private let authorizationProvider: any AuthorizationProviding
    private let ensureMonthlyAllowance: MonthlyAllowanceEnsure
    private let restoreRestriction: RestrictionRestore
    private let loadPersistedLocationConditions: PersistedLocationConditionLoad
    private let reconcileLiveActivity: LiveActivityReconcile
    private let clock: any Clock

    init(
        ruleRepository: any RuleRepository,
        scheduleManager: any ScheduleManaging,
        locationMonitor: any LocationMonitoring,
        authorizationProvider: any AuthorizationProviding,
        ensureMonthlyAllowance: @escaping MonthlyAllowanceEnsure = {},
        restoreRestriction: @escaping RestrictionRestore,
        loadPersistedLocationConditions: @escaping PersistedLocationConditionLoad = { _ in [] },
        reconcileLiveActivity: @escaping LiveActivityReconcile = { _, _ in },
        clock: any Clock = SystemAppLifecycleClock()
    ) {
        self.ruleRepository = ruleRepository
        self.scheduleManager = scheduleManager
        self.locationMonitor = locationMonitor
        self.authorizationProvider = authorizationProvider
        self.ensureMonthlyAllowance = ensureMonthlyAllowance
        self.restoreRestriction = restoreRestriction
        self.loadPersistedLocationConditions = loadPersistedLocationConditions
        self.reconcileLiveActivity = reconcileLiveActivity
        self.clock = clock
    }

    func restore() async throws -> AppLifecycleRecoveryResult {
        let rules = try await ruleRepository.loadRuleCollection()?.rules ?? []
        let enabledRules = rules.filter(\.isEnabled).sorted(by: Self.ruleOrder)
        let persistedLocationConditions = try await loadPersistedLocationConditions(
            enabledRules
        )
        let authorization = await authorizationProvider.authorizationSnapshot()
        let recoveryStartedAt = clock.now
        var failures: [AppLifecycleRecoveryFailure] = []
        var recoveredRuleIDs: [UUID] = []
        var liveActivityLocationConditions: [LocationConditionSnapshot] = []

        do {
            try await scheduleManager.removeSchedules()
        } catch {
            failures.append(.scheduleReset)
        }
        do {
            try await locationMonitor.stopMonitoring()
        } catch {
            failures.append(.locationReset)
        }

        for rule in enabledRules {
            var recoveredSchedule = true
            var recoveredLocation = true
            let extensionEvidence = persistedLocationConditions.first {
                Self.isFreshExtensionEvidence(
                    $0,
                    for: rule,
                    now: recoveryStartedAt
                )
            }

            do {
                try await scheduleManager.replaceSchedules(for: rule)
            } catch {
                recoveredSchedule = false
                failures.append(.schedule(ruleID: rule.id))
            }

            do {
                try await locationMonitor.replaceMonitoring(for: rule)
                if let extensionEvidence {
                    liveActivityLocationConditions.append(extensionEvidence)
                } else {
                    liveActivityLocationConditions.append(
                        await locationMonitor.refreshLocationCondition(
                            for: rule,
                            source: .restoration
                        )
                    )
                }
            } catch {
                recoveredLocation = false
                failures.append(.location(ruleID: rule.id))
                if let extensionEvidence {
                    liveActivityLocationConditions.append(extensionEvidence)
                }
            }

            if recoveredSchedule && recoveredLocation {
                recoveredRuleIDs.append(rule.id)
            }
        }

        do {
            try await ensureMonthlyAllowance()
        } catch {
            failures.append(.monthlyAllowance)
        }

        let restrictionResult: RestrictionCoordinationResult?
        do {
            restrictionResult = try await restoreRestriction()
        } catch {
            failures.append(.restriction)
            restrictionResult = nil
        }

        if restrictionResult != nil {
            do {
                try await reconcileLiveActivity(
                    rules,
                    liveActivityLocationConditions
                )
            } catch {
                failures.append(.liveActivity)
            }
        }

        return AppLifecycleRecoveryResult(
            recoveredRuleIDs: recoveredRuleIDs,
            failures: failures,
            authorization: authorization,
            presentationState: Self.presentationState(
                authorization: authorization,
                restrictionResult: restrictionResult,
                hasConfiguredRules: !rules.isEmpty
            )
        )
    }

    @MainActor
    static func live(
        container: DependencyContainer,
        bundle: Bundle = .main,
        authorizationProvider: any AuthorizationProviding = SystemAuthorizationProvider(),
        reconcileLiveActivity: @escaping LiveActivityReconcile = { _, _ in }
    ) throws -> AppLifecycleCoordinator {
        let restrictionCoordinator = try container.makeRestrictionCoordinator(
            bundle: bundle,
            authorizationProvider: authorizationProvider
        )

        return AppLifecycleCoordinator(
            ruleRepository: container.ruleRepository,
            scheduleManager: DeviceActivityScheduleAdapter(),
            locationMonitor: container.makeLocationMonitor(),
            authorizationProvider: authorizationProvider,
            ensureMonthlyAllowance: container.ensureMonthlyAllowanceOnForeground,
            restoreRestriction: {
                try await restrictionCoordinator.restore()
            },
            loadPersistedLocationConditions: { rules in
                try await container.sharedSnapshotRepository
                    .loadLocationConditions(matching: rules)
            },
            reconcileLiveActivity: reconcileLiveActivity
        )
    }

    private static func isFreshExtensionEvidence(
        _ condition: LocationConditionSnapshot,
        for rule: RestrictionRuleSnapshot,
        now: Date
    ) -> Bool {
        guard
            condition.ruleID == rule.id,
            condition.ruleRevision == rule.revision,
            condition.source == .regionEvent
        else {
            return false
        }

        let age = now.timeIntervalSince(condition.observedAt)
        return age >= 0 && age <= maximumExtensionEvidenceAge
    }

    private static func presentationState(
        authorization: AuthorizationSnapshot,
        restrictionResult: RestrictionCoordinationResult?,
        hasConfiguredRules: Bool
    ) -> RestrictionPresentationState? {
        let missingPermissions = missingPermissions(in: authorization)
        if !missingPermissions.isEmpty {
            return .permissionRequired(missingPermissions: missingPermissions)
        }

        guard let restrictionResult else {
            return nil
        }

        if restrictionResult.decisions.values.contains(where: { decision in
            if case .locationUnavailable = decision.presentationState {
                return true
            }
            return false
        }) == true {
            return .locationUnavailable(
                isRestrictionApplied: restrictionResult.appliedState.isApplied
            )
        }

        if restrictionResult.appliedState.isApplied {
            return .active
        }
        return hasConfiguredRules ? .inactive : .configurationRequired
    }

    private static func missingPermissions(
        in authorization: AuthorizationSnapshot
    ) -> Set<RequiredPermission> {
        var result: Set<RequiredPermission> = []
        if authorization.familyControls != .approved {
            result.insert(.familyControls)
        }
        if authorization.locationAuthorization != .always {
            result.insert(.alwaysLocation)
        }
        if authorization.locationAccuracy != .full {
            result.insert(.fullAccuracy)
        }
        return result
    }

    private static func ruleOrder(
        _ lhs: RestrictionRuleSnapshot,
        _ rhs: RestrictionRuleSnapshot
    ) -> Bool {
        lhs.id.uuidString < rhs.id.uuidString
    }
}
