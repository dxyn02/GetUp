import Testing
import UIKit
@testable import GetUp

@MainActor
@Suite("Authorization adapter")
struct AuthorizationAdapterTests {
    @Test(
        "Family Controls, location, accuracy, and background refresh are composed",
        arguments: authorizationCases
    )
    func composesEveryAuthorizationStatus(testCase: AuthorizationCompositionCase) async {
        let reader = FakeAuthorizationStatusReader(snapshot: testCase.snapshot)
        let provider = SystemAuthorizationProvider(statusReader: reader)

        let snapshot: AuthorizationSnapshot = await provider.authorizationSnapshot()

        #expect(snapshot == testCase.snapshot)
    }

    @Test("Every snapshot reads the latest system authorization statuses")
    func readsCurrentStatusesForEverySnapshot() async {
        let reader = FakeAuthorizationStatusReader(
            snapshot: AuthorizationSnapshot(
                familyControls: .approved,
                locationAuthorization: .always,
                locationAccuracy: .full,
                backgroundRefresh: .available
            )
        )
        let provider = SystemAuthorizationProvider(statusReader: reader)

        let firstSnapshot: AuthorizationSnapshot = await provider.authorizationSnapshot()

        reader.snapshot = AuthorizationSnapshot(
            familyControls: .denied,
            locationAuthorization: .whenInUse,
            locationAccuracy: .reduced,
            backgroundRefresh: .restricted
        )
        let changedSnapshot: AuthorizationSnapshot = await provider.authorizationSnapshot()

        #expect(firstSnapshot.familyControls == .approved)
        #expect(firstSnapshot.locationAuthorization == .always)
        #expect(firstSnapshot.locationAccuracy == .full)
        #expect(firstSnapshot.backgroundRefresh == .available)
        #expect(changedSnapshot == reader.snapshot)
    }

    @Test("The application provider records the latest authorization snapshot")
    func recordsLatestAuthorizationSnapshot() async {
        let expected = AuthorizationSnapshot(
            familyControls: .approved,
            locationAuthorization: .always,
            locationAccuracy: .full,
            backgroundRefresh: .available
        )
        let reader = FakeAuthorizationStatusReader(snapshot: expected)
        var recordedSnapshots: [AuthorizationSnapshot] = []
        let provider = SystemAuthorizationProvider(
            statusReader: reader,
            recordSnapshot: { recordedSnapshots.append($0) }
        )

        _ = await provider.authorizationSnapshot()

        #expect(recordedSnapshots == [expected])
    }

    @Test("Every background refresh state is normalized")
    func normalizesBackgroundRefreshStatus() {
        #expect(
            SystemAuthorizationStatusReader.normalize(.available) == .available
        )
        #expect(
            SystemAuthorizationStatusReader.normalize(.denied) == .denied
        )
        #expect(
            SystemAuthorizationStatusReader.normalize(.restricted) == .restricted
        )
    }

    @Test("The adapter exposes the app's system Settings URL")
    func exposesSystemSettingsURL() {
        #expect(
            SystemAuthorizationProvider.settingsURL
                == URL(string: UIApplication.openSettingsURLString)
        )
    }
}

struct AuthorizationCompositionCase: Sendable, CustomTestStringConvertible {
    let name: String
    let snapshot: AuthorizationSnapshot

    var testDescription: String {
        name
    }
}

private let authorizationCases: [AuthorizationCompositionCase] = [
    AuthorizationCompositionCase(
        name: "all capabilities available",
        snapshot: AuthorizationSnapshot(
            familyControls: .approved,
            locationAuthorization: .always,
            locationAccuracy: .full,
            backgroundRefresh: .available
        )
    ),
    AuthorizationCompositionCase(
        name: "denied family controls, when-in-use, reduced accuracy, denied refresh",
        snapshot: AuthorizationSnapshot(
            familyControls: .denied,
            locationAuthorization: .whenInUse,
            locationAccuracy: .reduced,
            backgroundRefresh: .denied
        )
    ),
    AuthorizationCompositionCase(
        name: "undetermined family controls, denied location, restricted refresh",
        snapshot: AuthorizationSnapshot(
            familyControls: .notDetermined,
            locationAuthorization: .denied,
            locationAccuracy: .full,
            backgroundRefresh: .restricted
        )
    ),
    AuthorizationCompositionCase(
        name: "restricted location with reduced accuracy",
        snapshot: AuthorizationSnapshot(
            familyControls: .approved,
            locationAuthorization: .restricted,
            locationAccuracy: .reduced,
            backgroundRefresh: .available
        )
    ),
    AuthorizationCompositionCase(
        name: "undetermined location",
        snapshot: AuthorizationSnapshot(
            familyControls: .denied,
            locationAuthorization: .notDetermined,
            locationAccuracy: .full,
            backgroundRefresh: .denied
        )
    ),
]

@MainActor
private final class FakeAuthorizationStatusReader: AuthorizationStatusReading {
    var snapshot: AuthorizationSnapshot

    init(snapshot: AuthorizationSnapshot) {
        self.snapshot = snapshot
    }

    func familyControlsStatus() -> FamilyControlsAuthorizationStatus {
        snapshot.familyControls
    }

    func locationAuthorizationStatus() -> LocationAuthorizationStatus {
        snapshot.locationAuthorization
    }

    func locationAccuracyStatus() -> LocationAccuracyStatus {
        snapshot.locationAccuracy
    }

    func backgroundRefreshStatus() -> BackgroundRefreshStatus {
        snapshot.backgroundRefresh
    }
}
