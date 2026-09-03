import Foundation
import Testing
@testable import GetUp

@Suite("Restriction coordinator")
struct RestrictionCoordinatorTests {
    @Test("A time event applies every rule whose time and location are active")
    func timeEventAppliesAllSatisfiedRules() async throws {
        let first = TestFixtures.makeRule()
        let second = TestFixtures.makeRule(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000201")!,
            revision: 3
        )
        let adapter = RecordingRestrictionAdapter()
        let coordinator = makeCoordinator(
            rules: [first, second],
            conditions: [
                TestFixtures.makeLocationCondition(
                    ruleID: first.id,
                    ruleRevision: first.revision
                ),
                TestFixtures.makeLocationCondition(
                    ruleID: second.id,
                    ruleRevision: second.revision
                ),
            ],
            adapter: adapter
        )

        let result = try await coordinator.handleTimeEvent()

        #expect(result.decisions[first.id]?.reason == .conditionsSatisfied)
        #expect(result.decisions[second.id]?.reason == .conditionsSatisfied)
        #expect(result.appliedState.activeRuleRevisions == identities([first, second]))
        #expect(await adapter.appliedRuleIDs == Set([first.id, second.id]))
        #expect(await adapter.applyCount == 1)
    }

    @Test("A location event recomputes the union and removes only an ended rule")
    func locationEventPartiallyReleasesUnion() async throws {
        let first = TestFixtures.makeRule()
        let second = TestFixtures.makeRule(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000202")!,
            revision: 2
        )
        let adapter = RecordingRestrictionAdapter(initialRules: [first, second])
        let coordinator = makeCoordinator(
            rules: [first, second],
            conditions: [
                TestFixtures.makeLocationCondition(
                    ruleID: first.id,
                    state: .outside
                ),
                TestFixtures.makeLocationCondition(
                    ruleID: second.id,
                    ruleRevision: second.revision
                ),
            ],
            adapter: adapter
        )

        let result = try await coordinator.handleLocationEvent(ruleID: first.id)

        #expect(result.appliedState.activeRuleRevisions == identities([second]))
        #expect(result.transitionMeasurement?.effect == .removeShield)
        #expect(result.transitionMeasurement?.eventConfirmedAt == TestFixtures.now)
        #expect(await adapter.appliedRuleIDs == [second.id])
        #expect(await adapter.removeCount == 0)
    }

    @Test("Unavailable evidence preserves only a matching previously active rule")
    func unavailableLocationPreservesMatchingActiveRuleOnly() async throws {
        let preserved = TestFixtures.makeRule()
        let neverApplied = TestFixtures.makeRule(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000203")!
        )
        let adapter = RecordingRestrictionAdapter(initialRules: [preserved])
        let coordinator = makeCoordinator(
            rules: [preserved, neverApplied],
            conditions: [],
            adapter: adapter
        )

        let result = try await coordinator.restore()

        #expect(result.appliedState.activeRuleRevisions == identities([preserved]))
        #expect(result.transitionMeasurement == nil)
        #expect(await adapter.applyCount == 1)
        #expect(await adapter.removeCount == 0)
    }

    @Test("The same active revision still requests idempotent store reconciliation")
    func repeatedEvaluationReconcilesAdapterWithoutLogicalTransition() async throws {
        let rule = TestFixtures.makeRule()
        let adapter = RecordingRestrictionAdapter(initialRules: [rule])
        let coordinator = makeCoordinator(
            rules: [rule],
            conditions: [TestFixtures.makeLocationCondition(ruleID: rule.id)],
            adapter: adapter
        )

        let result = try await coordinator.handleTimeEvent()

        #expect(result.transitionMeasurement == nil)
        #expect(await adapter.applyCount == 1)
        #expect(await adapter.removeCount == 0)
    }

    @Test("An active state reasserts a shield that the system store lost")
    func activeStateReassertsMissingShield() async throws {
        let rule = TestFixtures.makeRule()
        let adapter = RecordingRestrictionAdapter(
            initialRules: [rule],
            isShieldPresent: false
        )
        let coordinator = makeCoordinator(
            rules: [rule],
            conditions: [TestFixtures.makeLocationCondition(ruleID: rule.id)],
            adapter: adapter
        )

        let result = try await coordinator.restore()

        #expect(result.appliedState.activeRuleRevisions == identities([rule]))
        #expect(result.transitionMeasurement == nil)
        #expect(await adapter.applyCount == 1)
        #expect(await adapter.isShieldPresent)
    }

    @Test("Applied rules persist deterministic occurrence intervals")
    func appliedRulesPersistDeterministicOccurrences() async throws {
        let first = TestFixtures.makeRule()
        let second = TestFixtures.makeRule(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000204")!,
            revision: 2
        )
        let snapshotRepository = CoordinatorActiveRestrictionRepository()
        let coordinator = makeCoordinator(
            rules: [second, first],
            conditions: [
                TestFixtures.makeLocationCondition(
                    ruleID: second.id,
                    ruleRevision: second.revision
                ),
                TestFixtures.makeLocationCondition(ruleID: first.id),
            ],
            adapter: RecordingRestrictionAdapter(),
            activeRestrictionSnapshotRepository: snapshotRepository
        )

        _ = try await coordinator.handleTimeEvent()

        let snapshot = try #require(await snapshotRepository.snapshot)
        #expect(snapshot.revision == 1)
        #expect(snapshot.observedAt == TestFixtures.now)
        #expect(snapshot.occurrences.map(\.ruleID) == [first.id, second.id])
        #expect(snapshot.occurrences.allSatisfy { occurrence in
            occurrence.startAt == date(hour: 6)
                && occurrence.endAt == date(hour: 9)
                && occurrence.activatedAt == TestFixtures.now
                && occurrence.id == RestrictionOccurrence.deterministicID(
                    ruleID: occurrence.ruleID,
                    ruleRevision: occurrence.ruleRevision,
                    startAt: occurrence.startAt,
                    endAt: occurrence.endAt
                )
        })
    }

    @Test("Repeated evaluation preserves activation time and snapshot revision")
    func repeatedEvaluationPreservesOccurrenceIdentity() async throws {
        let rule = TestFixtures.makeRule()
        let clock = LiveActivityCoinWallClock(now: TestFixtures.now)
        let snapshotRepository = CoordinatorActiveRestrictionRepository()
        let coordinator = makeCoordinator(
            rules: [rule],
            conditions: [TestFixtures.makeLocationCondition(ruleID: rule.id)],
            adapter: RecordingRestrictionAdapter(),
            activeRestrictionSnapshotRepository: snapshotRepository,
            clock: clock
        )

        _ = try await coordinator.handleTimeEvent()
        let first = try #require(await snapshotRepository.snapshot)
        clock.advance(by: 5 * 60)
        _ = try await coordinator.handleTimeEvent()
        let repeated = try #require(await snapshotRepository.snapshot)

        #expect(repeated.revision == first.revision)
        #expect(repeated.occurrences == first.occurrences)
        #expect(repeated.observedAt == TestFixtures.now.addingTimeInterval(5 * 60))
    }

    @Test("Removing the final applied rule persists an incremented empty snapshot")
    func removalPersistsEmptyOccurrenceSnapshot() async throws {
        let rule = TestFixtures.makeRule()
        let existingOccurrence = try RestrictionOccurrence(
            ruleID: rule.id,
            ruleRevision: rule.revision,
            startAt: date(hour: 6),
            endAt: date(hour: 9),
            activatedAt: TestFixtures.now.addingTimeInterval(-60)
        )
        let snapshotRepository = CoordinatorActiveRestrictionRepository(
            snapshot: try ActiveRestrictionSnapshot(
                revision: 4,
                occurrences: [existingOccurrence],
                observedAt: TestFixtures.now.addingTimeInterval(-60)
            )
        )
        let coordinator = makeCoordinator(
            rules: [rule],
            conditions: [
                TestFixtures.makeLocationCondition(
                    ruleID: rule.id,
                    state: .outside
                ),
            ],
            adapter: RecordingRestrictionAdapter(initialRules: [rule]),
            activeRestrictionSnapshotRepository: snapshotRepository
        )

        _ = try await coordinator.handleLocationEvent(ruleID: rule.id)

        let snapshot = try #require(await snapshotRepository.snapshot)
        #expect(snapshot.revision == 5)
        #expect(snapshot.occurrences.isEmpty)
        #expect(snapshot.observedAt == TestFixtures.now)
    }

    private func makeCoordinator(
        rules: [RestrictionRuleSnapshot],
        conditions: [LocationConditionSnapshot],
        adapter: RecordingRestrictionAdapter,
        activeRestrictionSnapshotRepository: CoordinatorActiveRestrictionRepository =
            CoordinatorActiveRestrictionRepository(),
        clock: any Clock = FixedClock(now: TestFixtures.now)
    ) -> RestrictionCoordinator {
        RestrictionCoordinator(
            ruleRepository: CoordinatorRuleRepository(rules: rules),
            locationConditionRepository: CoordinatorLocationRepository(
                conditions: conditions
            ),
            authorizationProvider: ApprovedAuthorizationProvider(),
            restrictionAdapter: adapter,
            activeRestrictionSnapshotRepository: activeRestrictionSnapshotRepository,
            clock: clock,
            calendar: TestFixtures.calendar,
            timeZone: TestFixtures.timeZone
        )
    }

    private func identities(
        _ rules: [RestrictionRuleSnapshot]
    ) -> Set<ActiveRuleRevision> {
        Set(rules.map { ActiveRuleRevision(ruleID: $0.id, revision: $0.revision) })
    }

    private func date(hour: Int) -> Date {
        TestFixtures.calendar.date(
            bySettingHour: hour,
            minute: 0,
            second: 0,
            of: TestFixtures.now
        )!
    }
}

private actor CoordinatorActiveRestrictionRepository:
    ActiveRestrictionSnapshotRepository
{
    private(set) var snapshot: ActiveRestrictionSnapshot?

    init(snapshot: ActiveRestrictionSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func loadActiveRestrictionSnapshot() -> ActiveRestrictionSnapshot? {
        snapshot
    }

    func saveActiveRestrictionSnapshot(_ snapshot: ActiveRestrictionSnapshot) {
        self.snapshot = snapshot
    }
}

private actor CoordinatorRuleRepository: RuleRepository {
    private var collection: RestrictionRuleCollectionSnapshot?

    init(rules: [RestrictionRuleSnapshot]) {
        collection = RestrictionRuleCollectionSnapshot(revision: 1, rules: rules)
    }

    func loadRuleCollection() -> RestrictionRuleCollectionSnapshot? { collection }
    func saveRuleCollection(_ collection: RestrictionRuleCollectionSnapshot) {
        self.collection = collection
    }
    func deleteRuleCollection() { collection = nil }
}

private actor CoordinatorLocationRepository: LocationConditionRepository {
    private var collection: LocationConditionCollectionSnapshot?

    init(conditions: [LocationConditionSnapshot]) {
        collection = LocationConditionCollectionSnapshot(conditions: conditions)
    }

    func loadLocationConditionCollection() -> LocationConditionCollectionSnapshot? {
        collection
    }

    func saveLocationCondition(_ condition: LocationConditionSnapshot) {
        var conditions = collection?.conditions ?? []
        conditions.removeAll { $0.ruleID == condition.ruleID }
        conditions.append(condition)
        collection = LocationConditionCollectionSnapshot(conditions: conditions)
    }

    func deleteLocationCondition(for ruleID: UUID) {
        collection = LocationConditionCollectionSnapshot(
            conditions: collection?.conditions.filter { $0.ruleID != ruleID } ?? []
        )
    }

    func deleteLocationConditions() { collection = nil }
}

private struct ApprovedAuthorizationProvider: AuthorizationProviding {
    func authorizationSnapshot() -> AuthorizationSnapshot {
        TestFixtures.makeAuthorization()
    }
}

private actor RecordingRestrictionAdapter: RestrictionApplying {
    private var state: AppliedRestrictionState
    private(set) var appliedRuleIDs: Set<UUID>
    private(set) var applyCount = 0
    private(set) var removeCount = 0
    private(set) var isShieldPresent: Bool

    init(
        initialRules: [RestrictionRuleSnapshot] = [],
        isShieldPresent: Bool? = nil
    ) {
        state = AppliedRestrictionState(
            activeRuleRevisions: Set(
                initialRules.map {
                    ActiveRuleRevision(ruleID: $0.id, revision: $0.revision)
                }
            )
        )
        appliedRuleIDs = Set(initialRules.map(\.id))
        self.isShieldPresent = isShieldPresent ?? !initialRules.isEmpty
    }

    func currentAppliedState() -> AppliedRestrictionState { state }

    func applyRestriction(for rules: [RestrictionRuleSnapshot]) {
        applyCount += 1
        isShieldPresent = true
        appliedRuleIDs = Set(rules.map(\.id))
        state = AppliedRestrictionState(
            activeRuleRevisions: Set(
                rules.map {
                    ActiveRuleRevision(ruleID: $0.id, revision: $0.revision)
                }
            )
        )
    }

    func removeRestriction() {
        removeCount += 1
        isShieldPresent = false
        appliedRuleIDs = []
        state = AppliedRestrictionState(activeRuleRevisions: [])
    }
}
