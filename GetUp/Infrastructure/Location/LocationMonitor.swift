@preconcurrency import CoreLocation
import Foundation

enum LocationMonitorError: Error, Equatable, Sendable {
    case alwaysAuthorizationRequired
    case fullAccuracyRequired
    case monitoringUnavailable
    case radiusExceedsMaximum
    case savedPlaceUnavailable
    case locationUnavailable
    case requestInProgress
}

struct LocationEvidence: Equatable, Sendable {
    let observedAt: Date
    let distanceMeters: Double
    let horizontalAccuracyMeters: Double
}

protocol LocationEvidenceProviding: Sendable {
    func evidence(for rule: RestrictionRuleSnapshot) async throws -> LocationEvidence
}

struct LocationFix: Equatable, Sendable {
    let coordinate: ReferenceLocation
    let observedAt: Date
    let horizontalAccuracyMeters: Double
}

protocol LocationFixProviding: Sendable {
    func requestLocationFix() async throws -> LocationFix
}

private struct SystemLocationClock: Clock {
    var now: Date {
        Date()
    }
}

struct RepositoryLocationEvidenceProvider: LocationEvidenceProviding, Sendable {
    private let fixProvider: any LocationFixProviding
    private let savedPlaceRepository: any SavedPlaceRepository

    init(
        fixProvider: any LocationFixProviding,
        savedPlaceRepository: any SavedPlaceRepository
    ) {
        self.fixProvider = fixProvider
        self.savedPlaceRepository = savedPlaceRepository
    }

    func evidence(for rule: RestrictionRuleSnapshot) async throws -> LocationEvidence {
        guard
            let collection = try await savedPlaceRepository.loadSavedPlaceCollection(),
            let place = collection.places.first(where: { $0.id == rule.savedPlaceID })
        else {
            throw LocationMonitorError.savedPlaceUnavailable
        }

        let fix = try await fixProvider.requestLocationFix()
        let currentLocation = CLLocation(
            latitude: fix.coordinate.latitude,
            longitude: fix.coordinate.longitude
        )
        let referenceLocation = CLLocation(
            latitude: place.coordinate.latitude,
            longitude: place.coordinate.longitude
        )

        return LocationEvidence(
            observedAt: fix.observedAt,
            distanceMeters: currentLocation.distance(from: referenceLocation),
            horizontalAccuracyMeters: fix.horizontalAccuracyMeters
        )
    }
}

@MainActor
protocol LocationRegionMonitoring: Sendable {
    func authorizationStatus() -> LocationAuthorizationStatus
    func accuracyStatus() -> LocationAccuracyStatus
    func isMonitoringAvailable() -> Bool
    func maximumMonitoringDistance() -> Double
    func monitoredRegionIdentifiers() -> [String]
    func startMonitoring(
        center: ReferenceLocation,
        radiusMeters: Double,
        identifier: String
    )
    func stopMonitoring(identifier: String)
}

@MainActor
final class SystemLocationRegionMonitor: LocationRegionMonitoring {
    private let manager: CLLocationManager

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
    }

    func authorizationStatus() -> LocationAuthorizationStatus {
        switch manager.authorizationStatus {
        case .authorizedAlways:
            .always
        case .authorizedWhenInUse:
            .whenInUse
        case .denied:
            .denied
        case .restricted:
            .restricted
        case .notDetermined:
            .notDetermined
        @unknown default:
            .notDetermined
        }
    }

    func accuracyStatus() -> LocationAccuracyStatus {
        switch manager.accuracyAuthorization {
        case .fullAccuracy:
            .full
        case .reducedAccuracy:
            .reduced
        @unknown default:
            .reduced
        }
    }

    func isMonitoringAvailable() -> Bool {
        CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)
    }

    func maximumMonitoringDistance() -> Double {
        manager.maximumRegionMonitoringDistance
    }

    func monitoredRegionIdentifiers() -> [String] {
        manager.monitoredRegions.map(\.identifier)
    }

    func startMonitoring(
        center: ReferenceLocation,
        radiusMeters: Double,
        identifier: String
    ) {
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(
                latitude: center.latitude,
                longitude: center.longitude
            ),
            radius: radiusMeters,
            identifier: identifier
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true
        manager.startMonitoring(for: region)
    }

    func stopMonitoring(identifier: String) {
        guard
            let region = manager.monitoredRegions.first(where: {
                $0.identifier == identifier
            })
        else {
            return
        }

        manager.stopMonitoring(for: region)
    }
}

@MainActor
final class CoreLocationFixProvider: NSObject,
    LocationFixProviding,
    @preconcurrency CLLocationManagerDelegate
{
    private let manager: CLLocationManager
    private var continuation: CheckedContinuation<LocationFix, any Error>?

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        super.init()
        manager.delegate = self
    }

    func requestLocationFix() async throws -> LocationFix {
        guard continuation == nil else {
            throw LocationMonitorError.requestInProgress
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else {
            finish(with: .failure(LocationMonitorError.locationUnavailable))
            return
        }

        let coordinate = location.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            finish(with: .failure(LocationMonitorError.locationUnavailable))
            return
        }

        finish(
            with: .success(
                LocationFix(
                    coordinate: ReferenceLocation(
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude
                    ),
                    observedAt: location.timestamp,
                    horizontalAccuracyMeters: location.horizontalAccuracy
                )
            )
        )
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: any Error
    ) {
        finish(with: .failure(LocationMonitorError.locationUnavailable))
    }

    private func finish(with result: Result<LocationFix, any Error>) {
        guard let continuation else {
            return
        }

        self.continuation = nil
        continuation.resume(with: result)
    }
}

actor LocationMonitor: LocationMonitoring {
    private static let regionIdentifierPrefix = "getup.location."

    private let evidenceProvider: any LocationEvidenceProviding
    private let conditionRepository: any LocationConditionRepository
    private let savedPlaceRepository: (any SavedPlaceRepository)?
    private let regionMonitor: (any LocationRegionMonitoring)?
    private let clock: any Clock

    init(
        evidenceProvider: any LocationEvidenceProviding,
        conditionRepository: any LocationConditionRepository,
        savedPlaceRepository: (any SavedPlaceRepository)? = nil,
        regionMonitor: (any LocationRegionMonitoring)? = nil,
        clock: any Clock = SystemLocationClock()
    ) {
        self.evidenceProvider = evidenceProvider
        self.conditionRepository = conditionRepository
        self.savedPlaceRepository = savedPlaceRepository
        self.regionMonitor = regionMonitor
        self.clock = clock
    }

    @MainActor
    static func live(
        conditionRepository: any LocationConditionRepository,
        savedPlaceRepository: any SavedPlaceRepository
    ) -> LocationMonitor {
        let fixProvider = CoreLocationFixProvider()
        return LocationMonitor(
            evidenceProvider: RepositoryLocationEvidenceProvider(
                fixProvider: fixProvider,
                savedPlaceRepository: savedPlaceRepository
            ),
            conditionRepository: conditionRepository,
            savedPlaceRepository: savedPlaceRepository,
            regionMonitor: SystemLocationRegionMonitor()
        )
    }

    func replaceMonitoring(for rule: RestrictionRuleSnapshot) async throws {
        guard let savedPlaceRepository, let regionMonitor else {
            throw LocationMonitorError.monitoringUnavailable
        }

        let identifier = Self.regionIdentifier(for: rule.id)

        guard rule.isEnabled else {
            await regionMonitor.stopMonitoring(identifier: identifier)
            return
        }

        guard await regionMonitor.authorizationStatus() == .always else {
            throw LocationMonitorError.alwaysAuthorizationRequired
        }
        guard await regionMonitor.accuracyStatus() == .full else {
            throw LocationMonitorError.fullAccuracyRequired
        }
        guard await regionMonitor.isMonitoringAvailable() else {
            throw LocationMonitorError.monitoringUnavailable
        }
        let maximumMonitoringDistance = await regionMonitor.maximumMonitoringDistance()
        guard rule.radius.meters <= maximumMonitoringDistance else {
            throw LocationMonitorError.radiusExceedsMaximum
        }
        guard
            let collection = try await savedPlaceRepository.loadSavedPlaceCollection(),
            let place = collection.places.first(where: { $0.id == rule.savedPlaceID })
        else {
            throw LocationMonitorError.savedPlaceUnavailable
        }

        let existingIdentifiers = await regionMonitor.monitoredRegionIdentifiers()
        if existingIdentifiers.contains(identifier) {
            await regionMonitor.stopMonitoring(identifier: identifier)
        }
        await regionMonitor.startMonitoring(
            center: place.coordinate,
            radiusMeters: rule.radius.meters,
            identifier: identifier
        )
    }

    func stopMonitoring() async throws {
        guard let regionMonitor else {
            throw LocationMonitorError.monitoringUnavailable
        }

        let identifiers = await regionMonitor.monitoredRegionIdentifiers().filter {
            $0.hasPrefix(Self.regionIdentifierPrefix)
        }
        for identifier in identifiers {
            await regionMonitor.stopMonitoring(identifier: identifier)
        }
    }

    func refreshLocationCondition(
        for rule: RestrictionRuleSnapshot,
        source: LocationConditionSource
    ) async -> LocationConditionSnapshot {
        let snapshot: LocationConditionSnapshot

        do {
            let evidence = try await evidenceProvider.evidence(for: rule)
            snapshot = LocationConditionSnapshot(
                ruleID: rule.id,
                ruleRevision: rule.revision,
                state: LocationEvidenceEvaluator.evaluate(
                    distanceMeters: evidence.distanceMeters,
                    horizontalAccuracyMeters: evidence.horizontalAccuracyMeters,
                    radiusMeters: rule.radius.meters
                ),
                observedAt: evidence.observedAt,
                distanceMeters: evidence.distanceMeters,
                horizontalAccuracyMeters: evidence.horizontalAccuracyMeters,
                source: source
            )
        } catch {
            snapshot = LocationConditionSnapshot(
                ruleID: rule.id,
                ruleRevision: rule.revision,
                state: .unavailable,
                observedAt: clock.now,
                distanceMeters: nil,
                horizontalAccuracyMeters: nil,
                source: source
            )
        }

        try? await conditionRepository.saveLocationCondition(snapshot)
        return snapshot
    }

    private static func regionIdentifier(for ruleID: UUID) -> String {
        "\(regionIdentifierPrefix)\(ruleID.uuidString.lowercased())"
    }
}

@MainActor
extension DependencyContainer {
    func makeLocationMonitor() -> LocationMonitor {
        LocationMonitor.live(
            conditionRepository: locationConditionRepository,
            savedPlaceRepository: savedPlaceRepository
        )
    }
}
