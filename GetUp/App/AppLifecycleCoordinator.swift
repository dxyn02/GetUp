import Foundation

enum AppLifecycleRecoveryFailure: Equatable, Sendable {
    case scheduleReset
    case locationReset
    case schedule(ruleID: UUID)
    case location(ruleID: UUID)
    case restriction
}

struct AppLifecycleRecoveryResult: Equatable, Sendable {
    let recoveredRuleIDs: [UUID]
    let failures: [AppLifecycleRecoveryFailure]
}

actor AppLifecycleCoordinator {
    typealias RestrictionRestore = @Sendable () async throws -> Void

    private let ruleRepository: any RuleRepository
    private let scheduleManager: any ScheduleManaging
    private let locationMonitor: any LocationMonitoring
    private let restoreRestriction: RestrictionRestore

    init(
        ruleRepository: any RuleRepository,
        scheduleManager: any ScheduleManaging,
        locationMonitor: any LocationMonitoring,
        restoreRestriction: @escaping RestrictionRestore
    ) {
        self.ruleRepository = ruleRepository
        self.scheduleManager = scheduleManager
        self.locationMonitor = locationMonitor
        self.restoreRestriction = restoreRestriction
    }

    func restore() async throws -> AppLifecycleRecoveryResult {
        let rules = try await ruleRepository.loadRuleCollection()?.rules ?? []
        let enabledRules = rules.filter(\.isEnabled).sorted(by: Self.ruleOrder)
        var failures: [AppLifecycleRecoveryFailure] = []
        var recoveredRuleIDs: [UUID] = []

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

            do {
                try await scheduleManager.replaceSchedules(for: rule)
            } catch {
                recoveredSchedule = false
                failures.append(.schedule(ruleID: rule.id))
            }

            do {
                try await locationMonitor.replaceMonitoring(for: rule)
                _ = await locationMonitor.refreshLocationCondition(
                    for: rule,
                    source: .restoration
                )
            } catch {
                recoveredLocation = false
                failures.append(.location(ruleID: rule.id))
            }

            if recoveredSchedule && recoveredLocation {
                recoveredRuleIDs.append(rule.id)
            }
        }

        do {
            try await restoreRestriction()
        } catch {
            failures.append(.restriction)
        }

        return AppLifecycleRecoveryResult(
            recoveredRuleIDs: recoveredRuleIDs,
            failures: failures
        )
    }

    @MainActor
    static func live(
        container: DependencyContainer,
        bundle: Bundle = .main
    ) throws -> AppLifecycleCoordinator {
        let authorizationProvider = SystemAuthorizationProvider()
        let restrictionAdapter = try ManagedSettingsRestrictionAdapter.live(
            bundle: bundle
        )
        let restrictionCoordinator = RestrictionCoordinator(
            ruleRepository: container.ruleRepository,
            locationConditionRepository: container.locationConditionRepository,
            authorizationProvider: authorizationProvider,
            restrictionAdapter: restrictionAdapter
        )

        return AppLifecycleCoordinator(
            ruleRepository: container.ruleRepository,
            scheduleManager: DeviceActivityScheduleAdapter(),
            locationMonitor: container.makeLocationMonitor(),
            restoreRestriction: {
                _ = try await restrictionCoordinator.restore()
            }
        )
    }

    private static func ruleOrder(
        _ lhs: RestrictionRuleSnapshot,
        _ rhs: RestrictionRuleSnapshot
    ) -> Bool {
        lhs.id.uuidString < rhs.id.uuidString
    }
}
