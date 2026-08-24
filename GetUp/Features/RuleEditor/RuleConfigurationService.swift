@preconcurrency import FamilyControls
import Foundation

enum RuleConfigurationServiceError: Error, Equatable, Sendable {
    case invalidDraft(Set<RestrictionRuleValidationError>)
    case staleRevision(expected: Int?, actual: Int?)
}

struct SavedRuleConfiguration: Equatable, Sendable {
    let rule: RestrictionRuleSnapshot
    let rules: RestrictionRuleCollectionSnapshot
    let savedPlaces: SavedPlaceCollectionSnapshot
}

struct RuleConfigurationService: Sendable {
    private let ruleRepository: any RuleRepository
    private let savedPlaceRepository: any SavedPlaceRepository
    private let now: @Sendable () -> Date
    private let applicationTokenCounter: @Sendable (FamilyActivitySelection) -> Int

    init(
        ruleRepository: any RuleRepository,
        savedPlaceRepository: any SavedPlaceRepository,
        now: @escaping @Sendable () -> Date = Date.init,
        applicationTokenCounter: @escaping @Sendable (FamilyActivitySelection) -> Int = {
            $0.applicationTokens.count
        }
    ) {
        self.ruleRepository = ruleRepository
        self.savedPlaceRepository = savedPlaceRepository
        self.now = now
        self.applicationTokenCounter = applicationTokenCounter
    }

    @discardableResult
    func save(
        draft: RuleEditorDraft,
        savedPlaces: [SavedPlaceSnapshot]
    ) async throws -> SavedRuleConfiguration {
        let currentRules = try await ruleRepository.loadRuleCollection()
            ?? RestrictionRuleCollectionSnapshot(revision: 0, rules: [])
        let currentPlaces = try await savedPlaceRepository.loadSavedPlaceCollection()
            ?? SavedPlaceCollectionSnapshot(revision: 0, places: [])

        let existingRule = currentRules.rules.first { $0.id == draft.id }
        try validateRevision(of: existingRule, against: draft)

        let mergedPlaces = mergePlaces(currentPlaces.places, with: savedPlaces)
        let errors = validationErrors(for: draft, savedPlaces: mergedPlaces)
        guard errors.isEmpty else {
            throw RuleConfigurationServiceError.invalidDraft(errors)
        }
        guard let savedPlaceID = draft.savedPlaceID else {
            throw RuleConfigurationServiceError.invalidDraft([.savedPlaceRequired])
        }

        let timestamp = now()
        let rule = RestrictionRuleSnapshot(
            id: draft.id,
            revision: (existingRule?.revision ?? 0) + 1,
            name: draft.name,
            isEnabled: draft.isEnabled,
            weekdays: draft.weekdays,
            startTime: draft.startTime,
            endTime: draft.endTime,
            savedPlaceID: savedPlaceID,
            radius: draft.radius,
            activitySelection: draft.activitySelection,
            createdAt: existingRule?.createdAt ?? draft.createdAt,
            updatedAt: timestamp
        )
        let ruleCollection = RestrictionRuleCollectionSnapshot(
            revision: currentRules.revision + 1,
            rules: upserting(rule, in: currentRules.rules)
        )
        let placeCollection = SavedPlaceCollectionSnapshot(
            revision: currentPlaces.revision + 1,
            places: mergedPlaces
        )

        // 장소를 먼저 기록해 새 규칙이 존재하지 않는 장소를 참조하는 순간을 만들지 않는다.
        try await savedPlaceRepository.saveSavedPlaceCollection(placeCollection)
        try await ruleRepository.saveRuleCollection(ruleCollection)

        return SavedRuleConfiguration(
            rule: rule,
            rules: ruleCollection,
            savedPlaces: placeCollection
        )
    }

    private func validateRevision(
        of existingRule: RestrictionRuleSnapshot?,
        against draft: RuleEditorDraft
    ) throws {
        let expectedRevision = existingRule?.revision
        guard draft.sourceRevision == expectedRevision else {
            throw RuleConfigurationServiceError.staleRevision(
                expected: expectedRevision,
                actual: draft.sourceRevision
            )
        }
    }

    private func validationErrors(
        for draft: RuleEditorDraft,
        savedPlaces: [SavedPlaceSnapshot]
    ) -> Set<RestrictionRuleValidationError> {
        let selectedPlace = draft.savedPlaceID.flatMap { savedPlaceID in
            savedPlaces.first { $0.id == savedPlaceID }
        }

        return RestrictionRuleValidator.errors(
            in: RestrictionRuleValidationInput(
                weekdays: draft.weekdays,
                startTime: draft.startTime,
                endTime: draft.endTime,
                savedPlaceID: draft.savedPlaceID,
                availableSavedPlaceIDs: Set(savedPlaces.map(\.id)),
                referenceLocation: selectedPlace?.coordinate,
                radiusMeters: draft.radius.rawValue,
                applicationTokenCount: applicationTokenCounter(draft.activitySelection)
            )
        )
    }

    private func mergePlaces(
        _ existingPlaces: [SavedPlaceSnapshot],
        with incomingPlaces: [SavedPlaceSnapshot]
    ) -> [SavedPlaceSnapshot] {
        var placesByID = Dictionary(uniqueKeysWithValues: existingPlaces.map { ($0.id, $0) })
        for place in incomingPlaces {
            placesByID[place.id] = place
        }

        return placesByID.values.sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private func upserting(
        _ rule: RestrictionRuleSnapshot,
        in rules: [RestrictionRuleSnapshot]
    ) -> [RestrictionRuleSnapshot] {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            var updatedRules = rules
            updatedRules[index] = rule
            return updatedRules
        }

        return rules + [rule]
    }
}
