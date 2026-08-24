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
        #expect(snapshot.ruleID == rule.id)
        #expect(snapshot.ruleRevision == 7)
        #expect(snapshot.state == LocationConditionState.inside)
        #expect(snapshot.observedAt == observedAt)
        #expect(snapshot.distanceMeters == 420)
        #expect(snapshot.horizontalAccuracyMeters == 30)
        #expect(snapshot.source == LocationConditionSource.regionEvent)
        #expect(
            try await repository.loadLocationConditionCollection()?.conditions
                == [snapshot]
        )
        #expect(await evidenceProvider.requestedRuleIDs == [rule.id])
    }

    @MainActor
    @Test("Always and Full Accuracy register the selected place as a rule-specific region")
    func registersRuleRegionWithRequiredAuthorization() async throws {
        let place = makeSavedPlace()
        let savedPlaces = RecordingSavedPlaceRepository(place: place)
        let regionMonitor = FakeLocationRegionMonitor(
            monitoredIdentifiers: [regionIdentifier(for: TestFixtures.makeRule().id)]
        )
        let monitor = LocationMonitor(
            evidenceProvider: FakeLocationEvidenceProvider(
                evidence: LocationEvidence(
                    observedAt: TestFixtures.now,
                    distanceMeters: 0,
                    horizontalAccuracyMeters: 0
                )
            ),
            conditionRepository: RecordingLocationConditionRepository(),
            savedPlaceRepository: savedPlaces,
            regionMonitor: regionMonitor
        )
        let rule = TestFixtures.makeRule(radius: .meters2000)

        try await monitor.replaceMonitoring(for: rule)

        #expect(regionMonitor.stoppedIdentifiers == [regionIdentifier(for: rule.id)])
        let registration = try #require(regionMonitor.registrations.first)
        #expect(registration.center == place.coordinate)
        #expect(registration.radiusMeters == 2_000)
        #expect(registration.identifier == regionIdentifier(for: rule.id))
    }

    @MainActor
    @Test("Region registration requires both Always authorization and Full Accuracy")
    func requiresAlwaysAndFullAccuracy() async {
        let place = makeSavedPlace()
        let savedPlaces = RecordingSavedPlaceRepository(place: place)
        let rule = TestFixtures.makeRule()

        let whenInUseMonitor = FakeLocationRegionMonitor(
            authorization: .whenInUse
        )
        let whenInUseLocationMonitor = makeLocationMonitor(
            savedPlaces: savedPlaces,
            regionMonitor: whenInUseMonitor
        )
        await #expect(throws: LocationMonitorError.alwaysAuthorizationRequired) {
            try await whenInUseLocationMonitor.replaceMonitoring(for: rule)
        }

        let reducedAccuracyMonitor = FakeLocationRegionMonitor(
            accuracy: .reduced
        )
        let reducedAccuracyLocationMonitor = makeLocationMonitor(
            savedPlaces: savedPlaces,
            regionMonitor: reducedAccuracyMonitor
        )
        await #expect(throws: LocationMonitorError.fullAccuracyRequired) {
            try await reducedAccuracyLocationMonitor.replaceMonitoring(for: rule)
        }

        #expect(whenInUseMonitor.registrations.isEmpty)
        #expect(reducedAccuracyMonitor.registrations.isEmpty)
    }

    @MainActor
    private func makeLocationMonitor(
        savedPlaces: any SavedPlaceRepository,
        regionMonitor: any LocationRegionMonitoring
    ) -> LocationMonitor {
        LocationMonitor(
            evidenceProvider: FakeLocationEvidenceProvider(
                evidence: LocationEvidence(
                    observedAt: TestFixtures.now,
                    distanceMeters: 0,
                    horizontalAccuracyMeters: 0
                )
            ),
            conditionRepository: RecordingLocationConditionRepository(),
            savedPlaceRepository: savedPlaces,
            regionMonitor: regionMonitor
        )
    }

    private func makeSavedPlace() -> SavedPlaceSnapshot {
        SavedPlaceSnapshot(
            id: TestFixtures.makeRule().savedPlaceID,
            name: "테스트 장소",
            coordinate: ReferenceLocation(latitude: 37.5, longitude: 127.0),
            createdAt: TestFixtures.now,
            updatedAt: TestFixtures.now
        )
    }

    private func regionIdentifier(for ruleID: UUID) -> String {
        "getup.location.\(ruleID.uuidString.lowercased())"
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
    private var collection: LocationConditionCollectionSnapshot?

    func loadLocationConditionCollection() async throws
        -> LocationConditionCollectionSnapshot?
    {
        collection
    }

    func saveLocationCondition(_ condition: LocationConditionSnapshot) async throws {
        var conditions = collection?.conditions ?? []
        conditions.removeAll { $0.ruleID == condition.ruleID }
        conditions.append(condition)
        collection = LocationConditionCollectionSnapshot(conditions: conditions)
    }

    func deleteLocationCondition(for ruleID: UUID) async throws {
        collection = LocationConditionCollectionSnapshot(
            conditions: collection?.conditions.filter { $0.ruleID != ruleID } ?? []
        )
    }

    func deleteLocationConditions() async throws {
        collection = nil
    }
}

private actor RecordingSavedPlaceRepository: SavedPlaceRepository {
    private var collection: SavedPlaceCollectionSnapshot?

    init(place: SavedPlaceSnapshot) {
        collection = SavedPlaceCollectionSnapshot(revision: 1, places: [place])
    }

    func loadSavedPlaceCollection() async throws -> SavedPlaceCollectionSnapshot? {
        collection
    }

    func saveSavedPlaceCollection(
        _ collection: SavedPlaceCollectionSnapshot
    ) async throws {
        self.collection = collection
    }

    func deleteSavedPlaceCollection() async throws {
        collection = nil
    }
}

@MainActor
private final class FakeLocationRegionMonitor: LocationRegionMonitoring {
    struct Registration {
        let center: ReferenceLocation
        let radiusMeters: Double
        let identifier: String
    }

    private let authorization: LocationAuthorizationStatus
    private let accuracy: LocationAccuracyStatus
    private var monitoredIdentifiers: Set<String>
    private(set) var registrations: [Registration] = []
    private(set) var stoppedIdentifiers: [String] = []

    init(
        authorization: LocationAuthorizationStatus = .always,
        accuracy: LocationAccuracyStatus = .full,
        monitoredIdentifiers: Set<String> = []
    ) {
        self.authorization = authorization
        self.accuracy = accuracy
        self.monitoredIdentifiers = monitoredIdentifiers
    }

    func authorizationStatus() -> LocationAuthorizationStatus {
        authorization
    }

    func accuracyStatus() -> LocationAccuracyStatus {
        accuracy
    }

    func isMonitoringAvailable() -> Bool {
        true
    }

    func maximumMonitoringDistance() -> Double {
        5_000
    }

    func monitoredRegionIdentifiers() -> [String] {
        Array(monitoredIdentifiers)
    }

    func startMonitoring(
        center: ReferenceLocation,
        radiusMeters: Double,
        identifier: String
    ) {
        registrations.append(
            Registration(
                center: center,
                radiusMeters: radiusMeters,
                identifier: identifier
            )
        )
        monitoredIdentifiers.insert(identifier)
    }

    func stopMonitoring(identifier: String) {
        stoppedIdentifiers.append(identifier)
        monitoredIdentifiers.remove(identifier)
    }
}
