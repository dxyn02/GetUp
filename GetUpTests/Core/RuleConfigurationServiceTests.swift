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

    private func makeService(
        repository: InMemoryRuleConfigurationRepository
    ) -> RuleConfigurationService {
        RuleConfigurationService(
            ruleRepository: repository,
            savedPlaceRepository: repository,
            now: { Date(timeIntervalSince1970: 2_000) },
            applicationTokenCounter: { _ in 1 }
        )
    }

    private func makeDraft(
        id: UUID = UUID(uuidString: "00000000-0000-4000-8000-000000000201")!,
        sourceRevision: Int? = nil,
        name: String? = "출근 준비",
        savedPlaceID: UUID,
        createdAt: Date = Date(timeIntervalSince1970: 1_000)
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
            activitySelection: FamilyActivitySelection(),
            createdAt: createdAt
        )
    }

    private func makePlace() -> SavedPlaceSnapshot {
        SavedPlaceSnapshot(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000203")!,
            name: "집",
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
    private(set) var writeOrder: [Write] = []

    var storedRules: RestrictionRuleCollectionSnapshot? { rules }
    var storedPlaces: SavedPlaceCollectionSnapshot? { places }

    init(
        rules: RestrictionRuleCollectionSnapshot? = nil,
        places: SavedPlaceCollectionSnapshot? = nil
    ) {
        self.rules = rules
        self.places = places
    }

    func loadRuleCollection() async throws -> RestrictionRuleCollectionSnapshot? {
        rules
    }

    func saveRuleCollection(_ collection: RestrictionRuleCollectionSnapshot) async throws {
        rules = collection
        writeOrder.append(.rules)
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
    }

    func deleteSavedPlaceCollection() async throws {
        places = nil
    }
}
