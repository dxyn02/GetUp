import FamilyControls
import Foundation
import Testing
@testable import GetUp

@MainActor
@Suite("Rule editor model")
struct RuleEditorModelTests {
    @Test("A new rule keeps its optional name but reports every required input")
    func newRuleStartsWithRequiredValidationErrors() {
        let model = makeModel()
        model.ruleName = "   "

        #expect(model.normalizedRuleName == nil)
        #expect(model.validationErrors.contains(.weekdaysRequired))
        #expect(model.validationErrors.contains(.savedPlaceRequired))
        #expect(model.validationErrors.contains(.applicationTokenRequired))
        #expect(!model.canSave)
    }

    @Test("A complete draft is valid and normalizes its optional rule name")
    func completeDraftIsValid() {
        let savedPlace = makeSavedPlace()
        let model = makeModel(
            savedPlaces: [savedPlace],
            applicationTokenCount: 1
        )
        model.ruleName = "  아침 집중  "
        model.weekdays = [.monday, .wednesday, .friday]
        model.selectSavedPlace(id: savedPlace.id)
        model.replaceActivitySelection(
            with: FamilyActivitySelection(includeEntireCategory: true)
        )

        #expect(model.normalizedRuleName == "아침 집중")
        #expect(model.validationErrors.isEmpty)
        #expect(model.canSave)
        #expect(model.preparedDraft.name == "아침 집중")
        #expect(model.preparedDraft.savedPlaceID == savedPlace.id)
    }

    @Test("Editing preserves the selected rule identity, revision, and values")
    func editingPreservesExistingDraft() {
        let savedPlace = makeSavedPlace()
        let draft = RuleEditorDraft(
            id: Self.ruleID,
            sourceRevision: 7,
            isEnabled: true,
            name: "퇴근 준비",
            weekdays: [.tuesday, .thursday],
            startTime: TimeOfDay(hour: 18, minute: 0),
            endTime: TimeOfDay(hour: 20, minute: 0),
            savedPlaceID: savedPlace.id,
            radius: .meters500,
            activitySelection: FamilyActivitySelection(includeEntireCategory: true),
            createdAt: TestFixtures.now
        )

        let model = makeModel(draft: draft, savedPlaces: [savedPlace])

        #expect(model.mode == .editing)
        #expect(model.preparedDraft == draft)
        #expect(model.selectedSavedPlace == savedPlace)
    }

    @Test("An active restriction keeps disabling and saving guarded until release")
    func activeRestrictionGuardsMutations() {
        let savedPlace = makeSavedPlace()
        let guardContext = RestrictionModificationGuard(
            savedPlaceName: "집",
            radius: .meters1000,
            endTime: TimeOfDay(hour: 9, minute: 0)
        )
        let draft = RuleEditorDraft(
            id: Self.ruleID,
            sourceRevision: 7,
            isEnabled: true,
            name: "출근 준비",
            weekdays: [.monday],
            startTime: TimeOfDay(hour: 6, minute: 0),
            endTime: TimeOfDay(hour: 9, minute: 0),
            savedPlaceID: savedPlace.id,
            radius: .meters1000,
            activitySelection: FamilyActivitySelection(includeEntireCategory: true),
            createdAt: TestFixtures.now
        )
        let model = makeModel(
            draft: draft,
            savedPlaces: [savedPlace],
            applicationTokenCount: 1,
            modificationGuard: guardContext
        )

        #expect(!model.canModify)
        #expect(!model.canSave)
        #expect(!model.setEnabled(false))
        #expect(model.isEnabled)
        #expect(
            model.modificationGuard?.message
                == "집 1km 밖으로 이동하거나 09:00 AM이 지나면 규칙을 수정·끄기·삭제할 수 있어요."
        )

        model.updateModificationGuard(nil)

        #expect(model.canModify)
        #expect(model.canSave)
        #expect(model.setEnabled(false))
        #expect(!model.isEnabled)
    }

    @Test("Reusing a saved place selects it without duplicating the collection")
    func reusedPlaceIsSelectedWithoutDuplication() {
        let savedPlace = makeSavedPlace()
        let model = makeModel(savedPlaces: [savedPlace])

        model.applyLocationCompletion(.reused(savedPlace))

        #expect(model.savedPlaces == [savedPlace])
        #expect(model.selectedSavedPlaceID == savedPlace.id)
        #expect(model.selectedSavedPlace == savedPlace)
    }

    @Test("Confirming a new location creates and selects a reusable saved place")
    func confirmedLocationCreatesSavedPlace() {
        let model = makeModel()
        let coordinate = ReferenceLocation(latitude: 35.1796, longitude: 129.0756)

        model.applyLocationCompletion(
            .confirmed(SavedPlaceDraft(name: "부산 집", coordinate: coordinate))
        )

        #expect(model.savedPlaces.count == 1)
        #expect(model.selectedSavedPlaceID == Self.newPlaceID)
        #expect(
            model.selectedSavedPlace
                == SavedPlaceSnapshot(
                    id: Self.newPlaceID,
                    name: "부산 집",
                    coordinate: coordinate,
                    createdAt: TestFixtures.now,
                    updatedAt: TestFixtures.now
                )
        )
    }

    @Test("A duplicate place name never appends another saved place")
    func duplicatePlaceNameDoesNotAppend() {
        let savedPlace = makeSavedPlace()
        let model = makeModel(savedPlaces: [savedPlace])

        model.applyLocationCompletion(
            .confirmed(
                SavedPlaceDraft(
                    name: " 회사 ",
                    coordinate: ReferenceLocation(latitude: 35, longitude: 129)
                )
            )
        )

        #expect(model.savedPlaces == [savedPlace])
        #expect(model.selectedSavedPlaceID == savedPlace.id)
    }

    @Test("Cancelling location selection preserves the current draft")
    func cancelledLocationPreservesDraft() {
        let savedPlace = makeSavedPlace()
        let model = makeModel(savedPlaces: [savedPlace])
        model.selectSavedPlace(id: savedPlace.id)

        model.applyLocationCompletion(.cancelled)

        #expect(model.selectedSavedPlaceID == savedPlace.id)
        #expect(model.savedPlaces == [savedPlace])
    }

    @Test("A removed saved place invalidates only the draft that referenced it")
    func removedSavedPlaceInvalidatesDraft() {
        let savedPlace = makeSavedPlace()
        let model = makeModel(savedPlaces: [savedPlace])
        model.weekdays = [.monday]
        model.selectSavedPlace(id: savedPlace.id)

        model.replaceSavedPlaces(with: [])

        #expect(model.selectedSavedPlaceID == savedPlace.id)
        #expect(model.validationErrors.contains(.savedPlaceNotFound))
    }

    @Test("New editors keep separate stable rule identities")
    func newRulesHaveIndependentIdentities() {
        let first = makeModel(ruleID: Self.ruleID)
        let second = makeModel(ruleID: Self.secondRuleID)

        first.ruleName = "첫 규칙"
        second.ruleName = "둘째 규칙"

        #expect(first.preparedDraft.id == Self.ruleID)
        #expect(second.preparedDraft.id == Self.secondRuleID)
        #expect(first.preparedDraft.name == "첫 규칙")
        #expect(second.preparedDraft.name == "둘째 규칙")
    }

    private func makeModel(
        draft: RuleEditorDraft? = nil,
        savedPlaces: [SavedPlaceSnapshot] = [],
        ruleID: UUID = RuleEditorModelTests.ruleID,
        applicationTokenCount: Int = 0,
        modificationGuard: RestrictionModificationGuard? = nil
    ) -> RuleEditorModel {
        RuleEditorModel(
            draft: draft,
            savedPlaces: savedPlaces,
            modificationGuard: modificationGuard,
            makeID: IDSequence([ruleID, Self.newPlaceID]).next,
            now: { TestFixtures.now },
            applicationTokenCounter: { _ in applicationTokenCount }
        )
    }

    private func makeSavedPlace() -> SavedPlaceSnapshot {
        SavedPlaceSnapshot(
            id: Self.savedPlaceID,
            name: "회사",
            coordinate: ReferenceLocation(latitude: 37.4021, longitude: 127.1087),
            createdAt: TestFixtures.now,
            updatedAt: TestFixtures.now
        )
    }

    private static let ruleID = UUID(
        uuidString: "27B602AE-83AB-4D7C-A8FD-78AE2C53798F"
    )!
    private static let secondRuleID = UUID(
        uuidString: "0607DA17-E687-4977-BA38-F810990ED3C9"
    )!
    private static let savedPlaceID = UUID(
        uuidString: "13BE96A0-3E22-4E3E-BDF6-3DA784462F54"
    )!
    private static let newPlaceID = UUID(
        uuidString: "9D32DA2B-612E-43FE-8762-F6A8D623082E"
    )!
}

private final class IDSequence: @unchecked Sendable {
    private var values: [UUID]

    init(_ values: [UUID]) {
        self.values = values
    }

    func next() -> UUID {
        values.removeFirst()
    }
}
