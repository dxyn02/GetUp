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
        #expect(await adapter.applyCount == 0)
        #expect(await adapter.removeCount == 0)
    }

    @Test("The same active rule revision set is idempotent")
    func repeatedEvaluationHasNoAdapterEffect() async throws {
        let rule = TestFixtures.makeRule()
        let adapter = RecordingRestrictionAdapter(initialRules: [rule])
        let coordinator = makeCoordinator(
            rules: [rule],
            conditions: [TestFixtures.makeLocationCondition(ruleID: rule.id)],
            adapter: adapter
        )

        let result = try await coordinator.handleTimeEvent()

        #expect(result.transitionMeasurement == nil)
        #expect(await adapter.applyCount == 0)
        #expect(await adapter.removeCount == 0)
    }

    private func makeCoordinator(
        rules: [RestrictionRuleSnapshot],
        conditions: [LocationConditionSnapshot],
        adapter: RecordingRestrictionAdapter
    ) -> RestrictionCoordinator {
        RestrictionCoordinator(
            ruleRepository: CoordinatorRuleRepository(rules: rules),
            locationConditionRepository: CoordinatorLocationRepository(
                conditions: conditions
            ),
            authorizationProvider: ApprovedAuthorizationProvider(),
            restrictionAdapter: adapter,
            clock: FixedClock(now: TestFixtures.now),
            calendar: TestFixtures.calendar,
            timeZone: TestFixtures.timeZone
        )
    }

    private func identities(
        _ rules: [RestrictionRuleSnapshot]
    ) -> Set<ActiveRuleRevision> {
        Set(rules.map { ActiveRuleRevision(ruleID: $0.id, revision: $0.revision) })
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

    init(initialRules: [RestrictionRuleSnapshot] = []) {
        state = AppliedRestrictionState(
            activeRuleRevisions: Set(
                initialRules.map {
                    ActiveRuleRevision(ruleID: $0.id, revision: $0.revision)
                }
            )
        )
        appliedRuleIDs = Set(initialRules.map(\.id))
    }

    func currentAppliedState() -> AppliedRestrictionState { state }

    func applyRestriction(for rules: [RestrictionRuleSnapshot]) {
        applyCount += 1
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
        appliedRuleIDs = []
        state = AppliedRestrictionState(activeRuleRevisions: [])
    }
}
