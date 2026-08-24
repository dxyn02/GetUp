@preconcurrency import CoreLocation
@preconcurrency import FamilyControls
import Foundation

@MainActor
final class SystemAuthorizationProvider: AuthorizationProviding {
    private let locationManager: CLLocationManager
    private let backgroundRefreshStatus: @Sendable () -> BackgroundRefreshStatus

    init(
        locationManager: CLLocationManager = CLLocationManager(),
        backgroundRefreshStatus: @escaping @Sendable () -> BackgroundRefreshStatus = {
            .available
        }
    ) {
        self.locationManager = locationManager
        self.backgroundRefreshStatus = backgroundRefreshStatus
    }

    func authorizationSnapshot() async -> AuthorizationSnapshot {
        AuthorizationSnapshot(
            familyControls: familyControlsStatus,
            locationAuthorization: locationAuthorizationStatus,
            locationAccuracy: locationAccuracyStatus,
            backgroundRefresh: backgroundRefreshStatus()
        )
    }

    private var familyControlsStatus: FamilyControlsAuthorizationStatus {
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

    private var locationAuthorizationStatus: LocationAuthorizationStatus {
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

    private var locationAccuracyStatus: LocationAccuracyStatus {
        switch locationManager.accuracyAuthorization {
        case .fullAccuracy:
            .full
        case .reducedAccuracy:
            .reduced
        @unknown default:
            .reduced
        }
    }
}
