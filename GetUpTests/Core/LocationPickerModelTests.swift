import Foundation
import Testing
@testable import GetUp

@MainActor
@Suite("Location picker model")
struct LocationPickerModelTests {
    @Test("A settled map movement updates the center and pin candidate")
    func mapMovementUpdatesCandidate() {
        let savedPlace = makeSavedPlace()
        let model = makeModel(savedPlaces: [savedPlace])
        model.selectSavedPlace(id: savedPlace.id)
        let movedCoordinate = ReferenceLocation(latitude: 35.1796, longitude: 129.0756)

        model.mapDidSettle(at: movedCoordinate)

        #expect(model.cameraCenter == movedCoordinate)
        #expect(model.pinCandidate == movedCoordinate)
        #expect(model.selectedSavedPlaceID == nil)
        #expect(model.placeName.isEmpty)
    }

    @Test("The current-location shortcut moves both map and pin")
    func currentLocationShortcutUpdatesCandidate() async {
        let currentLocation = ReferenceLocation(latitude: 37.4563, longitude: 126.7052)
        let savedPlace = makeSavedPlace()
        let model = makeModel(
            savedPlaces: [savedPlace],
            currentLocationResult: .success(currentLocation)
        )
        model.selectSavedPlace(id: savedPlace.id)

        await model.useCurrentLocation()

        #expect(model.cameraCenter == currentLocation)
        #expect(model.pinCandidate == currentLocation)
        #expect(model.selectedSavedPlaceID == nil)
        #expect(model.placeName.isEmpty)
        #expect(model.guidance == nil)
    }

    @Test("Missing When In Use permission keeps direct pin selection available")
    func permissionFailurePreservesPinCandidate() async {
        let initialCoordinate = ReferenceLocation(latitude: 37.5665, longitude: 126.9780)
        let model = makeModel(
            initialCoordinate: initialCoordinate,
            currentLocationResult: .failure(.authorizationRequired)
        )

        await model.useCurrentLocation()

        #expect(model.pinCandidate == initialCoordinate)
        #expect(model.guidance == .whenInUseRequired)
        #expect(model.canConfirmPinSelection)
    }

    @Test("A location lookup failure is presented without replacing the pin")
    func locationFailurePreservesPinCandidate() async {
        let initialCoordinate = ReferenceLocation(latitude: 37.5665, longitude: 126.9780)
        let model = makeModel(
            initialCoordinate: initialCoordinate,
            currentLocationResult: .failure(.locationUnavailable)
        )

        await model.useCurrentLocation()

        #expect(model.pinCandidate == initialCoordinate)
        #expect(model.guidance == .locationUnavailable)
    }

    @Test("Confirming a moved pin creates a reusable saved-place draft")
    func confirmationCreatesSavedPlaceDraft() {
        let coordinate = ReferenceLocation(latitude: 35.8714, longitude: 128.6014)
        let model = makeModel(initialCoordinate: coordinate)

        model.confirm(placeName: "집")

        #expect(
            model.completion
                == .confirmed(
                    SavedPlaceDraft(name: "집", coordinate: coordinate)
                )
        )
    }

    @Test("Selecting a saved place reuses its name and coordinate")
    func savedPlaceCanBeReused() {
        let savedPlace = makeSavedPlace()
        let model = makeModel(savedPlaces: [savedPlace])

        model.selectSavedPlace(id: savedPlace.id)

        #expect(model.selectedSavedPlaceID == savedPlace.id)
        #expect(model.placeName == savedPlace.name)
        #expect(model.cameraCenter == savedPlace.coordinate)
        #expect(model.pinCandidate == savedPlace.coordinate)
        #expect(model.savedPlaces == [savedPlace])
    }

    @Test("Confirming a reused place returns the existing saved place")
    func confirmationReusesExistingSavedPlace() {
        let savedPlace = makeSavedPlace()
        let model = makeModel(savedPlaces: [savedPlace])
        model.selectSavedPlace(id: savedPlace.id)

        model.confirm(placeName: savedPlace.name)

        #expect(model.completion == .reused(savedPlace))
    }

    @Test("Cancelling records no location selection")
    func cancellationDoesNotConfirmCandidate() {
        let model = makeModel()

        model.cancel()

        #expect(model.completion == .cancelled)
    }

    @Test("A saved place keeps latitude and longitude at the storage payload root")
    func savedPlaceUsesFlatCoordinatePayload() throws {
        let savedPlace = makeSavedPlace()
        let data = try JSONEncoder().encode(savedPlace)
        let payload = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(payload["latitude"] as? Double == savedPlace.coordinate.latitude)
        #expect(payload["longitude"] as? Double == savedPlace.coordinate.longitude)
        #expect(payload["coordinate"] == nil)
        #expect(try JSONDecoder().decode(SavedPlaceSnapshot.self, from: data) == savedPlace)
    }

    private func makeModel(
        savedPlaces: [SavedPlaceSnapshot] = [],
        initialCoordinate: ReferenceLocation = ReferenceLocation(
            latitude: 37.5665,
            longitude: 126.9780
        ),
        currentLocationResult: Result<ReferenceLocation, CurrentLocationProviderError> = .success(
            ReferenceLocation(latitude: 37.5665, longitude: 126.9780)
        )
    ) -> LocationPickerModel {
        LocationPickerModel(
            savedPlaces: savedPlaces,
            initialSavedPlaceID: nil,
            initialCoordinate: initialCoordinate,
            defaultCoordinate: ReferenceLocation(latitude: 36.5, longitude: 127.5),
            currentLocationProvider: FakeCurrentLocationProvider(
                result: currentLocationResult
            )
        )
    }

    private func makeSavedPlace() -> SavedPlaceSnapshot {
        SavedPlaceSnapshot(
            id: UUID(uuidString: "E82EFC71-CB77-44AF-8E22-C7942BDF0177")!,
            name: "회사",
            coordinate: ReferenceLocation(latitude: 37.4021, longitude: 127.1087),
            createdAt: TestFixtures.now,
            updatedAt: TestFixtures.now
        )
    }
}

private struct FakeCurrentLocationProvider: CurrentLocationProviding {
    let result: Result<ReferenceLocation, CurrentLocationProviderError>

    func currentLocation() async throws -> ReferenceLocation {
        try result.get()
    }
}
