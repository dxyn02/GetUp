import FamilyControls
import Foundation
import Testing
@testable import GetUp

@MainActor
@Suite("App model")
struct AppModelTests {
    @Test("Today's rules come first and remaining rules use their next start")
    func sortsEverySavedRuleForHome() async throws {
        let place = makePlace()
        let today = makeRule(
            id: Self.todayRuleID,
            weekdays: [.monday],
            start: TimeOfDay(hour: 6, minute: 0),
            placeID: place.id
        )
        let tuesday = makeRule(
            id: Self.tuesdayRuleID,
            weekdays: [.tuesday],
            start: TimeOfDay(hour: 6, minute: 0),
            placeID: place.id
        )
        let wednesday = makeRule(
            id: Self.wednesdayRuleID,
            weekdays: [.wednesday],
            start: TimeOfDay(hour: 6, minute: 0),
            placeID: place.id
        )
        let repository = AppModelRepository(
            rules: RestrictionRuleCollectionSnapshot(
                revision: 1,
                rules: [wednesday, tuesday, today]
            ),
            places: SavedPlaceCollectionSnapshot(revision: 1, places: [place])
        )
        let model = makeModel(repository: repository)

        await model.load()

        #expect(model.loadingState == .loaded)
        #expect(model.homeRules.map(\.id) == [
            Self.todayRuleID,
            Self.tuesdayRuleID,
            Self.wednesdayRuleID,
        ])
        #expect(model.homeRules[0].isScheduledToday)
        #expect(!model.homeRules[1].isScheduledToday)
        #expect(model.selectedRuleID == Self.todayRuleID)
    }

    @Test("A cross-midnight rule stays in today's group while it is active")
    func activeCrossMidnightRuleIsScheduledToday() async throws {
        let place = makePlace()
        let overnight = makeRule(
            id: Self.todayRuleID,
            weekdays: [.monday],
            start: TimeOfDay(hour: 23, minute: 0),
            end: TimeOfDay(hour: 6, minute: 0),
            placeID: place.id
        )
        let repository = AppModelRepository(
            rules: RestrictionRuleCollectionSnapshot(revision: 1, rules: [overnight]),
            places: SavedPlaceCollectionSnapshot(revision: 1, places: [place])
        )
        let model = makeModel(
            repository: repository,
            now: Self.date(year: 2026, month: 8, day: 25, hour: 1)
        )

        await model.load()

        #expect(model.homeRules.count == 1)
        #expect(model.homeRules[0].isScheduledToday)
    }

    @Test("A category-only rule remains visible on the home screen")
    func categoryOnlyRuleIsVisible() async throws {
        let place = makePlace()
        var selection = FamilyActivitySelection()
        selection.categoryTokens = [
            try TestFixtures.activityCategoryToken(seed: 23),
        ]
        let rule = makeRule(
            id: Self.todayRuleID,
            weekdays: [.monday],
            start: TimeOfDay(hour: 6, minute: 0),
            placeID: place.id,
            activitySelection: selection
        )
        let repository = AppModelRepository(
            rules: RestrictionRuleCollectionSnapshot(revision: 1, rules: [rule]),
            places: SavedPlaceCollectionSnapshot(revision: 1, places: [place])
        )
        let now = Self.date(year: 2026, month: 8, day: 24, hour: 12)
        let model = AppModel(
            ruleRepository: repository,
            savedPlaceRepository: repository,
            now: { now },
            calendar: Self.calendar,
            timeZone: Self.timeZone
        )

        await model.load()

        #expect(model.homeRules.count == 1)
        #expect(model.homeRules.first?.applicationCount == 1)
        #expect(model.homeRules.first?.restrictionSelectionSummary == .multiple)
        #expect(model.homeRules.first?.applicationSummary == "여러 앱")
    }

    @Test("Editing a selected card preserves values and refreshes home after save")
    func editingAndSavingRefreshesHome() async throws {
        let place = makePlace()
        let rule = makeRule(
            id: Self.todayRuleID,
            revision: 3,
            name: "수정 전",
            weekdays: [.monday],
            start: TimeOfDay(hour: 6, minute: 0),
            placeID: place.id
        )
        let repository = AppModelRepository(
            rules: RestrictionRuleCollectionSnapshot(revision: 5, rules: [rule]),
            places: SavedPlaceCollectionSnapshot(revision: 2, places: [place])
        )
        let runtimeSync = SavedRuleRuntimeSyncRecorder()
        let model = makeModel(
            repository: repository,
            synchronizeRuntimeAfterSave: { rule in
                await runtimeSync.record(rule)
            }
        )
        await model.load()

        model.beginEditingRule(id: rule.id)
        let editor = try #require(model.editorModel)
        #expect(editor.sourceRevision == 3)
        #expect(editor.startTime == rule.startTime)
        #expect(editor.selectedSavedPlaceID == place.id)

        editor.ruleName = "수정 후"
        try await model.save(
            draft: editor.preparedDraft,
            savedPlaces: editor.savedPlaces
        )

        #expect(model.editorModel == nil)
        #expect(model.homeRules.count == 1)
        #expect(model.homeRules[0].rule.name == "수정 후")
        #expect(model.homeRules[0].rule.revision == 4)
        #expect(model.selectedRuleID == rule.id)
        #expect(await repository.storedRules?.revision == 6)
        #expect(await runtimeSync.ruleRevisions == [4])
    }

    @Test("A repository read failure exposes a retryable load state")
    func loadFailureIsReported() async {
        let repository = AppModelRepository(shouldFailLoading: true)
        let model = makeModel(repository: repository)

        await model.load()

        #expect(model.loadingState == .failed)
        #expect(model.homeRules.isEmpty)
        #expect(model.savedPlaces.isEmpty)
    }

    @Test("Deleting an edited rule refreshes home and preserves its saved place")
    func deletingEditedRuleRefreshesHome() async throws {
        let place = makePlace()
        let deletedRule = makeRule(
            id: Self.todayRuleID,
            revision: 3,
            weekdays: [.monday],
            start: TimeOfDay(hour: 6, minute: 0),
            placeID: place.id
        )
        let remainingRule = makeRule(
            id: Self.tuesdayRuleID,
            weekdays: [.tuesday],
            start: TimeOfDay(hour: 6, minute: 0),
            placeID: place.id
        )
        let repository = AppModelRepository(
            rules: RestrictionRuleCollectionSnapshot(
                revision: 5,
                rules: [deletedRule, remainingRule]
            ),
            places: SavedPlaceCollectionSnapshot(revision: 2, places: [place])
        )
        let model = makeModel(repository: repository)
        await model.load()
        model.beginEditingRule(id: deletedRule.id)

        try await model.deleteEditingRule()

        #expect(model.editorModel == nil)
        #expect(model.homeRules.map(\.id) == [remainingRule.id])
        #expect(model.selectedRuleID == remainingRule.id)
        #expect(model.savedPlaces == [place])
        #expect(await repository.storedRules?.revision == 6)
        #expect(await repository.storedPlacesSnapshot?.places == [place])
    }

    @Test("Deleting the last rule leaves an empty home selection and preserves its place")
    func deletingLastRuleClearsHomeSelection() async throws {
        let place = makePlace()
        let rule = makeRule(
            id: Self.todayRuleID,
            revision: 3,
            weekdays: [.monday],
            start: TimeOfDay(hour: 6, minute: 0),
            placeID: place.id
        )
        let repository = AppModelRepository(
            rules: RestrictionRuleCollectionSnapshot(revision: 5, rules: [rule]),
            places: SavedPlaceCollectionSnapshot(revision: 2, places: [place])
        )
        let model = makeModel(repository: repository)
        await model.load()
        model.beginEditingRule(id: rule.id)

        try await model.deleteEditingRule()

        #expect(model.editorModel == nil)
        #expect(model.homeRules.isEmpty)
        #expect(model.selectedRuleID == nil)
        #expect(model.savedPlaces == [place])
        #expect(await repository.storedRules?.revision == 6)
        #expect(await repository.storedRules?.rules.isEmpty == true)
        #expect(await repository.storedPlacesSnapshot?.places == [place])
    }

    @Test("The deletion guard rejects an active rule without writing")
    func deletionGuardRejectsActiveRule() async throws {
        let place = makePlace()
        let rule = makeRule(
            id: Self.todayRuleID,
            revision: 3,
            weekdays: [.monday],
            start: TimeOfDay(hour: 6, minute: 0),
            placeID: place.id
        )
        let repository = AppModelRepository(
            rules: RestrictionRuleCollectionSnapshot(revision: 5, rules: [rule]),
            places: SavedPlaceCollectionSnapshot(revision: 2, places: [place])
        )
        let model = makeModel(repository: repository, canDeleteRule: { _ in false })
        await model.load()
        model.beginEditingRule(id: rule.id)

        await #expect(throws: AppRuleDeletionError.activeRestriction) {
            try await model.deleteEditingRule()
        }

        #expect(model.editorModel != nil)
        #expect(await repository.storedRules?.rules == [rule])
    }

    @Test("The applied active revision guards editor save and deletion")
    func appliedActiveRevisionGuardsEditorMutations() async throws {
        let place = makePlace()
        let rule = makeRule(
            id: Self.todayRuleID,
            revision: 3,
            weekdays: [.monday],
            start: TimeOfDay(hour: 6, minute: 0),
            placeID: place.id
        )
        let repository = AppModelRepository(
            rules: RestrictionRuleCollectionSnapshot(revision: 5, rules: [rule]),
            places: SavedPlaceCollectionSnapshot(revision: 2, places: [place])
        )
        let activeState = AppliedRestrictionState(
            activeRuleRevisions: [
                ActiveRuleRevision(ruleID: rule.id, revision: rule.revision),
            ]
        )
        let model = makeModel(
            repository: repository,
            loadAppliedRestrictionState: { activeState }
        )
        await model.load()
        model.beginEditingRule(id: rule.id)
        let editor = try #require(model.editorModel)

        #expect(!editor.canModify)
        await #expect(throws: AppRuleSaveError.activeRestriction) {
            try await model.save(
                draft: editor.preparedDraft,
                savedPlaces: editor.savedPlaces
            )
        }
        await #expect(throws: AppRuleDeletionError.activeRestriction) {
            try await model.deleteEditingRule()
        }

        #expect(model.editorModel != nil)
        #expect(await repository.storedRules?.rules == [rule])
    }

    @Test("Refreshing a released active revision re-enables the open editor and re-entry")
    func releaseRefreshReEnablesEditing() async throws {
        let place = makePlace()
        let rule = makeRule(
            id: Self.todayRuleID,
            revision: 3,
            weekdays: [.monday],
            start: TimeOfDay(hour: 6, minute: 0),
            placeID: place.id
        )
        let repository = AppModelRepository(
            rules: RestrictionRuleCollectionSnapshot(revision: 5, rules: [rule]),
            places: SavedPlaceCollectionSnapshot(revision: 2, places: [place])
        )
        let stateSource = AppliedRestrictionStateSource(
            AppliedRestrictionState(
                activeRuleRevisions: [
                    ActiveRuleRevision(ruleID: rule.id, revision: rule.revision),
                ]
            )
        )
        let model = makeModel(
            repository: repository,
            loadAppliedRestrictionState: { await stateSource.load() }
        )
        await model.load()
        model.beginEditingRule(id: rule.id)
        let guardedEditor = try #require(model.editorModel)
        #expect(model.restrictionStatus.isActive(rule))
        #expect(!guardedEditor.canModify)

        await stateSource.update(AppliedRestrictionState(activeRuleRevisions: []))
        await model.refreshRestrictionStatus()

        #expect(!model.restrictionStatus.isActive(rule))
        #expect(guardedEditor.canModify)
        #expect(guardedEditor.modificationGuard == nil)

        model.cancelEditing()
        model.beginEditingRule(id: rule.id)
        let reenteredEditor = try #require(model.editorModel)
        #expect(reenteredEditor.canModify)
        #expect(reenteredEditor.setEnabled(false))

        try await model.save(
            draft: reenteredEditor.preparedDraft,
            savedPlaces: reenteredEditor.savedPlaces
        )

        #expect(model.editorModel == nil)
        #expect(model.homeRules.first?.rule.isEnabled == false)
    }

    private func makeModel(
        repository: AppModelRepository,
        now: Date = date(year: 2026, month: 8, day: 24, hour: 12),
        canDeleteRule: @escaping @Sendable (UUID) async -> Bool = { _ in true },
        loadAppliedRestrictionState: @escaping @Sendable () async -> AppliedRestrictionState = {
            AppliedRestrictionState(activeRuleRevisions: [])
        },
        synchronizeRuntimeAfterSave: @escaping @Sendable (
            RestrictionRuleSnapshot
        ) async throws -> Void = { _ in }
    ) -> AppModel {
        AppModel(
            ruleRepository: repository,
            savedPlaceRepository: repository,
            now: { now },
            calendar: Self.calendar,
            timeZone: Self.timeZone,
            applicationTokenCounter: { _ in 1 },
            applicationCountForRule: { _ in 1 },
            canDeleteRule: canDeleteRule,
            synchronizeRuntimeAfterSave: synchronizeRuntimeAfterSave,
            loadAppliedRestrictionState: loadAppliedRestrictionState
        )
    }

    private func makePlace() -> SavedPlaceSnapshot {
        SavedPlaceSnapshot(
            id: Self.placeID,
            name: "집",
            coordinate: ReferenceLocation(latitude: 37.0, longitude: 127.0),
            createdAt: Self.referenceDate,
            updatedAt: Self.referenceDate
        )
    }

    private func makeRule(
        id: UUID,
        revision: Int = 1,
        name: String = "테스트 규칙",
        weekdays: Set<Weekday>,
        start: TimeOfDay,
        end: TimeOfDay = TimeOfDay(hour: 9, minute: 0),
        placeID: UUID,
        activitySelection: FamilyActivitySelection = FamilyActivitySelection()
    ) -> RestrictionRuleSnapshot {
        RestrictionRuleSnapshot(
            id: id,
            revision: revision,
            name: name,
            isEnabled: true,
            weekdays: weekdays,
            startTime: start,
            endTime: end,
            savedPlaceID: placeID,
            radius: .meters1000,
            activitySelection: activitySelection,
            createdAt: Self.referenceDate,
            updatedAt: Self.referenceDate
        )
    }

    private static func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int
    ) -> Date {
        calendar.date(
            from: DateComponents(
                timeZone: timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour
            )
        )!
    }

    private static let timeZone = TimeZone(secondsFromGMT: 0)!
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
    private static let referenceDate = date(
        year: 2026,
        month: 8,
        day: 24,
        hour: 0
    )
    private static let placeID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000601"
    )!
    private static let todayRuleID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000611"
    )!
    private static let tuesdayRuleID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000612"
    )!
    private static let wednesdayRuleID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000613"
    )!
}

private actor SavedRuleRuntimeSyncRecorder {
    private(set) var ruleRevisions: [Int] = []

    func record(_ rule: RestrictionRuleSnapshot) {
        ruleRevisions.append(rule.revision)
    }
}

private actor AppliedRestrictionStateSource {
    private var state: AppliedRestrictionState

    init(_ state: AppliedRestrictionState) {
        self.state = state
    }

    func load() -> AppliedRestrictionState {
        state
    }

    func update(_ state: AppliedRestrictionState) {
        self.state = state
    }
}

private actor AppModelRepository: RuleRepository, SavedPlaceRepository {
    private(set) var storedRules: RestrictionRuleCollectionSnapshot?
    private var storedPlaces: SavedPlaceCollectionSnapshot?
    private let shouldFailLoading: Bool

    init(
        rules: RestrictionRuleCollectionSnapshot? = nil,
        places: SavedPlaceCollectionSnapshot? = nil,
        shouldFailLoading: Bool = false
    ) {
        storedRules = rules
        storedPlaces = places
        self.shouldFailLoading = shouldFailLoading
    }

    func loadRuleCollection() async throws -> RestrictionRuleCollectionSnapshot? {
        if shouldFailLoading {
            throw AppModelRepositoryError.readFailed
        }
        return storedRules
    }

    func saveRuleCollection(_ collection: RestrictionRuleCollectionSnapshot) async throws {
        storedRules = collection
    }

    func deleteRuleCollection() async throws {
        storedRules = nil
    }

    func loadSavedPlaceCollection() async throws -> SavedPlaceCollectionSnapshot? {
        if shouldFailLoading {
            throw AppModelRepositoryError.readFailed
        }
        return storedPlaces
    }

    func saveSavedPlaceCollection(_ collection: SavedPlaceCollectionSnapshot) async throws {
        storedPlaces = collection
    }

    func deleteSavedPlaceCollection() async throws {
        storedPlaces = nil
    }

    var storedPlacesSnapshot: SavedPlaceCollectionSnapshot? { storedPlaces }
}

private enum AppModelRepositoryError: Error {
    case readFailed
}
