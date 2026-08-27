import CoreLocation
import Foundation
import UIKit

enum CurrentLocationProviderError: Error, Equatable, Sendable {
    case authorizationRequired
    case restricted
    case locationUnavailable
}

protocol CurrentLocationSession: Sendable {
    func authorizationStatus() async -> LocationAuthorizationStatus
    func requestWhenInUseAuthorization() async -> LocationAuthorizationStatus
    func requestAlwaysAuthorization() async -> LocationAuthorizationStatus
    func requestLocation() async throws -> ReferenceLocation
}

protocol LocationAuthorizationRequesting: Sendable {
    func requestWhenInUseAuthorization() async -> LocationAuthorizationStatus
    func requestAlwaysAuthorization() async -> LocationAuthorizationStatus
}

struct CurrentLocationProvider: CurrentLocationProviding,
    LocationAuthorizationRequesting,
    Sendable
{
    private let session: any CurrentLocationSession

    init(session: any CurrentLocationSession) {
        self.session = session
    }

    func currentLocation() async throws -> ReferenceLocation {
        var authorizationStatus = await session.authorizationStatus()

        if authorizationStatus == .notDetermined {
            authorizationStatus = await session.requestWhenInUseAuthorization()
        }

        switch authorizationStatus {
        case .always, .whenInUse:
            break
        case .restricted:
            throw CurrentLocationProviderError.restricted
        case .denied, .notDetermined:
            throw CurrentLocationProviderError.authorizationRequired
        }

        do {
            return try await session.requestLocation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CurrentLocationProviderError.locationUnavailable
        }
    }

    func requestWhenInUseAuthorization() async -> LocationAuthorizationStatus {
        await session.requestWhenInUseAuthorization()
    }

    func requestAlwaysAuthorization() async -> LocationAuthorizationStatus {
        await session.requestAlwaysAuthorization()
    }
}

@MainActor
final class CoreLocationCurrentLocationSession: NSObject,
    CurrentLocationSession,
    @preconcurrency CLLocationManagerDelegate
{
    private static let defaultAlwaysAuthorizationFallbackNanoseconds: UInt64 = 1_000_000_000

    private enum SessionError: Error {
        case requestInProgress
        case locationUnavailable
    }

    private let manager: CLLocationManager
    private let alwaysAuthorizationFallbackNanoseconds: UInt64
    private var authorizationContinuation: CheckedContinuation<
        LocationAuthorizationStatus,
        Never
    >?
    private var authorizationFallbackTask: Task<Void, Never>?
    private var alwaysAuthorizationPromptWasPresented = false
    private var isAwaitingAlwaysAuthorization = false
    private var locationContinuation: CheckedContinuation<
        ReferenceLocation,
        any Error
    >?

    init(
        manager: CLLocationManager = CLLocationManager(),
        alwaysAuthorizationFallbackNanoseconds: UInt64 =
            defaultAlwaysAuthorizationFallbackNanoseconds
    ) {
        self.manager = manager
        self.alwaysAuthorizationFallbackNanoseconds =
            alwaysAuthorizationFallbackNanoseconds
        super.init()
        manager.delegate = self
    }

    func authorizationStatus() -> LocationAuthorizationStatus {
        Self.authorizationStatus(from: manager.authorizationStatus)
    }

    func requestWhenInUseAuthorization() async -> LocationAuthorizationStatus {
        let currentStatus = authorizationStatus()
        guard currentStatus == .notDetermined else {
            return currentStatus
        }

        guard authorizationContinuation == nil else {
            return currentStatus
        }

        return await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func requestAlwaysAuthorization() async -> LocationAuthorizationStatus {
        let currentStatus = authorizationStatus()
        guard currentStatus == .whenInUse else {
            return currentStatus
        }

        guard authorizationContinuation == nil else {
            return currentStatus
        }

        return await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            isAwaitingAlwaysAuthorization = true
            observeApplicationLifecycleForAlwaysAuthorization()
            manager.requestAlwaysAuthorization()
            scheduleAlwaysAuthorizationFallbackIfNeeded()
        }
    }

    func requestLocation() async throws -> ReferenceLocation {
        guard locationContinuation == nil else {
            throw SessionError.requestInProgress
        }

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = Self.authorizationStatus(from: manager.authorizationStatus)
        guard status != .notDetermined else {
            return
        }
        if isAwaitingAlwaysAuthorization, status == .whenInUse {
            return
        }

        finishAuthorizationRequest(returning: status)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else {
            finishLocationRequest(with: .failure(SessionError.locationUnavailable))
            return
        }

        let coordinate = location.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            finishLocationRequest(with: .failure(SessionError.locationUnavailable))
            return
        }

        finishLocationRequest(
            with: .success(
                ReferenceLocation(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            )
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        finishLocationRequest(with: .failure(error))
    }

    private func finishLocationRequest(
        with result: Result<ReferenceLocation, any Error>
    ) {
        guard let locationContinuation else {
            return
        }

        self.locationContinuation = nil
        locationContinuation.resume(with: result)
    }

    private func scheduleAlwaysAuthorizationFallbackIfNeeded() {
        guard authorizationContinuation != nil else {
            return
        }

        // Core Location ignores this request after Allow Once and also sends no
        // authorization callback when the user keeps When In Use permission.
        authorizationFallbackTask?.cancel()
        let delay = alwaysAuthorizationFallbackNanoseconds
        authorizationFallbackTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }

            guard let self else {
                return
            }
            guard !alwaysAuthorizationPromptWasPresented else {
                return
            }
            finishAuthorizationRequest(returning: authorizationStatus())
        }
    }

    private func observeApplicationLifecycleForAlwaysAuthorization() {
        alwaysAuthorizationPromptWasPresented = false
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(applicationWillResignActiveDuringAuthorizationRequest),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationDidBecomeActiveAfterAuthorizationRequest),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc
    private func applicationWillResignActiveDuringAuthorizationRequest() {
        guard authorizationContinuation != nil else {
            return
        }
        alwaysAuthorizationPromptWasPresented = true
    }

    @objc
    private func applicationDidBecomeActiveAfterAuthorizationRequest() {
        guard alwaysAuthorizationPromptWasPresented else {
            return
        }
        finishAuthorizationRequest(returning: authorizationStatus())
    }

    private func finishAuthorizationRequest(
        returning status: LocationAuthorizationStatus
    ) {
        guard let authorizationContinuation else {
            return
        }

        self.authorizationContinuation = nil
        authorizationFallbackTask?.cancel()
        authorizationFallbackTask = nil
        alwaysAuthorizationPromptWasPresented = false
        isAwaitingAlwaysAuthorization = false
        let center = NotificationCenter.default
        center.removeObserver(
            self,
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        center.removeObserver(
            self,
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        authorizationContinuation.resume(returning: status)
    }

    private static func authorizationStatus(
        from status: CLAuthorizationStatus
    ) -> LocationAuthorizationStatus {
        switch status {
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
}
