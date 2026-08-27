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

enum LocationPickerPlaceChoice: Equatable, Sendable {
    case preset(String)
    case saved(UUID)
    case custom
}

@MainActor
@Observable
final class LocationPickerModel {
    private var savedPlacesByID: [UUID: SavedPlaceSnapshot]
    private let currentLocationProvider: any CurrentLocationProviding

    private(set) var savedPlaces: [SavedPlaceSnapshot]
    private(set) var cameraCenter: ReferenceLocation
    private(set) var pinCandidate: ReferenceLocation?
    private(set) var selectedSavedPlaceID: UUID?
    private(set) var selectedPlaceChoice: LocationPickerPlaceChoice?
    private(set) var placeName: String
    private(set) var guidance: LocationPickerGuidance?
    private(set) var completion: LocationPickerCompletion?
    private var shouldLoadInitialCurrentLocation: Bool

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
        self.selectedPlaceChoice = selectedPlace.map(Self.choice(for:))
        self.placeName = selectedPlace?.name ?? ""
        self.shouldLoadInitialCurrentLocation = coordinate == nil
    }

    func mapDidSettle(at coordinate: ReferenceLocation) {
        let selectedCoordinate = selectedSavedPlaceID.flatMap {
            savedPlacesByID[$0]?.coordinate
        } ?? pinCandidate
        cameraCenter = coordinate
        pinCandidate = coordinate

        if selectedPlaceChoice != nil,
           let selectedCoordinate,
           selectedCoordinate.isApproximatelyEqual(to: coordinate) {
            return
        }

        selectedSavedPlaceID = nil
        selectedPlaceChoice = nil
        placeName = ""
        guidance = nil
    }

    @discardableResult
    func loadInitialCurrentLocation() async -> Bool {
        guard shouldLoadInitialCurrentLocation else {
            return false
        }

        shouldLoadInitialCurrentLocation = false
        return await updateCurrentLocation()
    }

    func useCurrentLocation() async {
        _ = await updateCurrentLocation()
    }

    private func updateCurrentLocation() async -> Bool {
        do {
            let coordinate = try await currentLocationProvider.currentLocation()
            cameraCenter = coordinate
            pinCandidate = coordinate
            selectedSavedPlaceID = nil
            selectedPlaceChoice = nil
            placeName = ""
            guidance = nil
            return true
        } catch let error as CurrentLocationProviderError {
            switch error {
            case .authorizationRequired, .restricted:
                guidance = .whenInUseRequired
            case .locationUnavailable:
                guidance = .locationUnavailable
            }
        } catch is CancellationError {
            return false
        } catch {
            guidance = .locationUnavailable
        }
        return false
    }

    func selectSavedPlace(id: UUID) {
        guard let savedPlace = savedPlacesByID[id] else {
            return
        }

        selectedSavedPlaceID = savedPlace.id
        selectedPlaceChoice = Self.choice(for: savedPlace)
        placeName = savedPlace.name
        cameraCenter = savedPlace.coordinate
        pinCandidate = savedPlace.coordinate
        guidance = nil
    }

    func removeSavedPlace(id: UUID) {
        savedPlaces.removeAll { $0.id == id }
        savedPlacesByID[id] = nil

        guard selectedSavedPlaceID == id else {
            return
        }

        selectedSavedPlaceID = nil
        selectedPlaceChoice = nil
        placeName = ""
        guidance = nil
        completion = nil
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
        selectedPlaceChoice = .preset(name)
        placeName = name
        guidance = nil
    }

    func selectCustomPlaceName() {
        selectedSavedPlaceID = nil
        selectedPlaceChoice = .custom
        placeName = ""
        guidance = .placeNameRequired
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

    private static func choice(for savedPlace: SavedPlaceSnapshot) -> LocationPickerPlaceChoice {
        if ["집", "회사"].contains(savedPlace.name) {
            return .preset(savedPlace.name)
        }
        return .saved(savedPlace.id)
    }
}

private extension ReferenceLocation {
    func isApproximatelyEqual(to other: ReferenceLocation) -> Bool {
        abs(latitude - other.latitude) < 0.0001
            && abs(longitude - other.longitude) < 0.0001
    }
}
