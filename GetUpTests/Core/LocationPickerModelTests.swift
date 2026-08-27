import Foundation
import Testing
@testable import GetUp

@MainActor
@Suite("Location picker model")
struct LocationPickerModelTests {
    @Test("Moving a selected saved place keeps its name and identity for reassignment")
    func mapMovementKeepsSelectedPlaceForReassignment() {
        let savedPlace = makeSavedPlace()
        let model = makeModel(savedPlaces: [savedPlace])
        model.selectSavedPlace(id: savedPlace.id)
        let movedCoordinate = ReferenceLocation(latitude: 35.1796, longitude: 129.0756)

        model.mapDidSettle(at: movedCoordinate)

        #expect(model.cameraCenter == movedCoordinate)
        #expect(model.pinCandidate == movedCoordinate)
        #expect(model.selectedSavedPlaceID == savedPlace.id)
        #expect(model.selectedPlaceChoice == .preset("회사"))
        #expect(model.placeName == savedPlace.name)
    }

    @Test("The current-location shortcut keeps a selected place ready for reassignment")
    func currentLocationShortcutKeepsSelectedPlaceForReassignment() async {
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
        #expect(model.selectedSavedPlaceID == savedPlace.id)
        #expect(model.selectedPlaceChoice == .preset("회사"))
        #expect(model.placeName == savedPlace.name)
        #expect(model.guidance == nil)
    }

    @Test("A new picker loads the current location once for its initial map center")
    func initialMapCenterUsesCurrentLocation() async {
        let currentLocation = ReferenceLocation(latitude: 35.1595, longitude: 126.8526)
        let model = makeModel(
            initialCoordinate: nil,
            currentLocationResult: .success(currentLocation)
        )

        let firstLoad = await model.loadInitialCurrentLocation()
        let secondLoad = await model.loadInitialCurrentLocation()

        #expect(firstLoad)
        #expect(!secondLoad)
        #expect(model.cameraCenter == currentLocation)
        #expect(model.pinCandidate == currentLocation)
    }

    @Test("An existing place keeps its coordinate instead of replacing it on initial load")
    func existingPlaceSkipsInitialCurrentLocation() async {
        let savedPlace = makeSavedPlace()
        let model = LocationPickerModel(
            savedPlaces: [savedPlace],
            initialSavedPlaceID: savedPlace.id,
            initialCoordinate: savedPlace.coordinate,
            defaultCoordinate: ReferenceLocation(latitude: 36.5, longitude: 127.5),
            currentLocationProvider: FakeCurrentLocationProvider(
                result: .success(ReferenceLocation(latitude: 35.1595, longitude: 126.8526))
            )
        )

        let didLoad = await model.loadInitialCurrentLocation()

        #expect(!didLoad)
        #expect(model.cameraCenter == savedPlace.coordinate)
        #expect(model.selectedPlaceChoice == .preset("회사"))
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

    @Test("Home and work presets name the current pin before they have saved coordinates")
    func unsavedPresetNamesCurrentPin() {
        let coordinate = ReferenceLocation(latitude: 35.8714, longitude: 128.6014)
        let model = makeModel(initialCoordinate: coordinate)

        model.selectPreset(named: "집")
        model.confirm(placeName: model.placeName)

        #expect(model.placeName == "집")
        #expect(model.selectedPlaceChoice == .preset("집"))
        #expect(model.completion == .confirmed(SavedPlaceDraft(name: "집", coordinate: coordinate)))
    }

    @Test("Custom input remains the selected place-name choice while typing")
    func customInputMaintainsSelection() {
        let model = makeModel()

        model.selectCustomPlaceName()
        model.updatePlaceName("도서관")

        #expect(model.selectedPlaceChoice == .custom)
        #expect(model.placeName == "도서관")
        #expect(model.placeNameValidationGuidance == nil)
    }

    @Test("Custom names are capped at ten characters")
    func customNameIsCappedAtTenCharacters() {
        let model = makeModel()

        model.updatePlaceName("12345678901")

        #expect(model.placeName == "1234567890")
        #expect(model.placeName.count == SavedPlaceNamePolicy.maximumLength)
    }

    @Test("A duplicate saved-place name cannot be confirmed for another coordinate")
    func duplicateNameIsRejected() {
        let savedPlace = makeSavedPlace()
        let model = makeModel(savedPlaces: [savedPlace])
        model.mapDidSettle(at: ReferenceLocation(latitude: 35, longitude: 129))
        model.updatePlaceName(" 회사 ")

        model.confirm(placeName: model.placeName)

        #expect(model.completion == nil)
        #expect(model.guidance == .duplicatePlaceName)
        #expect(!model.canApplySelection)
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

    @Test("A camera settle at the selected saved place keeps its selection")
    func selectedPlaceProgrammaticSettleKeepsSelection() {
        let savedPlace = makeSavedPlace()
        let model = makeModel(savedPlaces: [savedPlace])
        model.selectSavedPlace(id: savedPlace.id)

        model.mapDidSettle(at: savedPlace.coordinate)

        #expect(model.selectedSavedPlaceID == savedPlace.id)
        #expect(model.selectedPlaceChoice == .preset("회사"))
        #expect(model.placeName == savedPlace.name)
    }

    @Test("An unsaved preset keeps its selection when the camera settles at its pin")
    func unsavedPresetProgrammaticSettleKeepsSelection() throws {
        let model = makeModel()
        model.selectPreset(named: "집")
        let pin = try #require(model.pinCandidate)

        model.mapDidSettle(at: pin)

        #expect(model.selectedSavedPlaceID == nil)
        #expect(model.selectedPlaceChoice == .preset("집"))
        #expect(model.placeName == "집")
    }

    @Test("Confirming a reused place returns the existing saved place")
    func confirmationReusesExistingSavedPlace() {
        let savedPlace = makeSavedPlace()
        let model = makeModel(savedPlaces: [savedPlace])
        model.selectSavedPlace(id: savedPlace.id)

        model.confirm(placeName: savedPlace.name)

        #expect(model.completion == .reused(savedPlace))
    }

    @Test("Confirming a moved saved place requests an update with the same identity")
    func confirmationUpdatesMovedSavedPlace() {
        let savedPlace = makeSavedPlace(name: "집")
        let movedCoordinate = ReferenceLocation(latitude: 35.1796, longitude: 129.0756)
        let model = makeModel(savedPlaces: [savedPlace])
        model.selectPreset(named: "집")
        model.mapDidSettle(at: movedCoordinate)

        model.confirm(placeName: model.placeName)

        #expect(
            model.completion == .updated(
                id: savedPlace.id,
                draft: SavedPlaceDraft(name: "집", coordinate: movedCoordinate)
            )
        )
    }

    @Test("Deleting the selected custom place clears its choice but preserves the map pin")
    func deletingSelectedCustomPlacePreservesPin() {
        let savedPlace = makeSavedPlace(name: "도서관")
        let model = makeModel(savedPlaces: [savedPlace])
        model.selectSavedPlace(id: savedPlace.id)
        let selectedPin = model.pinCandidate

        model.removeSavedPlace(id: savedPlace.id)

        #expect(model.savedPlaces.isEmpty)
        #expect(model.selectedSavedPlaceID == nil)
        #expect(model.selectedPlaceChoice == nil)
        #expect(model.placeName.isEmpty)
        #expect(model.pinCandidate == selectedPin)
        #expect(!model.canApplySelection)
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
        initialCoordinate: ReferenceLocation? = ReferenceLocation(
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

    private func makeSavedPlace(name: String = "회사") -> SavedPlaceSnapshot {
        SavedPlaceSnapshot(
            id: UUID(uuidString: "E82EFC71-CB77-44AF-8E22-C7942BDF0177")!,
            name: name,
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
