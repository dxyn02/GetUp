@preconcurrency import FamilyControls
import Foundation
import Testing
@testable import GetUp

@Suite("Rule configuration service")
struct RuleConfigurationServiceTests {
    @Test("A new rule and its saved place are stored as revision one collections")
    func savesNewRuleAndPlaceCollections() async throws {
        let repository = InMemoryRuleConfigurationRepository()
        let service = makeService(repository: repository)
        let place = makePlace()

        let saved = try await service.save(
            draft: makeDraft(savedPlaceID: place.id),
            savedPlaces: [place]
        )

        #expect(saved.rule.revision == 1)
        #expect(saved.rules.revision == 1)
        #expect(saved.rules.rules == [saved.rule])
        #expect(saved.savedPlaces.revision == 1)
        #expect(saved.savedPlaces.places == [place])
        #expect(await repository.writeOrder == [.places, .rules])
    }

    @Test("A category-only selection can be persisted by the default validator")
    func savesCategoryOnlySelection() async throws {
        let repository = InMemoryRuleConfigurationRepository()
        let place = makePlace()
        var selection = FamilyActivitySelection()
        selection.categoryTokens = [
            try TestFixtures.activityCategoryToken(seed: 22),
        ]
        let service = RuleConfigurationService(
            ruleRepository: repository,
            savedPlaceRepository: repository,
            now: { Date(timeIntervalSince1970: 2_000) }
        )

        let saved = try await service.save(
            draft: makeDraft(
                savedPlaceID: place.id,
                activitySelection: selection
            ),
            savedPlaces: [place]
        )

        #expect(saved.rule.activitySelection == selection)
        #expect(await repository.storedRules?.rules == [saved.rule])
    }

    @Test("Editing increments only that rule revision and preserves other rules")
    func editingIncrementsRevisionAndPreservesOtherRules() async throws {
        let place = makePlace()
        let editedID = UUID(uuidString: "00000000-0000-4000-8000-000000000201")!
        let otherRule = makeRule(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000202")!,
            revision: 4,
            savedPlaceID: place.id,
            name: "다른 규칙"
        )
        let editedRule = makeRule(
            id: editedID,
            revision: 2,
            savedPlaceID: place.id,
            name: "수정 전"
        )
        let repository = InMemoryRuleConfigurationRepository(
            rules: RestrictionRuleCollectionSnapshot(
                revision: 7,
                rules: [editedRule, otherRule]
            ),
            places: SavedPlaceCollectionSnapshot(revision: 3, places: [place])
        )
        let service = makeService(repository: repository)

        let saved = try await service.save(
            draft: makeDraft(
                id: editedID,
                sourceRevision: 2,
                name: "수정 후",
                savedPlaceID: place.id,
                createdAt: editedRule.createdAt
            ),
            savedPlaces: [place]
        )

        #expect(saved.rule.revision == 3)
        #expect(saved.rule.name == "수정 후")
        #expect(saved.rules.revision == 8)
        #expect(saved.rules.rules.count == 2)
        #expect(saved.rules.rules.first { $0.id == otherRule.id } == otherRule)
        #expect(saved.savedPlaces.revision == 4)
    }

    @Test("Updating a shared saved place keeps its identity for every referencing rule")
    func updatesSharedSavedPlaceWithoutBreakingRuleReferences() async throws {
        let place = makePlace()
        let movedPlace = SavedPlaceSnapshot(
            id: place.id,
            name: place.name,
            coordinate: ReferenceLocation(latitude: 35.1796, longitude: 129.0756),
            createdAt: place.createdAt,
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        let editedRule = makeRule(revision: 2, savedPlaceID: place.id)
        let otherRule = makeRule(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000205")!,
            revision: 1,
            savedPlaceID: place.id,
            name: "공유 장소 규칙"
        )
        let repository = InMemoryRuleConfigurationRepository(
            rules: RestrictionRuleCollectionSnapshot(
                revision: 3,
                rules: [editedRule, otherRule]
            ),
            places: SavedPlaceCollectionSnapshot(revision: 5, places: [place])
        )
        let service = makeService(repository: repository)

        let saved = try await service.save(
            draft: makeDraft(
                id: editedRule.id,
                sourceRevision: editedRule.revision,
                savedPlaceID: place.id,
                createdAt: editedRule.createdAt
            ),
            savedPlaces: [movedPlace]
        )

        #expect(saved.savedPlaces.revision == 6)
        #expect(saved.savedPlaces.places == [movedPlace])
        #expect(saved.rules.rules.first { $0.id == editedRule.id }?.savedPlaceID == place.id)
        #expect(saved.rules.rules.first { $0.id == otherRule.id } == otherRule)
    }

    @Test("A stale editor revision is rejected without writing")
    func rejectsStaleRevision() async throws {
        let place = makePlace()
        let existing = makeRule(revision: 3, savedPlaceID: place.id)
        let repository = InMemoryRuleConfigurationRepository(
            rules: RestrictionRuleCollectionSnapshot(revision: 3, rules: [existing]),
            places: SavedPlaceCollectionSnapshot(revision: 1, places: [place])
        )
        let service = makeService(repository: repository)

        await #expect(throws: RuleConfigurationServiceError.staleRevision(
            expected: 3,
            actual: 2
        )) {
            try await service.save(
                draft: makeDraft(
                    id: existing.id,
                    sourceRevision: 2,
                    savedPlaceID: place.id
                ),
                savedPlaces: [place]
            )
        }

        #expect(await repository.writeOrder.isEmpty)
    }

    @Test("A draft referencing a missing place is rejected")
    func rejectsMissingSavedPlace() async throws {
        let repository = InMemoryRuleConfigurationRepository()
        let service = makeService(repository: repository)

        await #expect(throws: RuleConfigurationServiceError.invalidDraft([
            .savedPlaceNotFound,
        ])) {
            try await service.save(
                draft: makeDraft(savedPlaceID: UUID()),
                savedPlaces: []
            )
        }

        #expect(await repository.writeOrder.isEmpty)
    }

    @Test("Duplicate saved-place names are rejected before persistence")
    func rejectsDuplicateSavedPlaceNames() async throws {
        let first = makePlace()
        let duplicate = SavedPlaceSnapshot(
            id: UUID(),
            name: " 집 ",
            coordinate: ReferenceLocation(latitude: 35, longitude: 129),
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let repository = InMemoryRuleConfigurationRepository()
        let service = makeService(repository: repository)

        await #expect(throws: RuleConfigurationServiceError.invalidSavedPlaces) {
            try await service.save(
                draft: makeDraft(savedPlaceID: first.id),
                savedPlaces: [first, duplicate]
            )
        }

        #expect(await repository.writeOrder.isEmpty)
    }

    @Test("Saved-place names longer than ten characters are rejected before persistence")
    func rejectsLongSavedPlaceName() async throws {
        let place = SavedPlaceSnapshot(
            id: UUID(),
            name: "12345678901",
            coordinate: ReferenceLocation(latitude: 37, longitude: 127),
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let repository = InMemoryRuleConfigurationRepository()
        let service = makeService(repository: repository)

        await #expect(throws: RuleConfigurationServiceError.invalidSavedPlaces) {
            try await service.save(
                draft: makeDraft(savedPlaceID: place.id),
                savedPlaces: [place]
            )
        }

        #expect(await repository.writeOrder.isEmpty)
    }

    @Test("Runtime recovery starts only after both snapshots are stored")
    func synchronizesRuntimeAfterPersistence() async throws {
        let events = RuleConfigurationRuntimeEventRecorder()
        let repository = InMemoryRuleConfigurationRepository(events: events)
        let service = makeService(
            repository: repository,
            synchronizeRuntimeAfterSave: { rule in
                await events.record(.runtime(ruleRevision: rule.revision))
            }
        )
        let place = makePlace()

        let saved = try await service.save(
            draft: makeDraft(savedPlaceID: place.id),
            savedPlaces: [place]
        )

        #expect(saved.rule.revision == 1)
        #expect(await events.values == [
            .places,
            .rules,
            .runtime(ruleRevision: 1),
        ])
    }

    @Test("A rule snapshot write failure never changes runtime registrations")
    func persistenceFailureSkipsRuntimeSynchronization() async throws {
        let events = RuleConfigurationRuntimeEventRecorder()
        let repository = InMemoryRuleConfigurationRepository(
            events: events,
            shouldFailRuleSave: true
        )
        let service = makeService(
            repository: repository,
            synchronizeRuntimeAfterSave: { rule in
                await events.record(.runtime(ruleRevision: rule.revision))
            }
        )
        let place = makePlace()

        await #expect(throws: RuleConfigurationTestFailure.expected) {
            try await service.save(
                draft: makeDraft(savedPlaceID: place.id),
                savedPlaces: [place]
            )
        }

        #expect(await events.values == [.places])
    }

    @Test("Deleting a rule preserves other rules and reusable saved places")
    func deletesOnlySelectedRule() async throws {
        let place = makePlace()
        let deletedRule = makeRule(revision: 2, savedPlaceID: place.id)
        let remainingRule = makeRule(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000204")!,
            revision: 4,
            savedPlaceID: place.id,
            name: "남은 규칙"
        )
        let repository = InMemoryRuleConfigurationRepository(
            rules: RestrictionRuleCollectionSnapshot(
                revision: 7,
                rules: [deletedRule, remainingRule]
            ),
            places: SavedPlaceCollectionSnapshot(revision: 3, places: [place])
        )
        let service = makeService(repository: repository)

        let deleted = try await service.delete(
            ruleID: deletedRule.id,
            sourceRevision: deletedRule.revision
        )

        #expect(deleted.revision == 8)
        #expect(deleted.rules == [remainingRule])
        #expect(await repository.storedRules == deleted)
        #expect(await repository.storedPlaces?.places == [place])
        #expect(await repository.writeOrder == [.rules])
    }

    @Test("Deleting from a stale editor is rejected without writing")
    func rejectsStaleDelete() async throws {
        let place = makePlace()
        let rule = makeRule(revision: 3, savedPlaceID: place.id)
        let repository = InMemoryRuleConfigurationRepository(
            rules: RestrictionRuleCollectionSnapshot(revision: 3, rules: [rule]),
            places: SavedPlaceCollectionSnapshot(revision: 1, places: [place])
        )
        let service = makeService(repository: repository)

        await #expect(throws: RuleConfigurationServiceError.staleRevision(
            expected: 3,
            actual: 2
        )) {
            try await service.delete(ruleID: rule.id, sourceRevision: 2)
        }

        #expect(await repository.writeOrder.isEmpty)
    }

    @Test("Deleting an unused custom place persists an empty collection with a new revision")
    func deletesUnusedCustomPlace() async throws {
        let customPlace = makePlace(name: "도서관")
        let repository = InMemoryRuleConfigurationRepository(
            places: SavedPlaceCollectionSnapshot(revision: 3, places: [customPlace])
        )
        let service = makeService(repository: repository)

        let deleted = try await service.deleteSavedPlace(id: customPlace.id)

        #expect(deleted.revision == 4)
        #expect(deleted.places.isEmpty)
        #expect(await repository.storedPlaces == deleted)
        #expect(await repository.writeOrder == [.places])
    }

    @Test("A custom place referenced by any rule cannot be deleted")
    func rejectsReferencedCustomPlaceDeletion() async throws {
        let customPlace = makePlace(name: "도서관")
        let rule = makeRule(revision: 2, savedPlaceID: customPlace.id)
        let repository = InMemoryRuleConfigurationRepository(
            rules: RestrictionRuleCollectionSnapshot(revision: 4, rules: [rule]),
            places: SavedPlaceCollectionSnapshot(revision: 3, places: [customPlace])
        )
        let service = makeService(repository: repository)

        await #expect(throws: RuleConfigurationServiceError.savedPlaceInUse(
            ruleIDs: [rule.id]
        )) {
            try await service.deleteSavedPlace(id: customPlace.id)
        }

        #expect(await repository.storedPlaces?.places == [customPlace])
        #expect(await repository.writeOrder.isEmpty)
    }

    @Test("Home and work preset places cannot be deleted")
    func rejectsProtectedPresetDeletion() async throws {
        let home = makePlace(name: " 집 ")
        let repository = InMemoryRuleConfigurationRepository(
            places: SavedPlaceCollectionSnapshot(revision: 3, places: [home])
        )
        let service = makeService(repository: repository)

        await #expect(throws: RuleConfigurationServiceError.protectedSavedPlace) {
            try await service.deleteSavedPlace(id: home.id)
        }

        #expect(await repository.writeOrder.isEmpty)
    }

    private func makeService(
        repository: InMemoryRuleConfigurationRepository,
        synchronizeRuntimeAfterSave: @escaping @Sendable (
            RestrictionRuleSnapshot
        ) async throws -> Void = { _ in }
    ) -> RuleConfigurationService {
        RuleConfigurationService(
            ruleRepository: repository,
            savedPlaceRepository: repository,
            now: { Date(timeIntervalSince1970: 2_000) },
            applicationTokenCounter: { _ in 1 },
            synchronizeRuntimeAfterSave: synchronizeRuntimeAfterSave
        )
    }

    private func makeDraft(
        id: UUID = UUID(uuidString: "00000000-0000-4000-8000-000000000201")!,
        sourceRevision: Int? = nil,
        name: String? = "출근 준비",
        savedPlaceID: UUID,
        createdAt: Date = Date(timeIntervalSince1970: 1_000),
        activitySelection: FamilyActivitySelection = FamilyActivitySelection()
    ) -> RuleEditorDraft {
        RuleEditorDraft(
            id: id,
            sourceRevision: sourceRevision,
            isEnabled: true,
            name: name,
            weekdays: [.monday, .wednesday, .friday],
            startTime: TimeOfDay(hour: 6, minute: 0),
            endTime: TimeOfDay(hour: 9, minute: 0),
            savedPlaceID: savedPlaceID,
            radius: .meters1000,
            activitySelection: activitySelection,
            createdAt: createdAt
        )
    }

    private func makePlace(name: String = "집") -> SavedPlaceSnapshot {
        SavedPlaceSnapshot(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000203")!,
            name: name,
            coordinate: ReferenceLocation(latitude: 37.0, longitude: 127.0),
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func makeRule(
        id: UUID = UUID(uuidString: "00000000-0000-4000-8000-000000000201")!,
        revision: Int,
        savedPlaceID: UUID,
        name: String? = "출근 준비"
    ) -> RestrictionRuleSnapshot {
        RestrictionRuleSnapshot(
            id: id,
            revision: revision,
            name: name,
            isEnabled: true,
            weekdays: [.monday],
            startTime: TimeOfDay(hour: 6, minute: 0),
            endTime: TimeOfDay(hour: 9, minute: 0),
            savedPlaceID: savedPlaceID,
            radius: .meters1000,
            activitySelection: FamilyActivitySelection(),
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}

private actor InMemoryRuleConfigurationRepository: RuleRepository, SavedPlaceRepository {
    enum Write: Equatable, Sendable {
        case places
        case rules
    }

    private var rules: RestrictionRuleCollectionSnapshot?
    private var places: SavedPlaceCollectionSnapshot?
    private let events: RuleConfigurationRuntimeEventRecorder?
    private let shouldFailRuleSave: Bool
    private(set) var writeOrder: [Write] = []

    var storedRules: RestrictionRuleCollectionSnapshot? { rules }
    var storedPlaces: SavedPlaceCollectionSnapshot? { places }

    init(
        rules: RestrictionRuleCollectionSnapshot? = nil,
        places: SavedPlaceCollectionSnapshot? = nil,
        events: RuleConfigurationRuntimeEventRecorder? = nil,
        shouldFailRuleSave: Bool = false
    ) {
        self.rules = rules
        self.places = places
        self.events = events
        self.shouldFailRuleSave = shouldFailRuleSave
    }

    func loadRuleCollection() async throws -> RestrictionRuleCollectionSnapshot? {
        rules
    }

    func saveRuleCollection(_ collection: RestrictionRuleCollectionSnapshot) async throws {
        if shouldFailRuleSave {
            throw RuleConfigurationTestFailure.expected
        }
        rules = collection
        writeOrder.append(.rules)
        await events?.record(.rules)
    }

    func deleteRuleCollection() async throws {
        rules = nil
    }

    func loadSavedPlaceCollection() async throws -> SavedPlaceCollectionSnapshot? {
        places
    }

    func saveSavedPlaceCollection(_ collection: SavedPlaceCollectionSnapshot) async throws {
        places = collection
        writeOrder.append(.places)
        await events?.record(.places)
    }

    func deleteSavedPlaceCollection() async throws {
        places = nil
    }
}

private enum RuleConfigurationRuntimeEvent: Equatable, Sendable {
    case places
    case rules
    case runtime(ruleRevision: Int)
}

private actor RuleConfigurationRuntimeEventRecorder {
    private(set) var values: [RuleConfigurationRuntimeEvent] = []

    func record(_ event: RuleConfigurationRuntimeEvent) {
        values.append(event)
    }
}

private enum RuleConfigurationTestFailure: Error {
    case expected
}
