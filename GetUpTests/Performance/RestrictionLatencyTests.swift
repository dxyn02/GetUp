@preconcurrency import FamilyControls
import Foundation
@preconcurrency import ManagedSettings
import Testing
@testable import GetUp

@MainActor
@Suite("Restriction latency performance", .serialized)
struct RestrictionLatencyTests {
    private static let sampleCount = 100
    private static let latencyLimit: TimeInterval = 30

    @Test("100 activations meet p95 and 100 releases all meet the 30-second SLA")
    func activationAndReleaseLatency() async throws {
        let clock = ElapsedRestrictionClock(origin: TestFixtures.now)
        let rule = TestFixtures.makeRule(
            weekdays: Set(Weekday.allCases),
            startTime: TimeOfDay(hour: 0, minute: 0),
            endTime: TimeOfDay(hour: 23, minute: 59),
            activitySelection: try selection(seed: 40)
        )
        let locations = LatencyLocationRepository(
            condition: TestFixtures.makeLocationCondition(ruleID: rule.id)
        )
        let store = ConfirmingManagedSettingsStoreAccess()
        let adapter = ManagedSettingsRestrictionAdapter(
            storeAccess: store,
            stateStore: LatencyRestrictionStateStore()
        )
        let coordinator = RestrictionCoordinator(
            ruleRepository: LatencyRuleRepository(rule: rule),
            locationConditionRepository: locations,
            authorizationProvider: LatencyAuthorizationProvider(),
            restrictionAdapter: adapter,
            clock: clock,
            calendar: TestFixtures.calendar,
            timeZone: TestFixtures.timeZone
        )
        var activationLatencies: [TimeInterval] = []
        var releaseLatencies: [TimeInterval] = []

        for _ in 0..<Self.sampleCount {
            await locations.setState(.inside, observedAt: clock.now)
            let activation = try #require(
                try await coordinator.handleLocationEvent(
                    ruleID: rule.id,
                    confirmedAt: clock.now
                ).transitionMeasurement
            )
            #expect(activation.effect == .applyShield)
            activationLatencies.append(activation.latencySeconds)

            await locations.setState(.outside, observedAt: clock.now)
            let release = try #require(
                try await coordinator.handleLocationEvent(
                    ruleID: rule.id,
                    confirmedAt: clock.now
                ).transitionMeasurement
            )
            #expect(release.effect == .removeShield)
            releaseLatencies.append(release.latencySeconds)
        }

        let activationP95 = percentile95(activationLatencies)
        let releaseMaximum = releaseLatencies.max() ?? .infinity

        #expect(activationLatencies.count >= Self.sampleCount)
        #expect(releaseLatencies.count >= Self.sampleCount)
        #expect(activationP95 <= Self.latencyLimit)
        #expect(releaseLatencies.allSatisfy { $0 <= Self.latencyLimit })
        #expect(store.confirmedWriteCount == Self.sampleCount * 2)

        print(
            "RESTRICTION_LATENCY_RESULT "
                + "mode=automatic effect=applyShield samples=\(activationLatencies.count) "
                + "p95_seconds=\(formatted(activationP95)) limit_seconds=30 result=PASS"
        )
        print(
            "RESTRICTION_LATENCY_RESULT "
                + "mode=automatic effect=removeShield samples=\(releaseLatencies.count) "
                + "max_seconds=\(formatted(releaseMaximum)) limit_seconds=30 result=PASS"
        )
    }

    private func percentile95(_ values: [TimeInterval]) -> TimeInterval {
        guard !values.isEmpty else { return .infinity }
        let sorted = values.sorted()
        let rank = Int(ceil(Double(sorted.count) * 0.95))
        return sorted[max(0, rank - 1)]
    }

    private func formatted(_ value: TimeInterval) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func selection(seed: UInt8) throws -> FamilyActivitySelection {
        let encoded = try JSONEncoder().encode(["data": Data([seed])])
        let token = try JSONDecoder().decode(ApplicationToken.self, from: encoded)
        var selection = FamilyActivitySelection()
        selection.applicationTokens = [token]
        return selection
    }
}

private struct ElapsedRestrictionClock: Clock {
    let origin: Date
    let originUptime = ProcessInfo.processInfo.systemUptime

    var now: Date {
        origin.addingTimeInterval(
            ProcessInfo.processInfo.systemUptime - originUptime
        )
    }
}

private actor LatencyRuleRepository: RuleRepository {
    private let collection: RestrictionRuleCollectionSnapshot

    init(rule: RestrictionRuleSnapshot) {
        collection = RestrictionRuleCollectionSnapshot(revision: 1, rules: [rule])
    }

    func loadRuleCollection() -> RestrictionRuleCollectionSnapshot? { collection }
    func saveRuleCollection(_ collection: RestrictionRuleCollectionSnapshot) {}
    func deleteRuleCollection() {}
}

private actor LatencyLocationRepository: LocationConditionRepository {
    private var condition: LocationConditionSnapshot

    init(condition: LocationConditionSnapshot) {
        self.condition = condition
    }

    func setState(_ state: LocationConditionState, observedAt: Date) {
        condition = LocationConditionSnapshot(
            ruleID: condition.ruleID,
            ruleRevision: condition.ruleRevision,
            state: state,
            observedAt: observedAt,
            distanceMeters: state == .inside ? 100 : 600,
            horizontalAccuracyMeters: 10,
            source: .freshFix
        )
    }

    func loadLocationConditionCollection() -> LocationConditionCollectionSnapshot? {
        LocationConditionCollectionSnapshot(conditions: [condition])
    }

    func saveLocationCondition(_ condition: LocationConditionSnapshot) {
        self.condition = condition
    }

    func deleteLocationCondition(for ruleID: UUID) {}
    func deleteLocationConditions() {}
}

private struct LatencyAuthorizationProvider: AuthorizationProviding {
    func authorizationSnapshot() -> AuthorizationSnapshot {
        TestFixtures.makeAuthorization()
    }
}

@MainActor
private final class ConfirmingManagedSettingsStoreAccess: ManagedSettingsStoreAccess {
    private var applications: Set<ApplicationToken>?
    private(set) var confirmedWriteCount = 0

    func shieldedApplications(named storeName: String) -> Set<ApplicationToken>? {
        applications
    }

    func setShieldedApplications(
        _ applications: Set<ApplicationToken>?,
        named storeName: String
    ) {
        self.applications = applications
        confirmedWriteCount += 1
    }
}

private actor LatencyRestrictionStateStore: RestrictionApplicationStateStoring {
    private var state = AppliedRestrictionState(activeRuleRevisions: [])

    func currentState() -> AppliedRestrictionState { state }
    func saveState(_ newState: AppliedRestrictionState) { state = newState }
}
