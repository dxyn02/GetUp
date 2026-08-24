import Foundation
import Observation

protocol CurrentLocationProviding: Sendable {
    func currentLocation() async throws -> ReferenceLocation
}

enum LocationPickerGuidance: Equatable, Sendable {
    case whenInUseRequired
    case locationUnavailable
    case placeNameRequired
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

    func confirm(placeName: String) {
        let normalizedName = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            guidance = .placeNameRequired
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
