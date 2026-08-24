import Foundation
import Testing
@testable import GetUp

@Suite("Restriction release")
struct RestrictionReleaseTests {
    @Test("A confirmed time end removes the active restriction and records its latency origin")
    func timeEndRemovesRestriction() async throws {
        let rule = TestFixtures.makeRule()
        let confirmedAt = inactiveDate
        let adapter = ReleaseRecordingAdapter(initialRule: rule)
        let coordinator = makeCoordinator(
            rule: rule,
            condition: TestFixtures.makeLocationCondition(
                ruleID: rule.id,
                state: .unavailable
            ),
            adapter: adapter,
            now: confirmedAt
        )

        let result = try await coordinator.handleTimeEvent(confirmedAt: confirmedAt)

        #expect(result.decisions[rule.id]?.effect == .removeShield)
        #expect(result.appliedState.activeRuleRevisions.isEmpty)
        #expect(result.transitionMeasurement?.effect == .removeShield)
        #expect(result.transitionMeasurement?.eventConfirmedAt == confirmedAt)
        #expect(result.transitionMeasurement?.effectCompletedAt == confirmedAt)
        #expect(result.transitionMeasurement?.latencySeconds == 0)
        #expect(await adapter.removeCount == 1)
    }

    @Test("A trustworthy outside fix removes the active restriction from its observation time")
    func outsideLocationRemovesRestriction() async throws {
        let rule = TestFixtures.makeRule()
        let observedAt = TestFixtures.now.addingTimeInterval(-4)
        let adapter = ReleaseRecordingAdapter(initialRule: rule)
        let coordinator = makeCoordinator(
            rule: rule,
            condition: TestFixtures.makeLocationCondition(
                ruleID: rule.id,
                state: .outside,
                observedAt: observedAt
            ),
            adapter: adapter
        )

        let result = try await coordinator.handleLocationEvent(
            ruleID: rule.id,
            confirmedAt: observedAt
        )

        #expect(result.decisions[rule.id]?.reason == .locationOutside)
        #expect(result.appliedState.activeRuleRevisions.isEmpty)
        #expect(result.transitionMeasurement?.effect == .removeShield)
        #expect(result.transitionMeasurement?.eventConfirmedAt == observedAt)
        #expect(result.transitionMeasurement?.effectCompletedAt == TestFixtures.now)
        #expect(result.transitionMeasurement?.latencySeconds == 4)
        #expect(await adapter.removeCount == 1)
    }

    @Test("Unavailable location evidence preserves an active restriction without a release measurement")
    func unavailableLocationPreservesRestriction() async throws {
        let rule = TestFixtures.makeRule()
        let confirmedAt = TestFixtures.now.addingTimeInterval(-3)
        let adapter = ReleaseRecordingAdapter(initialRule: rule)
        let coordinator = makeCoordinator(
            rule: rule,
            condition: TestFixtures.makeLocationCondition(
                ruleID: rule.id,
                state: .unavailable,
                observedAt: confirmedAt
            ),
            adapter: adapter
        )

        let result = try await coordinator.handleLocationEvent(
            ruleID: rule.id,
            confirmedAt: confirmedAt
        )

        #expect(result.decisions[rule.id]?.desiredRestriction == .preserve)
        #expect(result.appliedState.contains(rule))
        #expect(result.transitionMeasurement == nil)
        #expect(await adapter.removeCount == 0)
    }

    @Test("Repeated release evaluation does not remove or measure the same transition twice")
    func repeatedReleaseIsIdempotent() async throws {
        let rule = TestFixtures.makeRule()
        let confirmedAt = TestFixtures.now.addingTimeInterval(-2)
        let adapter = ReleaseRecordingAdapter(initialRule: rule)
        let coordinator = makeCoordinator(
            rule: rule,
            condition: TestFixtures.makeLocationCondition(
                ruleID: rule.id,
                state: .outside,
                observedAt: confirmedAt
            ),
            adapter: adapter
        )

        let first = try await coordinator.handleLocationEvent(
            ruleID: rule.id,
            confirmedAt: confirmedAt
        )
        let repeated = try await coordinator.handleLocationEvent(
            ruleID: rule.id,
            confirmedAt: confirmedAt
        )

        #expect(first.transitionMeasurement?.effect == .removeShield)
        #expect(repeated.transitionMeasurement == nil)
        #expect(await adapter.removeCount == 1)
    }

    private var inactiveDate: Date {
        TestFixtures.calendar.date(
            byAdding: .hour,
            value: 3,
            to: TestFixtures.now
        )!
    }

    private func makeCoordinator(
        rule: RestrictionRuleSnapshot,
        condition: LocationConditionSnapshot,
        adapter: ReleaseRecordingAdapter,
        now: Date = TestFixtures.now
    ) -> RestrictionCoordinator {
        RestrictionCoordinator(
            ruleRepository: ReleaseRuleRepository(rule: rule),
            locationConditionRepository: ReleaseLocationRepository(
                condition: condition
            ),
            authorizationProvider: ReleaseAuthorizationProvider(),
            restrictionAdapter: adapter,
            clock: FixedClock(now: now),
            calendar: TestFixtures.calendar,
            timeZone: TestFixtures.timeZone
        )
    }
}

private actor ReleaseRuleRepository: RuleRepository {
    let collection: RestrictionRuleCollectionSnapshot

    init(rule: RestrictionRuleSnapshot) {
        collection = RestrictionRuleCollectionSnapshot(revision: 1, rules: [rule])
    }

    func loadRuleCollection() -> RestrictionRuleCollectionSnapshot? { collection }
    func saveRuleCollection(_: RestrictionRuleCollectionSnapshot) {}
    func deleteRuleCollection() {}
}

private actor ReleaseLocationRepository: LocationConditionRepository {
    let collection: LocationConditionCollectionSnapshot

    init(condition: LocationConditionSnapshot) {
        collection = LocationConditionCollectionSnapshot(conditions: [condition])
    }

    func loadLocationConditionCollection() -> LocationConditionCollectionSnapshot? {
        collection
    }

    func saveLocationCondition(_: LocationConditionSnapshot) {}
    func deleteLocationCondition(for _: UUID) {}
    func deleteLocationConditions() {}
}

private struct ReleaseAuthorizationProvider: AuthorizationProviding {
    func authorizationSnapshot() -> AuthorizationSnapshot {
        TestFixtures.makeAuthorization()
    }
}

private actor ReleaseRecordingAdapter: RestrictionApplying {
    private var state: AppliedRestrictionState
    private(set) var removeCount = 0

    init(initialRule: RestrictionRuleSnapshot) {
        state = AppliedRestrictionState(
            activeRuleRevisions: [
                ActiveRuleRevision(
                    ruleID: initialRule.id,
                    revision: initialRule.revision
                ),
            ]
        )
    }

    func currentAppliedState() -> AppliedRestrictionState { state }

    func applyRestriction(for rules: [RestrictionRuleSnapshot]) {
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
        state = AppliedRestrictionState(activeRuleRevisions: [])
    }
}
