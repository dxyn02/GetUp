@preconcurrency import FamilyControls
import Foundation
import Observation

enum RuleEditorMode: Equatable, Sendable {
    case creating
    case editing
}

struct RuleEditorDraft: Equatable, @unchecked Sendable {
    let id: UUID
    let sourceRevision: Int?
    var isEnabled: Bool
    var name: String?
    var weekdays: Set<Weekday>
    var startTime: TimeOfDay
    var endTime: TimeOfDay
    var savedPlaceID: UUID?
    var radius: RadiusOption
    var activitySelection: FamilyActivitySelection
    let createdAt: Date
}

@MainActor
@Observable
final class RuleEditorModel {
    @ObservationIgnored private let makeID: () -> UUID
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let applicationTokenCounter: (FamilyActivitySelection) -> Int

    let mode: RuleEditorMode
    let ruleID: UUID
    let sourceRevision: Int?
    let createdAt: Date

    var isEnabled: Bool
    var ruleName: String
    var weekdays: Set<Weekday>
    var startTime: TimeOfDay
    var endTime: TimeOfDay
    private(set) var selectedSavedPlaceID: UUID?
    var radius: RadiusOption
    private(set) var activitySelection: FamilyActivitySelection
    private(set) var savedPlaces: [SavedPlaceSnapshot]

    var normalizedRuleName: String? {
        let normalized = ruleName.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    var selectedSavedPlace: SavedPlaceSnapshot? {
        guard let selectedSavedPlaceID else {
            return nil
        }

        return savedPlaces.first { $0.id == selectedSavedPlaceID }
    }

    var applicationTokenCount: Int {
        applicationTokenCounter(activitySelection)
    }

    var validationErrors: Set<RestrictionRuleValidationError> {
        RestrictionRuleValidator.errors(
            in: RestrictionRuleValidationInput(
                weekdays: weekdays,
                startTime: startTime,
                endTime: endTime,
                savedPlaceID: selectedSavedPlaceID,
                availableSavedPlaceIDs: Set(savedPlaces.map(\.id)),
                referenceLocation: selectedSavedPlace?.coordinate,
                radiusMeters: radius.rawValue,
                applicationTokenCount: applicationTokenCount
            )
        )
    }

    var canSave: Bool {
        validationErrors.isEmpty
    }

    var preparedDraft: RuleEditorDraft {
        RuleEditorDraft(
            id: ruleID,
            sourceRevision: sourceRevision,
            isEnabled: isEnabled,
            name: normalizedRuleName,
            weekdays: weekdays,
            startTime: startTime,
            endTime: endTime,
            savedPlaceID: selectedSavedPlaceID,
            radius: radius,
            activitySelection: activitySelection,
            createdAt: createdAt
        )
    }

    init(
        draft: RuleEditorDraft? = nil,
        savedPlaces: [SavedPlaceSnapshot],
        makeID: @escaping () -> UUID = UUID.init,
        now: @escaping () -> Date = Date.init,
        applicationTokenCounter: @escaping (FamilyActivitySelection) -> Int = {
            $0.applicationTokens.count
        }
    ) {
        self.makeID = makeID
        self.now = now
        self.applicationTokenCounter = applicationTokenCounter
        self.savedPlaces = savedPlaces

        let source = draft ?? RuleEditorDraft(
            id: makeID(),
            sourceRevision: nil,
            isEnabled: true,
            name: nil,
            weekdays: [],
            startTime: TimeOfDay(hour: 6, minute: 0),
            endTime: TimeOfDay(hour: 9, minute: 0),
            savedPlaceID: nil,
            radius: .meters1000,
            activitySelection: FamilyActivitySelection(),
            createdAt: now()
        )

        mode = draft == nil ? .creating : .editing
        ruleID = source.id
        sourceRevision = source.sourceRevision
        createdAt = source.createdAt
        isEnabled = source.isEnabled
        ruleName = source.name ?? ""
        weekdays = source.weekdays
        startTime = source.startTime
        endTime = source.endTime
        selectedSavedPlaceID = source.savedPlaceID
        radius = source.radius
        activitySelection = source.activitySelection
    }

    func selectSavedPlace(id: UUID) {
        guard savedPlaces.contains(where: { $0.id == id }) else {
            return
        }

        selectedSavedPlaceID = id
    }

    func replaceSavedPlaces(with savedPlaces: [SavedPlaceSnapshot]) {
        self.savedPlaces = savedPlaces
    }

    func applyLocationCompletion(_ completion: LocationPickerCompletion) {
        switch completion {
        case .confirmed(let draft):
            selectOrCreateSavedPlace(from: draft)
        case .reused(let savedPlace):
            upsert(savedPlace)
            selectedSavedPlaceID = savedPlace.id
        case .cancelled:
            break
        }
    }

    func replaceActivitySelection(with selection: FamilyActivitySelection) {
        activitySelection = selection
    }

    func clearActivitySelection() {
        activitySelection = FamilyActivitySelection()
    }

    private func selectOrCreateSavedPlace(from draft: SavedPlaceDraft) {
        if let existing = savedPlaces.first(where: {
            $0.name == draft.name && $0.coordinate == draft.coordinate
        }) {
            selectedSavedPlaceID = existing.id
            return
        }

        let timestamp = now()
        let savedPlace = SavedPlaceSnapshot(
            id: makeID(),
            name: draft.name,
            coordinate: draft.coordinate,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        savedPlaces.append(savedPlace)
        selectedSavedPlaceID = savedPlace.id
    }

    private func upsert(_ savedPlace: SavedPlaceSnapshot) {
        if let index = savedPlaces.firstIndex(where: { $0.id == savedPlace.id }) {
            savedPlaces[index] = savedPlace
        } else {
            savedPlaces.append(savedPlace)
        }
    }
}
