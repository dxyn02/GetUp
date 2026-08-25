import Foundation
import Observation

protocol CurrentLocationProviding: Sendable {
    func currentLocation() async throws -> ReferenceLocation
}

enum LocationPickerGuidance: Equatable, Sendable {
    case whenInUseRequired
    case locationUnavailable
    case placeNameRequired
    case placeNameTooLong
    case duplicatePlaceName
}

struct SavedPlaceDraft: Equatable, Sendable {
    let name: String
    let coordinate: ReferenceLocation
}

enum LocationPickerCompletion: Equatable, Sendable {
    case confirmed(SavedPlaceDraft)
    case reused(SavedPlaceSnapshot)
    case cancelled
}

@MainActor
@Observable
final class LocationPickerModel {
    private let savedPlacesByID: [UUID: SavedPlaceSnapshot]
    private let currentLocationProvider: any CurrentLocationProviding

    let savedPlaces: [SavedPlaceSnapshot]
    private(set) var cameraCenter: ReferenceLocation
    private(set) var pinCandidate: ReferenceLocation?
    private(set) var selectedSavedPlaceID: UUID?
    private(set) var placeName: String
    private(set) var guidance: LocationPickerGuidance?
    private(set) var completion: LocationPickerCompletion?

    var canConfirmPinSelection: Bool {
        guard let pinCandidate else {
            return false
        }

        return pinCandidate.latitude.isFinite
            && pinCandidate.longitude.isFinite
            && (-90...90).contains(pinCandidate.latitude)
            && (-180...180).contains(pinCandidate.longitude)
    }

    var canApplySelection: Bool {
        canConfirmPinSelection && placeNameValidationGuidance == nil
    }

    var placeNameValidationGuidance: LocationPickerGuidance? {
        validationGuidance(for: placeName)
    }

    private func validationGuidance(for name: String) -> LocationPickerGuidance? {
        let normalized = SavedPlaceNamePolicy.normalized(name)
        guard !normalized.isEmpty else { return .placeNameRequired }
        guard normalized.count <= SavedPlaceNamePolicy.maximumLength else {
            return .placeNameTooLong
        }
        if let duplicate = savedPlaces.first(where: {
            SavedPlaceNamePolicy.uniquenessKey($0.name)
                == SavedPlaceNamePolicy.uniquenessKey(normalized)
        }), duplicate.id != selectedSavedPlaceID {
            return .duplicatePlaceName
        }
        return nil
    }

    init(
        savedPlaces: [SavedPlaceSnapshot],
        initialSavedPlaceID: UUID?,
        initialCoordinate: ReferenceLocation?,
        defaultCoordinate: ReferenceLocation,
        currentLocationProvider: any CurrentLocationProviding
    ) {
        let savedPlacesByID = Dictionary(
            uniqueKeysWithValues: savedPlaces.map { ($0.id, $0) }
        )
        self.savedPlaces = savedPlaces
        self.savedPlacesByID = savedPlacesByID
        self.currentLocationProvider = currentLocationProvider

        let selectedPlace = initialSavedPlaceID.flatMap {
            savedPlacesByID[$0]
        }
        let coordinate = selectedPlace?.coordinate ?? initialCoordinate

        self.cameraCenter = coordinate ?? defaultCoordinate
        self.pinCandidate = coordinate
        self.selectedSavedPlaceID = selectedPlace?.id
        self.placeName = selectedPlace?.name ?? ""
    }

    func mapDidSettle(at coordinate: ReferenceLocation) {
        cameraCenter = coordinate
        pinCandidate = coordinate
        selectedSavedPlaceID = nil
        placeName = ""
        guidance = nil
    }

    func useCurrentLocation() async {
        do {
            let coordinate = try await currentLocationProvider.currentLocation()
            cameraCenter = coordinate
            pinCandidate = coordinate
            selectedSavedPlaceID = nil
            placeName = ""
            guidance = nil
        } catch let error as CurrentLocationProviderError {
            switch error {
            case .authorizationRequired, .restricted:
                guidance = .whenInUseRequired
            case .locationUnavailable:
                guidance = .locationUnavailable
            }
        } catch is CancellationError {
            return
        } catch {
            guidance = .locationUnavailable
        }
    }

    func selectSavedPlace(id: UUID) {
        guard let savedPlace = savedPlacesByID[id] else {
            return
        }

        selectedSavedPlaceID = savedPlace.id
        placeName = savedPlace.name
        cameraCenter = savedPlace.coordinate
        pinCandidate = savedPlace.coordinate
        guidance = nil
    }

    func selectPreset(named name: String) {
        if let saved = savedPlaces.first(where: {
            SavedPlaceNamePolicy.uniquenessKey($0.name)
                == SavedPlaceNamePolicy.uniquenessKey(name)
        }) {
            selectSavedPlace(id: saved.id)
            return
        }

        selectedSavedPlaceID = nil
        placeName = name
        guidance = nil
    }

    func updatePlaceName(_ name: String) {
        placeName = String(name.prefix(SavedPlaceNamePolicy.maximumLength))
        if let selectedSavedPlaceID,
           savedPlacesByID[selectedSavedPlaceID]?.name != placeName {
            self.selectedSavedPlaceID = nil
        }
        guidance = placeNameValidationGuidance
    }

    func confirm(placeName: String) {
        let normalizedName = SavedPlaceNamePolicy.normalized(placeName)
        if let validation = validationGuidance(for: normalizedName) {
            guidance = validation
            return
        }
        guard let pinCandidate, canConfirmPinSelection else {
            guidance = .locationUnavailable
            return
        }

        if
            let selectedSavedPlaceID,
            let savedPlace = savedPlacesByID[selectedSavedPlaceID],
            savedPlace.name == normalizedName,
            savedPlace.coordinate == pinCandidate
        {
            completion = .reused(savedPlace)
        } else {
            completion = .confirmed(
                SavedPlaceDraft(name: normalizedName, coordinate: pinCandidate)
            )
        }

        self.placeName = normalizedName
        guidance = nil
    }

    func cancel() {
        completion = .cancelled
    }
}
