import Foundation
import Testing
@testable import GetUp

@Suite("App lifecycle recovery coordinator")
struct AppLifecycleCoordinatorTests {
    @Test("Recovery rebuilds schedules, regions, locations, then restriction state")
    func restoresEveryEnabledRule() async throws {
        let enabled = TestFixtures.makeRule()
        let disabled = TestFixtures.makeRule(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000301")!,
            isEnabled: false
        )
        let schedule = RecoveryScheduleManager()
        let location = RecoveryLocationMonitor()
        let authorization = TestFixtures.makeAuthorization()
        let restriction = RecoveryRestrictionRecorder(
            result: restrictionResult(for: enabled, presentationState: .active)
        )
        let coordinator = AppLifecycleCoordinator(
            ruleRepository: RecoveryRuleRepository(rules: [enabled, disabled]),
            scheduleManager: schedule,
            locationMonitor: location,
            authorizationProvider: RecoveryAuthorizationProvider(
                snapshot: authorization
            ),
            restoreRestriction: { try await restriction.restore() }
        )

        let result = try await coordinator.restore()

        #expect(await schedule.didRemoveAll)
        #expect(await schedule.replacedRuleIDs == [enabled.id])
        #expect(await location.didStopAll)
        #expect(await location.replacedRuleIDs == [enabled.id])
        #expect(await location.refreshedRuleIDs == [enabled.id])
        #expect(await restriction.restoreCount == 1)
        #expect(result.recoveredRuleIDs == [enabled.id])
        #expect(result.failures.isEmpty)
        #expect(result.authorization == authorization)
        #expect(result.presentationState == .active)
    }

    @Test("A platform registration failure does not skip restriction reconciliation")
    func bestEffortRecoveryStillReconcilesRestriction() async throws {
        let rule = TestFixtures.makeRule()
        let schedule = RecoveryScheduleManager(shouldFailReplacement: true)
        let location = RecoveryLocationMonitor(shouldFailReplacement: true)
        let restriction = RecoveryRestrictionRecorder(
            result: restrictionResult(for: rule, presentationState: .inactive)
        )
        let coordinator = AppLifecycleCoordinator(
            ruleRepository: RecoveryRuleRepository(rules: [rule]),
            scheduleManager: schedule,
            locationMonitor: location,
            authorizationProvider: RecoveryAuthorizationProvider(),
            restoreRestriction: { try await restriction.restore() }
        )

        let result = try await coordinator.restore()

        #expect(await restriction.restoreCount == 1)
        #expect(result.failures == [.schedule(ruleID: rule.id), .location(ruleID: rule.id)])
    }

    @Test("An unreadable protected snapshot preserves registrations and restriction state")
    func protectedSnapshotFailurePerformsNoRecoveryWrites() async {
        let schedule = RecoveryScheduleManager()
        let location = RecoveryLocationMonitor()
        let restriction = RecoveryRestrictionRecorder()
        let coordinator = AppLifecycleCoordinator(
            ruleRepository: RecoveryRuleRepository(rules: [], shouldFailLoad: true),
            scheduleManager: schedule,
            locationMonitor: location,
            authorizationProvider: RecoveryAuthorizationProvider(),
            restoreRestriction: { try await restriction.restore() }
        )

        do {
            _ = try await coordinator.restore()
            Issue.record("보호된 snapshot read 실패가 전달되어야 합니다.")
        } catch {
            #expect(await schedule.didRemoveAll == false)
            #expect(await location.didStopAll == false)
            #expect(await restriction.restoreCount == 0)
        }
    }

    @Test("Recovery reports permission changes before restriction presentation")
    func reportsLatestAuthorizationForPermissionGuidance() async throws {
        let rule = TestFixtures.makeRule()
        let authorization = TestFixtures.makeAuthorization(
            familyControls: .denied,
            locationAuthorization: .whenInUse,
            locationAccuracy: .reduced,
            backgroundRefresh: .restricted
        )
        let coordinator = AppLifecycleCoordinator(
            ruleRepository: RecoveryRuleRepository(rules: [rule]),
            scheduleManager: RecoveryScheduleManager(),
            locationMonitor: RecoveryLocationMonitor(),
            authorizationProvider: RecoveryAuthorizationProvider(
                snapshot: authorization
            ),
            restoreRestriction: {
                restrictionResult(
                    for: rule,
                    presentationState: .locationUnavailable(
                        isRestrictionApplied: true
                    )
                )
            }
        )

        let result = try await coordinator.restore()

        #expect(result.authorization == authorization)
        #expect(result.presentationState == .permissionRequired(
            missingPermissions: [
                .familyControls,
                .alwaysLocation,
                .fullAccuracy,
            ]
        ))
    }

    @Test("A restriction reconciliation failure does not invent a presentation state")
    func restrictionFailureDoesNotInferPresentation() async throws {
        let rule = TestFixtures.makeRule()
        let restriction = RecoveryRestrictionRecorder(shouldFail: true)
        let coordinator = AppLifecycleCoordinator(
            ruleRepository: RecoveryRuleRepository(rules: [rule]),
            scheduleManager: RecoveryScheduleManager(),
            locationMonitor: RecoveryLocationMonitor(),
            authorizationProvider: RecoveryAuthorizationProvider(),
            restoreRestriction: { try await restriction.restore() }
        )

        let result = try await coordinator.restore()

        #expect(result.failures == [.restriction])
        #expect(result.presentationState == nil)
    }

    @Test("Foreground recovery triggers monthly allowance creation once")
    func foregroundRecoveryEnsuresMonthlyAllowance() async throws {
        let allowance = RecoveryMonthlyAllowanceRecorder()
        let coordinator = AppLifecycleCoordinator(
            ruleRepository: RecoveryRuleRepository(rules: []),
            scheduleManager: RecoveryScheduleManager(),
            locationMonitor: RecoveryLocationMonitor(),
            authorizationProvider: RecoveryAuthorizationProvider(),
            ensureMonthlyAllowance: { try await allowance.ensure() },
            restoreRestriction: { restrictionResult(for: TestFixtures.makeRule(), presentationState: .inactive) }
        )

        let result = try await coordinator.restore()

        #expect(await allowance.ensureCount == 1)
        #expect(result.failures.isEmpty)
    }

    @Test("Monthly allowance failure is reported without skipping restriction recovery")
    func allowanceFailureDoesNotSkipRestrictionRecovery() async throws {
        let allowance = RecoveryMonthlyAllowanceRecorder(shouldFail: true)
        let restriction = RecoveryRestrictionRecorder()
        let coordinator = AppLifecycleCoordinator(
            ruleRepository: RecoveryRuleRepository(rules: []),
            scheduleManager: RecoveryScheduleManager(),
            locationMonitor: RecoveryLocationMonitor(),
            authorizationProvider: RecoveryAuthorizationProvider(),
            ensureMonthlyAllowance: { try await allowance.ensure() },
            restoreRestriction: { try await restriction.restore() }
        )

        let result = try await coordinator.restore()

        #expect(await restriction.restoreCount == 1)
        #expect(result.failures == [.monthlyAllowance])
    }

    private func restrictionResult(
        for rule: RestrictionRuleSnapshot,
        presentationState: RestrictionPresentationState
    ) -> RestrictionCoordinationResult {
        let appliedState = AppliedRestrictionState(
            activeRuleRevisions: presentationState == .active
                ? [ActiveRuleRevision(ruleID: rule.id, revision: rule.revision)]
                : []
        )
        return RestrictionCoordinationResult(
            event: .restoration,
            decisions: [
                rule.id: EvaluationDecision(
                    presentationState: presentationState,
                    desiredRestriction: presentationState == .active ? .active : .preserve,
                    effect: .none,
                    reason: presentationState == .active
                        ? .conditionsSatisfied
                        : .locationUnavailable
                ),
            ],
            appliedState: appliedState,
            transitionMeasurement: nil
        )
    }
}

private actor RecoveryRuleRepository: RuleRepository {
    private var collection: RestrictionRuleCollectionSnapshot?
    private let shouldFailLoad: Bool

    init(
        rules: [RestrictionRuleSnapshot],
        shouldFailLoad: Bool = false
    ) {
        collection = RestrictionRuleCollectionSnapshot(revision: 1, rules: rules)
        self.shouldFailLoad = shouldFailLoad
    }

    func loadRuleCollection() throws -> RestrictionRuleCollectionSnapshot? {
        if shouldFailLoad { throw RecoveryFailure.expected }
        return collection
    }
    func saveRuleCollection(_ collection: RestrictionRuleCollectionSnapshot) {
        self.collection = collection
    }
    func deleteRuleCollection() { collection = nil }
}

private actor RecoveryScheduleManager: ScheduleManaging {
    private(set) var didRemoveAll = false
    private(set) var replacedRuleIDs: [UUID] = []
    private let shouldFailReplacement: Bool

    init(shouldFailReplacement: Bool = false) {
        self.shouldFailReplacement = shouldFailReplacement
    }

    func replaceSchedules(for rule: RestrictionRuleSnapshot) throws {
        if shouldFailReplacement { throw RecoveryFailure.expected }
        replacedRuleIDs.append(rule.id)
    }

    func removeSchedules() { didRemoveAll = true }
}

private actor RecoveryLocationMonitor: LocationMonitoring {
    private(set) var didStopAll = false
    private(set) var replacedRuleIDs: [UUID] = []
    private(set) var refreshedRuleIDs: [UUID] = []
    private let shouldFailReplacement: Bool

    init(shouldFailReplacement: Bool = false) {
        self.shouldFailReplacement = shouldFailReplacement
    }

    func replaceMonitoring(for rule: RestrictionRuleSnapshot) throws {
        if shouldFailReplacement { throw RecoveryFailure.expected }
        replacedRuleIDs.append(rule.id)
    }

    func stopMonitoring() { didStopAll = true }

    func refreshLocationCondition(
        for rule: RestrictionRuleSnapshot,
        source: LocationConditionSource
    ) -> LocationConditionSnapshot {
        refreshedRuleIDs.append(rule.id)
        return TestFixtures.makeLocationCondition(
            ruleID: rule.id,
            ruleRevision: rule.revision,
            source: source
        )
    }
}

private struct RecoveryAuthorizationProvider: AuthorizationProviding {
    let snapshot: AuthorizationSnapshot

    init(snapshot: AuthorizationSnapshot = TestFixtures.makeAuthorization()) {
        self.snapshot = snapshot
    }

    func authorizationSnapshot() -> AuthorizationSnapshot { snapshot }
}

private actor RecoveryRestrictionRecorder {
    private(set) var restoreCount = 0
    private let result: RestrictionCoordinationResult
    private let shouldFail: Bool

    init(
        result: RestrictionCoordinationResult = RestrictionCoordinationResult(
            event: .restoration,
            decisions: [:],
            appliedState: AppliedRestrictionState(activeRuleRevisions: []),
            transitionMeasurement: nil
        ),
        shouldFail: Bool = false
    ) {
        self.result = result
        self.shouldFail = shouldFail
    }

    func restore() throws -> RestrictionCoordinationResult {
        restoreCount += 1
        if shouldFail {
            throw RecoveryFailure.expected
        }
        return result
    }
}

private actor RecoveryMonthlyAllowanceRecorder {
    private(set) var ensureCount = 0
    private let shouldFail: Bool

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func ensure() throws {
        ensureCount += 1
        if shouldFail {
            throw RecoveryFailure.expected
        }
    }
}

private enum RecoveryFailure: Error {
    case expected
}
