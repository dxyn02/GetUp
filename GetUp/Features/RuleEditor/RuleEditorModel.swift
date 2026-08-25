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

struct RestrictionModificationGuard: Equatable, Sendable {
    let savedPlaceName: String
    let radius: RadiusOption
    let endTime: TimeOfDay

    var message: String {
        String(
            format: String(
                localized: "restriction_guard.message",
                defaultValue: "%@ %@ 밖으로 이동하거나 %@이 지나면 규칙을 수정·끄기·삭제할 수 있어요."
            ),
            savedPlaceName,
            radiusDisplayName,
            endTimeDisplayName
        )
    }

    private var radiusDisplayName: String {
        switch radius {
        case .meters500: "500m"
        case .meters1000: "1km"
        case .meters2000: "2km"
        case .meters3000: "3km"
        case .meters4000: "4km"
        case .meters5000: "5km"
        }
    }

    private var endTimeDisplayName: String {
        let period = endTime.hour < 12 ? "AM" : "PM"
        let hour = endTime.hour % 12 == 0 ? 12 : endTime.hour % 12
        return String(format: "%02d:%02d %@", hour, endTime.minute, period)
    }
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
    private(set) var modificationGuard: RestrictionModificationGuard?

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
        validationErrors.isEmpty && modificationGuard == nil
    }

    var canModify: Bool { modificationGuard == nil }

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
        modificationGuard: RestrictionModificationGuard? = nil,
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
        self.modificationGuard = modificationGuard

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

    @discardableResult
    func setEnabled(_ isEnabled: Bool) -> Bool {
        guard canModify else {
            return false
        }

        self.isEnabled = isEnabled
        return true
    }

    func updateModificationGuard(_ modificationGuard: RestrictionModificationGuard?) {
        self.modificationGuard = modificationGuard
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
            SavedPlaceNamePolicy.uniquenessKey($0.name)
                == SavedPlaceNamePolicy.uniquenessKey(draft.name)
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
