import Foundation
import Testing
@testable import GetUp

@Suite("Location unavailable safety")
struct LocationUnavailableTests {
    @Test(
        "Untrusted location evidence preserves an active restriction",
        arguments: UntrustedLocationCause.allCases
    )
    func preservesActiveRestriction(cause: UntrustedLocationCause) async throws {
        let result = try await evaluate(cause: cause, initiallyApplied: true)

        expectAdapterClassification(result.snapshot, for: cause)
        #expect(
            result.coordination.decisions[result.rule.id]?.presentationState
                == .locationUnavailable(isRestrictionApplied: true)
        )
        #expect(
            result.coordination.decisions[result.rule.id]?.desiredRestriction
                == .preserve
        )
        #expect(result.coordination.appliedState.contains(result.rule))
        #expect(result.coordination.transitionMeasurement == nil)
        #expect(await result.adapter.applyCount == 1)
        #expect(await result.adapter.removeCount == 0)
    }

    @Test(
        "Untrusted location evidence does not apply a new restriction",
        arguments: UntrustedLocationCause.allCases
    )
    func preservesInactiveState(cause: UntrustedLocationCause) async throws {
        let result = try await evaluate(cause: cause, initiallyApplied: false)

        expectAdapterClassification(result.snapshot, for: cause)
        #expect(
            result.coordination.decisions[result.rule.id]?.presentationState
                == .locationUnavailable(isRestrictionApplied: false)
        )
        #expect(
            result.coordination.decisions[result.rule.id]?.desiredRestriction
                == .preserve
        )
        #expect(result.coordination.appliedState.activeRuleRevisions.isEmpty)
        #expect(result.coordination.transitionMeasurement == nil)
        #expect(await result.adapter.applyCount == 0)
        #expect(await result.adapter.removeCount == 0)
    }

    private func evaluate(
        cause: UntrustedLocationCause,
        initiallyApplied: Bool
    ) async throws -> LocationUnavailableResult {
        let rule = TestFixtures.makeRule()
        let locationRepository = UnavailableLocationRepository()
        let monitor = LocationMonitor(
            evidenceProvider: UntrustedLocationEvidenceProvider(cause: cause),
            conditionRepository: locationRepository,
            clock: FixedClock(now: TestFixtures.now)
        )
        let snapshot = await monitor.refreshLocationCondition(
            for: rule,
            source: .freshFix
        )
        let adapter = UnavailableLocationRestrictionAdapter(
            rule: rule,
            initiallyApplied: initiallyApplied
        )
        let coordinator = RestrictionCoordinator(
            ruleRepository: UnavailableLocationRuleRepository(rule: rule),
            locationConditionRepository: locationRepository,
            authorizationProvider: UnavailableLocationAuthorizationProvider(),
            restrictionAdapter: adapter,
            clock: FixedClock(now: TestFixtures.now),
            calendar: TestFixtures.calendar,
            timeZone: TestFixtures.timeZone
        )

        let coordination = try await coordinator.handleLocationEvent(
            ruleID: rule.id,
            confirmedAt: TestFixtures.now
        )

        return LocationUnavailableResult(
            rule: rule,
            snapshot: snapshot,
            coordination: coordination,
            adapter: adapter
        )
    }

    private func expectAdapterClassification(
        _ snapshot: LocationConditionSnapshot,
        for cause: UntrustedLocationCause
    ) {
        if cause == .staleFix {
            #expect(
                snapshot.observedAt
                    == TestFixtures.now.addingTimeInterval(-24 * 60 * 60)
            )
        } else {
            #expect(snapshot.state == .unavailable)
        }
    }
}

enum UntrustedLocationCause: CaseIterable, Sendable, CustomTestStringConvertible {
    case locationError
    case staleFix
    case negativeAccuracy
    case boundaryOverlap

    var testDescription: String {
        switch self {
        case .locationError:
            "location error"
        case .staleFix:
            "24-hour-old fix"
        case .negativeAccuracy:
            "negative horizontal accuracy"
        case .boundaryOverlap:
            "accuracy circle overlaps the boundary"
        }
    }
}

private struct LocationUnavailableResult {
    let rule: RestrictionRuleSnapshot
    let snapshot: LocationConditionSnapshot
    let coordination: RestrictionCoordinationResult
    let adapter: UnavailableLocationRestrictionAdapter
}

private enum UntrustedLocationEvidenceError: Error, Sendable {
    case locationUnavailable
}

private struct UntrustedLocationEvidenceProvider: LocationEvidenceProviding {
    let cause: UntrustedLocationCause

    func evidence(for _: RestrictionRuleSnapshot) async throws -> LocationEvidence {
        switch cause {
        case .locationError:
            throw UntrustedLocationEvidenceError.locationUnavailable
        case .staleFix:
            return LocationEvidence(
                observedAt: TestFixtures.now.addingTimeInterval(-24 * 60 * 60),
                distanceMeters: 100,
                horizontalAccuracyMeters: 10
            )
        case .negativeAccuracy:
            return LocationEvidence(
                observedAt: TestFixtures.now,
                distanceMeters: 100,
                horizontalAccuracyMeters: -1
            )
        case .boundaryOverlap:
            return LocationEvidence(
                observedAt: TestFixtures.now,
                distanceMeters: RadiusOption.meters500.meters,
                horizontalAccuracyMeters: 20
            )
        }
    }
}

private actor UnavailableLocationRepository: LocationConditionRepository {
    private var condition: LocationConditionSnapshot?

    func loadLocationConditionCollection() -> LocationConditionCollectionSnapshot? {
        condition.map { LocationConditionCollectionSnapshot(conditions: [$0]) }
    }

    func saveLocationCondition(_ condition: LocationConditionSnapshot) {
        self.condition = condition
    }

    func deleteLocationCondition(for _: UUID) {
        condition = nil
    }

    func deleteLocationConditions() {
        condition = nil
    }
}

private actor UnavailableLocationRuleRepository: RuleRepository {
    let collection: RestrictionRuleCollectionSnapshot

    init(rule: RestrictionRuleSnapshot) {
        collection = RestrictionRuleCollectionSnapshot(revision: 1, rules: [rule])
    }

    func loadRuleCollection() -> RestrictionRuleCollectionSnapshot? {
        collection
    }

    func saveRuleCollection(_: RestrictionRuleCollectionSnapshot) {}
    func deleteRuleCollection() {}
}

private struct UnavailableLocationAuthorizationProvider: AuthorizationProviding {
    func authorizationSnapshot() -> AuthorizationSnapshot {
        TestFixtures.makeAuthorization()
    }
}

private actor UnavailableLocationRestrictionAdapter: RestrictionApplying {
    private var state: AppliedRestrictionState
    private(set) var applyCount = 0
    private(set) var removeCount = 0

    init(rule: RestrictionRuleSnapshot, initiallyApplied: Bool) {
        state = AppliedRestrictionState(
            activeRuleRevisions: initiallyApplied
                ? [ActiveRuleRevision(ruleID: rule.id, revision: rule.revision)]
                : []
        )
    }

    func currentAppliedState() -> AppliedRestrictionState {
        state
    }

    func applyRestriction(for rules: [RestrictionRuleSnapshot]) {
        applyCount += 1
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
