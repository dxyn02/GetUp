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
        let events = RecoveryLifecycleEventRecorder()
        let coordinator = AppLifecycleCoordinator(
            ruleRepository: RecoveryRuleRepository(rules: [rule]),
            scheduleManager: RecoveryScheduleManager(),
            locationMonitor: RecoveryLocationMonitor(),
            authorizationProvider: RecoveryAuthorizationProvider(),
            restoreRestriction: { try await restriction.restore() },
            reconcileLiveActivity: { _, _ in
                await events.record(.liveActivity([rule.id]))
            }
        )

        let result = try await coordinator.restore()

        #expect(result.failures == [.restriction])
        #expect(result.presentationState == nil)
        #expect(await events.events.isEmpty)
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

    @Test("Foreground recovery reconciles Live Activity after restriction state")
    func foregroundRecoveryReconcilesLiveActivityLast() async throws {
        let rule = TestFixtures.makeRule()
        let events = RecoveryLifecycleEventRecorder()
        let coordinator = AppLifecycleCoordinator(
            ruleRepository: RecoveryRuleRepository(rules: [rule]),
            scheduleManager: RecoveryScheduleManager(),
            locationMonitor: RecoveryLocationMonitor(),
            authorizationProvider: RecoveryAuthorizationProvider(),
            restoreRestriction: {
                await events.record(.restriction)
                return restrictionResult(for: rule, presentationState: .active)
            },
            reconcileLiveActivity: { rules, _ in
                await events.record(.liveActivity(rules.map(\.id)))
            }
        )

        let result = try await coordinator.restore()

        #expect(result.failures.isEmpty)
        #expect(await events.events == [
            .restriction,
            .liveActivity([rule.id]),
        ])
    }

    @Test("Live Activity failure is isolated from foreground recovery")
    func liveActivityFailureIsNonFatal() async throws {
        let rule = TestFixtures.makeRule()
        let coordinator = AppLifecycleCoordinator(
            ruleRepository: RecoveryRuleRepository(rules: [rule]),
            scheduleManager: RecoveryScheduleManager(),
            locationMonitor: RecoveryLocationMonitor(),
            authorizationProvider: RecoveryAuthorizationProvider(),
            restoreRestriction: {
                restrictionResult(for: rule, presentationState: .active)
            },
            reconcileLiveActivity: { _, _ in
                throw RecoveryFailure.expected
            }
        )

        let result = try await coordinator.restore()

        #expect(result.failures == [.liveActivity])
        #expect(result.presentationState == .active)
    }

    @Test("Fresh extension evidence is consumed before foreground refresh")
    func foregroundConsumesFreshExtensionEvidence() async throws {
        let rule = TestFixtures.makeRule(revision: 4)
        let extensionEvidence = TestFixtures.makeLocationCondition(
            ruleID: rule.id,
            ruleRevision: rule.revision,
            observedAt: TestFixtures.now.addingTimeInterval(-300),
            source: .regionEvent
        )
        let location = RecoveryLocationMonitor()
        let liveActivity = RecoveryLiveActivityRecorder()
        let coordinator = AppLifecycleCoordinator(
            ruleRepository: RecoveryRuleRepository(rules: [rule]),
            scheduleManager: RecoveryScheduleManager(),
            locationMonitor: location,
            authorizationProvider: RecoveryAuthorizationProvider(),
            restoreRestriction: {
                restrictionResult(for: rule, presentationState: .active)
            },
            loadPersistedLocationConditions: { _ in [extensionEvidence] },
            reconcileLiveActivity: { _, conditions in
                await liveActivity.record(conditions)
            },
            clock: FixedClock(now: TestFixtures.now)
        )

        let result = try await coordinator.restore()

        #expect(result.failures.isEmpty)
        #expect(await location.refreshedRuleIDs.isEmpty)
        #expect(await liveActivity.locationConditions == [extensionEvidence])
    }

    @Test("Stale extension evidence falls back to foreground refresh")
    func staleExtensionEvidenceRefreshesLocation() async throws {
        let rule = TestFixtures.makeRule(revision: 4)
        let staleEvidence = TestFixtures.makeLocationCondition(
            ruleID: rule.id,
            ruleRevision: rule.revision,
            observedAt: TestFixtures.now.addingTimeInterval(-301),
            source: .regionEvent
        )
        let location = RecoveryLocationMonitor()
        let liveActivity = RecoveryLiveActivityRecorder()
        let coordinator = AppLifecycleCoordinator(
            ruleRepository: RecoveryRuleRepository(rules: [rule]),
            scheduleManager: RecoveryScheduleManager(),
            locationMonitor: location,
            authorizationProvider: RecoveryAuthorizationProvider(),
            restoreRestriction: {
                restrictionResult(for: rule, presentationState: .active)
            },
            loadPersistedLocationConditions: { _ in [staleEvidence] },
            reconcileLiveActivity: { _, conditions in
                await liveActivity.record(conditions)
            },
            clock: FixedClock(now: TestFixtures.now)
        )

        let result = try await coordinator.restore()

        #expect(result.failures.isEmpty)
        #expect(await location.refreshedRuleIDs == [rule.id])
        #expect(await liveActivity.locationConditions.first?.source == .restoration)
    }

    @Test("Live Activity snapshot uses the representative rule and trusted distance")
    func buildsRepresentativeLiveActivitySnapshot() throws {
        let rule = TestFixtures.makeRule(name: nil)
        let place = SavedPlaceSnapshot(
            id: rule.savedPlaceID,
            name: "집",
            coordinate: ReferenceLocation(latitude: 37.5, longitude: 127.0),
            createdAt: TestFixtures.now,
            updatedAt: TestFixtures.now
        )
        let occurrence = try RestrictionOccurrence(
            ruleID: rule.id,
            ruleRevision: rule.revision,
            startAt: TestFixtures.now.addingTimeInterval(-60),
            endAt: TestFixtures.now.addingTimeInterval(3_600),
            activatedAt: TestFixtures.now.addingTimeInterval(-30)
        )
        let activeSnapshot = try ActiveRestrictionSnapshot(
            revision: 1,
            occurrences: [occurrence],
            observedAt: TestFixtures.now
        )

        let desiredSnapshot = try AppLiveActivityRecovery.makeSnapshot(
            rules: [rule],
            savedPlaces: [place],
            activeSnapshot: activeSnapshot,
            locationConditions: [TestFixtures.makeLocationCondition()],
            now: TestFixtures.now
        )
        let snapshot = try #require(desiredSnapshot)

        #expect(snapshot.attributes.activityID == rule.id)
        #expect(snapshot.attributes.restrictionStartedAt == occurrence.activatedAt)
        #expect(snapshot.contentState.occurrenceID == occurrence.id)
        #expect(snapshot.contentState.ruleDisplayName == place.name)
        #expect(snapshot.contentState.remainingDistance == .known(meters: 400))
        #expect(!snapshot.contentState.hasAdditionalRestrictions)
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

private actor RecoveryLifecycleEventRecorder {
    enum Event: Equatable, Sendable {
        case restriction
        case liveActivity([UUID])
    }

    private(set) var events: [Event] = []

    func record(_ event: Event) {
        events.append(event)
    }
}

private actor RecoveryLiveActivityRecorder {
    private(set) var locationConditions: [LocationConditionSnapshot] = []

    func record(_ conditions: [LocationConditionSnapshot]) {
        locationConditions = conditions
    }
}

private enum RecoveryFailure: Error {
    case expected
}
