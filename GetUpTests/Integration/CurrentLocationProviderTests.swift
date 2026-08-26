import Foundation
import Testing
@testable import GetUp

@Suite("Current location provider")
struct CurrentLocationProviderTests {
    @Test("When In Use authorization returns one current location")
    func authorizedRequestReturnsLocation() async throws {
        let expected = ReferenceLocation(latitude: 37.5665, longitude: 126.9780)
        let session = FakeCurrentLocationSession(
            authorizationStatus: .whenInUse,
            locationResult: .success(expected)
        )
        let provider = CurrentLocationProvider(session: session)

        let location = try await provider.currentLocation()

        #expect(location == expected)
        #expect(await session.locationRequestCount == 1)
        #expect(await session.authorizationRequestCount == 0)
    }

    @Test("Denied authorization fails without requesting a location")
    func deniedAuthorizationFailsBeforeLocationRequest() async {
        let session = FakeCurrentLocationSession(authorizationStatus: .denied)
        let provider = CurrentLocationProvider(session: session)

        await #expect(throws: CurrentLocationProviderError.authorizationRequired) {
            try await provider.currentLocation()
        }
        #expect(await session.locationRequestCount == 0)
    }

    @Test("Restricted authorization fails without requesting a location")
    func restrictedAuthorizationFailsBeforeLocationRequest() async {
        let session = FakeCurrentLocationSession(authorizationStatus: .restricted)
        let provider = CurrentLocationProvider(session: session)

        await #expect(throws: CurrentLocationProviderError.restricted) {
            try await provider.currentLocation()
        }
        #expect(await session.locationRequestCount == 0)
    }

    @Test("An undetermined status requests When In Use permission once")
    func undeterminedAuthorizationRequestsPermission() async throws {
        let expected = ReferenceLocation(latitude: 35.1796, longitude: 129.0756)
        let session = FakeCurrentLocationSession(
            authorizationStatus: .notDetermined,
            authorizationResult: .whenInUse,
            locationResult: .success(expected)
        )
        let provider = CurrentLocationProvider(session: session)

        let location = try await provider.currentLocation()

        #expect(location == expected)
        #expect(await session.authorizationRequestCount == 1)
        #expect(await session.locationRequestCount == 1)
    }

    @Test("Permission refusal after the prompt is reported")
    func permissionRefusalAfterPromptFails() async {
        let session = FakeCurrentLocationSession(
            authorizationStatus: .notDetermined,
            authorizationResult: .denied
        )
        let provider = CurrentLocationProvider(session: session)

        await #expect(throws: CurrentLocationProviderError.authorizationRequired) {
            try await provider.currentLocation()
        }
        #expect(await session.authorizationRequestCount == 1)
        #expect(await session.locationRequestCount == 0)
    }

    @Test("Always authorization upgrade is forwarded to the shared Core Location session")
    func alwaysAuthorizationUpgradeIsForwarded() async {
        let session = FakeCurrentLocationSession(
            authorizationStatus: .whenInUse,
            authorizationResult: .always
        )
        let provider = CurrentLocationProvider(session: session)

        let status = await provider.requestAlwaysAuthorization()

        #expect(status == .always)
        #expect(await session.authorizationRequestCount == 1)
    }

    @Test("A one-shot Core Location failure is normalized")
    func locationFailureIsNormalized() async {
        let session = FakeCurrentLocationSession(
            authorizationStatus: .whenInUse,
            locationResult: .failure(.requestFailed)
        )
        let provider = CurrentLocationProvider(session: session)

        await #expect(throws: CurrentLocationProviderError.locationUnavailable) {
            try await provider.currentLocation()
        }
        #expect(await session.locationRequestCount == 1)
    }
}

private enum FakeCurrentLocationSessionError: Error, Sendable {
    case requestFailed
}

private actor FakeCurrentLocationSession: CurrentLocationSession {
    private let initialAuthorizationStatus: LocationAuthorizationStatus
    private let authorizationResult: LocationAuthorizationStatus
    private let locationResult: Result<ReferenceLocation, FakeCurrentLocationSessionError>

    private(set) var authorizationRequestCount = 0
    private(set) var locationRequestCount = 0

    init(
        authorizationStatus: LocationAuthorizationStatus,
        authorizationResult: LocationAuthorizationStatus? = nil,
        locationResult: Result<ReferenceLocation, FakeCurrentLocationSessionError> = .failure(
            .requestFailed
        )
    ) {
        self.initialAuthorizationStatus = authorizationStatus
        self.authorizationResult = authorizationResult ?? authorizationStatus
        self.locationResult = locationResult
    }

    func authorizationStatus() -> LocationAuthorizationStatus {
        initialAuthorizationStatus
    }

    func requestWhenInUseAuthorization() async -> LocationAuthorizationStatus {
        authorizationRequestCount += 1
        return authorizationResult
    }

    func requestAlwaysAuthorization() async -> LocationAuthorizationStatus {
        authorizationRequestCount += 1
        return authorizationResult
    }

    func requestLocation() async throws -> ReferenceLocation {
        locationRequestCount += 1
        return try locationResult.get()
    }
}
