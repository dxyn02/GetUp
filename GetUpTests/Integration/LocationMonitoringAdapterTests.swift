import Foundation
import Testing
@testable import GetUp

@Suite("Location monitoring adapter")
struct LocationMonitoringAdapterTests {
    @Test(
        "Every supported radius classifies a fully contained accuracy circle as inside",
        arguments: RadiusOption.allCases
    )
    func classifiesInsideEvidence(radius: RadiusOption) {
        let state = LocationEvidenceEvaluator.evaluate(
            distanceMeters: radius.meters - 100,
            horizontalAccuracyMeters: 50,
            radiusMeters: radius.meters
        )

        #expect(state == .inside)
    }

    @Test(
        "Every supported radius includes an exact zero-accuracy boundary",
        arguments: RadiusOption.allCases
    )
    func includesExactBoundary(radius: RadiusOption) {
        let state = LocationEvidenceEvaluator.evaluate(
            distanceMeters: radius.meters,
            horizontalAccuracyMeters: 0,
            radiusMeters: radius.meters
        )

        #expect(state == .inside)
    }

    @Test(
        "Every supported radius classifies a fully separated accuracy circle as outside",
        arguments: RadiusOption.allCases
    )
    func classifiesOutsideEvidence(radius: RadiusOption) {
        let state = LocationEvidenceEvaluator.evaluate(
            distanceMeters: radius.meters + 100,
            horizontalAccuracyMeters: 50,
            radiusMeters: radius.meters
        )

        #expect(state == .outside)
    }

    @Test(
        "Every supported radius treats boundary-overlapping accuracy as unavailable",
        arguments: RadiusOption.allCases
    )
    func classifiesOverlappingEvidenceAsUnavailable(radius: RadiusOption) {
        let state = LocationEvidenceEvaluator.evaluate(
            distanceMeters: radius.meters,
            horizontalAccuracyMeters: 20,
            radiusMeters: radius.meters
        )

        #expect(state == .unavailable)
    }

    @Test("A refreshed fix is recorded as the latest rule-revision snapshot")
    func refreshRecordsLocationConditionSnapshot() async throws {
        let observedAt = Date(timeIntervalSince1970: 1_787_025_600)
        let evidence = LocationEvidence(
            observedAt: observedAt,
            distanceMeters: 420,
            horizontalAccuracyMeters: 30
        )
        let evidenceProvider = FakeLocationEvidenceProvider(evidence: evidence)
        let repository = RecordingLocationConditionRepository()
        let monitor = LocationMonitor(
            evidenceProvider: evidenceProvider,
            conditionRepository: repository
        )
        let rule = TestFixtures.makeRule(
            revision: 7,
            radius: .meters500
        )

        let snapshot = await monitor.refreshLocationCondition(
            for: rule,
            source: LocationConditionSource.regionEvent
        )

        #expect(snapshot.schemaVersion == LocationConditionSnapshot.currentSchemaVersion)
        #expect(snapshot.ruleRevision == 7)
        #expect(snapshot.state == LocationConditionState.inside)
        #expect(snapshot.observedAt == observedAt)
        #expect(snapshot.distanceMeters == 420)
        #expect(snapshot.horizontalAccuracyMeters == 30)
        #expect(snapshot.source == LocationConditionSource.regionEvent)
        #expect(try await repository.loadLocationCondition() == snapshot)
        #expect(await evidenceProvider.requestedRuleIDs == [rule.id])
    }
}

private actor FakeLocationEvidenceProvider: LocationEvidenceProviding {
    private let evidence: LocationEvidence
    private(set) var requestedRuleIDs: [UUID] = []

    init(evidence: LocationEvidence) {
        self.evidence = evidence
    }

    func evidence(for rule: RestrictionRuleSnapshot) async throws -> LocationEvidence {
        requestedRuleIDs.append(rule.id)
        return evidence
    }
}

private actor RecordingLocationConditionRepository: LocationConditionRepository {
    private var snapshot: LocationConditionSnapshot?

    func loadLocationCondition() -> LocationConditionSnapshot? {
        snapshot
    }

    func saveLocationCondition(_ condition: LocationConditionSnapshot) {
        snapshot = condition
    }

    func deleteLocationCondition() {
        snapshot = nil
    }
}
