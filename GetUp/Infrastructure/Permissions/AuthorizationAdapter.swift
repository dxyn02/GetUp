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
    private let statusReader: any AuthorizationStatusReading

    init(statusReader: any AuthorizationStatusReading) {
        self.statusReader = statusReader
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
            )
        )
    }

    func authorizationSnapshot() async -> AuthorizationSnapshot {
        AuthorizationSnapshot(
            familyControls: statusReader.familyControlsStatus(),
            locationAuthorization: statusReader.locationAuthorizationStatus(),
            locationAccuracy: statusReader.locationAccuracyStatus(),
            backgroundRefresh: statusReader.backgroundRefreshStatus()
        )
    }

    @available(iOSApplicationExtension, unavailable)
    static func forApplication(
        application: UIApplication = .shared,
        locationManager: CLLocationManager = CLLocationManager()
    ) -> SystemAuthorizationProvider {
        SystemAuthorizationProvider(
            locationManager: locationManager,
            backgroundRefreshStatus: {
                SystemAuthorizationStatusReader.normalize(
                    application.backgroundRefreshStatus
                )
            }
        )
    }

    @available(iOSApplicationExtension, unavailable)
    static var settingsURL: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }
}
