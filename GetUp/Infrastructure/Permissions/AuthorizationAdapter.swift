@preconcurrency import CoreLocation
@preconcurrency import FamilyControls
import Foundation
import UIKit

@MainActor
protocol AuthorizationStatusReading: Sendable {
    func familyControlsStatus() -> FamilyControlsAuthorizationStatus
    func locationAuthorizationStatus() -> LocationAuthorizationStatus
    func locationAccuracyStatus() -> LocationAccuracyStatus
    func backgroundRefreshStatus() -> BackgroundRefreshStatus
}

@MainActor
final class SystemAuthorizationStatusReader: AuthorizationStatusReading {
    private let locationManager: CLLocationManager
    private let readBackgroundRefreshStatus: @MainActor () -> BackgroundRefreshStatus

    init(
        locationManager: CLLocationManager = CLLocationManager(),
        backgroundRefreshStatus: @escaping @MainActor () -> BackgroundRefreshStatus = {
            .available
        }
    ) {
        self.locationManager = locationManager
        self.readBackgroundRefreshStatus = backgroundRefreshStatus
    }

    func familyControlsStatus() -> FamilyControlsAuthorizationStatus {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved, .approvedWithDataAccess:
            .approved
        case .denied:
            .denied
        case .notDetermined:
            .notDetermined
        @unknown default:
            .notDetermined
        }
    }

    func locationAuthorizationStatus() -> LocationAuthorizationStatus {
        switch locationManager.authorizationStatus {
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

    func locationAccuracyStatus() -> LocationAccuracyStatus {
        switch locationManager.accuracyAuthorization {
        case .fullAccuracy:
            .full
        case .reducedAccuracy:
            .reduced
        @unknown default:
            .reduced
        }
    }

    func backgroundRefreshStatus() -> BackgroundRefreshStatus {
        readBackgroundRefreshStatus()
    }

    static func normalize(
        _ status: UIBackgroundRefreshStatus
    ) -> BackgroundRefreshStatus {
        switch status {
        case .available:
            .available
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .restricted
        }
    }
}

@MainActor
final class SystemAuthorizationProvider: AuthorizationProviding {
    typealias SnapshotRecorder = @MainActor (AuthorizationSnapshot) -> Void

    private let statusReader: any AuthorizationStatusReading
    private let recordSnapshot: SnapshotRecorder

    init(
        statusReader: any AuthorizationStatusReading,
        recordSnapshot: @escaping SnapshotRecorder
    ) {
        self.statusReader = statusReader
        self.recordSnapshot = recordSnapshot
    }

    convenience init(statusReader: any AuthorizationStatusReading) {
        self.init(statusReader: statusReader, recordSnapshot: { _ in })
    }

    convenience init(
        locationManager: CLLocationManager = CLLocationManager(),
        backgroundRefreshStatus: @escaping @MainActor () -> BackgroundRefreshStatus = {
            .available
        }
    ) {
        self.init(
            statusReader: SystemAuthorizationStatusReader(
                locationManager: locationManager,
                backgroundRefreshStatus: backgroundRefreshStatus
            ),
            recordSnapshot: { _ in }
        )
    }

    func authorizationSnapshot() async -> AuthorizationSnapshot {
        let snapshot = AuthorizationSnapshot(
            familyControls: statusReader.familyControlsStatus(),
            locationAuthorization: statusReader.locationAuthorizationStatus(),
            locationAccuracy: statusReader.locationAccuracyStatus(),
            backgroundRefresh: statusReader.backgroundRefreshStatus()
        )
        recordSnapshot(snapshot)
        return snapshot
    }

    @available(iOSApplicationExtension, unavailable)
    static func forApplication(
        application: UIApplication = .shared,
        locationManager: CLLocationManager = CLLocationManager(),
        bundle: Bundle = .main,
        now: @escaping @MainActor () -> Date = Date.init
    ) -> SystemAuthorizationProvider {
        let defaults = SharedIdentifiers.appGroupIdentifier(in: bundle).flatMap {
            UserDefaults(suiteName: $0)
        }
        return SystemAuthorizationProvider(
            statusReader: SystemAuthorizationStatusReader(
                locationManager: locationManager,
                backgroundRefreshStatus: {
                    SystemAuthorizationStatusReader.normalize(
                        application.backgroundRefreshStatus
                    )
                }
            ),
            recordSnapshot: { snapshot in
                guard let defaults else {
                    return
                }
                AuthorizationSnapshotDefaultsCodec.save(
                    AuthorizationSnapshotRecord(
                        snapshot: snapshot,
                        observedAt: now()
                    ),
                    to: defaults
                )
            }
        )
    }

    @available(iOSApplicationExtension, unavailable)
    static var settingsURL: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }
}

enum AuthorizationSnapshotDefaultsCodec {
    static func load(from defaults: UserDefaults) -> AuthorizationSnapshotRecord? {
        guard
            let data = defaults.data(
                forKey: SharedIdentifiers.authorizationSnapshotDefaultsKey
            )
        else {
            return nil
        }
        return try? JSONDecoder().decode(
            AuthorizationSnapshotRecord.self,
            from: data
        )
    }

    static func save(
        _ record: AuthorizationSnapshotRecord,
        to defaults: UserDefaults
    ) {
        guard let data = try? JSONEncoder().encode(record) else {
            return
        }
        defaults.set(
            data,
            forKey: SharedIdentifiers.authorizationSnapshotDefaultsKey
        )
    }
}
