@preconcurrency import FamilyControls
import Foundation
import Observation

enum AppLocalizedCopy {
    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }

    static func format(
        _ key: String.LocalizationValue,
        _ arguments: CVarArg...
    ) -> String {
        String(format: string(key), arguments: arguments)
    }

    static func savedPlaceName(_ storedName: String) -> String {
        switch storedName {
        case "집": string("집")
        case "회사": string("회사")
        case "기존 장소": string("기존 장소")
        default: storedName
        }
    }
}

enum AppLoadingState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed
}

enum AppRuleDeletionError: Error, Equatable, Sendable {
    case persistedRuleRequired
    case activeRestriction
}

enum AppRuleSaveError: Error, Equatable, Sendable {
    case activeRestriction
}

enum AppSavedPlaceDeletionError: Error, Equatable, Sendable {
    case notFound
    case protectedPreset
    case inUse(ruleCount: Int)
}

struct HomeRuleItem: Equatable, Identifiable, @unchecked Sendable {
    let rule: RestrictionRuleSnapshot
    let savedPlace: SavedPlaceSnapshot
    let isScheduledToday: Bool
    let nextStart: Date
    let sortDate: Date
    let applicationCount: Int
    let accessibilityID: String

    var id: UUID { rule.id }
}

@MainActor
@Observable
final class AppModel {
    @ObservationIgnored private let ruleRepository: any RuleRepository
    @ObservationIgnored private let savedPlaceRepository: any SavedPlaceRepository
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private let makeID: () -> UUID
    @ObservationIgnored private let applicationTokenCounter: @Sendable (
        FamilyActivitySelection
    ) -> Int
    @ObservationIgnored private let applicationCountForRule: (RestrictionRuleSnapshot) -> Int
    @ObservationIgnored private let ruleAccessibilityID: (RestrictionRuleSnapshot) -> String
    @ObservationIgnored private let bootstrap: @Sendable () async throws -> Void
    @ObservationIgnored private let synchronizeRuntimeAfterSave: @Sendable (
        RestrictionRuleSnapshot
    ) async throws -> Void
    @ObservationIgnored private let loadAppliedRestrictionState: @Sendable () async -> AppliedRestrictionState
    @ObservationIgnored private let canDeleteRule: @Sendable (UUID) async -> Bool
    @ObservationIgnored private let initialEditorDraft: RuleEditorDraft?

    private(set) var loadingState: AppLoadingState = .idle
    private(set) var homeRules: [HomeRuleItem] = []
    private(set) var savedPlaces: [SavedPlaceSnapshot] = []
    private(set) var restrictionStatus = RestrictionStatusModel()
    private(set) var editorModel: RuleEditorModel?
    var selectedRuleID: UUID?

    init(
        ruleRepository: any RuleRepository,
        savedPlaceRepository: any SavedPlaceRepository,
        now: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent,
        makeID: @escaping () -> UUID = UUID.init,
        applicationTokenCounter: @escaping @Sendable (FamilyActivitySelection) -> Int = {
            $0.restrictionTargetCount
        },
        applicationCountForRule: ((RestrictionRuleSnapshot) -> Int)? = nil,
        ruleAccessibilityID: @escaping (RestrictionRuleSnapshot) -> String = {
            $0.id.uuidString.lowercased()
        },
        initialEditorDraft: RuleEditorDraft? = nil,
        canDeleteRule: @escaping @Sendable (UUID) async -> Bool = { _ in true },
        bootstrap: @escaping @Sendable () async throws -> Void = {},
        synchronizeRuntimeAfterSave: @escaping @Sendable (
            RestrictionRuleSnapshot
        ) async throws -> Void = { _ in },
        loadAppliedRestrictionState: @escaping @Sendable () async -> AppliedRestrictionState = {
            AppliedRestrictionState(activeRuleRevisions: [])
        }
    ) {
        self.ruleRepository = ruleRepository
        self.savedPlaceRepository = savedPlaceRepository
        self.now = now
        self.calendar = calendar
        self.timeZone = timeZone
        self.makeID = makeID
        self.applicationTokenCounter = applicationTokenCounter
        self.applicationCountForRule = applicationCountForRule ?? {
            $0.activitySelection.restrictionTargetCount
        }
        self.ruleAccessibilityID = ruleAccessibilityID
        self.initialEditorDraft = initialEditorDraft
        self.canDeleteRule = canDeleteRule
        self.bootstrap = bootstrap
        self.synchronizeRuntimeAfterSave = synchronizeRuntimeAfterSave
        self.loadAppliedRestrictionState = loadAppliedRestrictionState
    }

    var canDeleteEditingRule: Bool {
        editorModel?.sourceRevision != nil
    }

    func load() async {
        loadingState = .loading

        do {
            try await bootstrap()
            async let loadedRules = ruleRepository.loadRuleCollection()
            async let loadedPlaces = savedPlaceRepository.loadSavedPlaceCollection()
            async let appliedState = loadAppliedRestrictionState()
            let snapshots = try await (loadedRules, loadedPlaces, appliedState)

            apply(
                rules: snapshots.0?.rules ?? [],
                places: snapshots.1?.places ?? []
            )
            restrictionStatus = RestrictionStatusModel(appliedState: snapshots.2)
            loadingState = .loaded

            if let initialEditorDraft, editorModel == nil {
                editorModel = makeEditorModel(draft: initialEditorDraft)
                refreshEditorModificationGuard()
            }
        } catch is CancellationError {
            loadingState = .idle
        } catch {
            homeRules = []
            savedPlaces = []
            editorModel = nil
            restrictionStatus = RestrictionStatusModel()
            loadingState = .failed
        }
    }

    func beginCreatingRule() {
        editorModel = makeEditorModel(draft: nil)
    }

    func beginEditingRule(id: UUID) {
        guard let item = homeRules.first(where: { $0.id == id }) else {
            return
        }

        let rule = item.rule
        let draft = RuleEditorDraft(
            id: rule.id,
            sourceRevision: rule.revision,
            isEnabled: rule.isEnabled,
            name: rule.name,
            weekdays: rule.weekdays,
            startTime: rule.startTime,
            endTime: rule.endTime,
            savedPlaceID: rule.savedPlaceID,
            radius: rule.radius,
            activitySelection: rule.activitySelection,
            createdAt: rule.createdAt
        )
        let count = item.applicationCount
        editorModel = makeEditorModel(
            draft: draft,
            modificationGuard: modificationGuard(for: item),
            tokenCounter: { _ in count }
        )
    }

    func cancelEditing() {
        editorModel = nil
    }

    func save(
        draft: RuleEditorDraft,
        savedPlaces: [SavedPlaceSnapshot]
    ) async throws {
        if editorModel?.ruleID == draft.id, editorModel?.canModify == false {
            throw AppRuleSaveError.activeRestriction
        }

        let service = RuleConfigurationService(
            ruleRepository: ruleRepository,
            savedPlaceRepository: savedPlaceRepository,
            now: now,
            applicationTokenCounter: applicationTokenCounter,
            synchronizeRuntimeAfterSave: synchronizeRuntimeAfterSave
        )
        let saved = try await service.save(
            draft: draft,
            savedPlaces: savedPlaces
        )

        apply(rules: saved.rules.rules, places: saved.savedPlaces.places)
        await refreshRestrictionStatus()
        selectedRuleID = saved.rule.id
        editorModel = nil
    }

    func refreshRestrictionStatus() async {
        restrictionStatus = RestrictionStatusModel(
            appliedState: await loadAppliedRestrictionState()
        )
        refreshEditorModificationGuard()
    }

    func deleteEditingRule() async throws {
        guard
            let editorModel,
            let sourceRevision = editorModel.sourceRevision
        else {
            throw AppRuleDeletionError.persistedRuleRequired
        }
        let ruleID = editorModel.preparedDraft.id
        guard editorModel.canModify else {
            throw AppRuleDeletionError.activeRestriction
        }
        guard await canDeleteRule(ruleID) else {
            throw AppRuleDeletionError.activeRestriction
        }

        let service = RuleConfigurationService(
            ruleRepository: ruleRepository,
            savedPlaceRepository: savedPlaceRepository,
            now: now,
            applicationTokenCounter: applicationTokenCounter
        )
        let updatedRules = try await service.delete(
            ruleID: ruleID,
            sourceRevision: sourceRevision
        )

        apply(rules: updatedRules.rules, places: savedPlaces)
        self.editorModel = nil
    }

    func deleteSavedPlace(id: UUID) async throws {
        if !savedPlaces.contains(where: { $0.id == id }) {
            guard let draftOnlyPlace = editorModel?.savedPlaces.first(where: {
                $0.id == id
            }) else {
                throw AppSavedPlaceDeletionError.notFound
            }
            guard !Self.isProtectedPreset(draftOnlyPlace) else {
                throw AppSavedPlaceDeletionError.protectedPreset
            }

            editorModel?.removeSavedPlace(id: id)
            return
        }

        let service = RuleConfigurationService(
            ruleRepository: ruleRepository,
            savedPlaceRepository: savedPlaceRepository,
            now: now,
            applicationTokenCounter: applicationTokenCounter
        )

        let updatedPlaces: SavedPlaceCollectionSnapshot
        do {
            updatedPlaces = try await service.deleteSavedPlace(id: id)
        } catch RuleConfigurationServiceError.savedPlaceNotFound {
            throw AppSavedPlaceDeletionError.notFound
        } catch RuleConfigurationServiceError.protectedSavedPlace {
            throw AppSavedPlaceDeletionError.protectedPreset
        } catch RuleConfigurationServiceError.savedPlaceInUse(let ruleIDs) {
            throw AppSavedPlaceDeletionError.inUse(ruleCount: ruleIDs.count)
        }

        savedPlaces = updatedPlaces.places
        editorModel?.removeSavedPlace(id: id)
    }

    private static func isProtectedPreset(_ place: SavedPlaceSnapshot) -> Bool {
        let key = SavedPlaceNamePolicy.uniquenessKey(place.name)
        return ["집", "회사"].contains {
            SavedPlaceNamePolicy.uniquenessKey($0) == key
        }
    }

    private func makeEditorModel(
        draft: RuleEditorDraft?,
        modificationGuard: RestrictionModificationGuard? = nil,
        tokenCounter: ((FamilyActivitySelection) -> Int)? = nil
    ) -> RuleEditorModel {
        RuleEditorModel(
            draft: draft,
            savedPlaces: savedPlaces,
            modificationGuard: modificationGuard,
            makeID: makeID,
            now: now,
            calendar: calendar,
            applicationTokenCounter: tokenCounter ?? applicationTokenCounter
        )
    }

    private func refreshEditorModificationGuard() {
        guard let editorModel, editorModel.mode == .editing else {
            return
        }

        let item = homeRules.first { $0.id == editorModel.ruleID }
        editorModel.updateModificationGuard(item.flatMap(modificationGuard(for:)))
    }

    private func modificationGuard(
        for item: HomeRuleItem
    ) -> RestrictionModificationGuard? {
        guard restrictionStatus.isActive(item.rule) else {
            return nil
        }

        return RestrictionModificationGuard(
            savedPlaceName: item.savedPlace.name,
            radius: item.rule.radius,
            endTime: item.rule.endTime
        )
    }

    private func apply(
        rules: [RestrictionRuleSnapshot],
        places: [SavedPlaceSnapshot]
    ) {
        savedPlaces = places
        let placesByID = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
        let currentDate = now()

        homeRules = rules.compactMap { rule in
            guard
                let place = placesByID[rule.savedPlaceID],
                let schedule = HomeRuleSchedule(
                    rule: rule,
                    now: currentDate,
                    calendar: calendar,
                    timeZone: timeZone
                )
            else {
                return nil
            }

            let applicationCount = applicationCountForRule(rule)
            guard applicationCount > 0 else {
                return nil
            }

            return HomeRuleItem(
                rule: rule,
                savedPlace: place,
                isScheduledToday: schedule.isScheduledToday,
                nextStart: schedule.nextStart,
                sortDate: schedule.sortDate,
                applicationCount: applicationCount,
                accessibilityID: ruleAccessibilityID(rule)
            )
        }
        .sorted(by: HomeRuleSchedule.isOrderedBefore)

        if let selectedRuleID, homeRules.contains(where: { $0.id == selectedRuleID }) {
            self.selectedRuleID = selectedRuleID
        } else {
            selectedRuleID = homeRules.first?.id
        }
    }
}

private struct HomeRuleSchedule {
    let isScheduledToday: Bool
    let nextStart: Date
    let sortDate: Date

    init?(
        rule: RestrictionRuleSnapshot,
        now: Date,
        calendar inputCalendar: Calendar,
        timeZone: TimeZone
    ) {
        guard
            !rule.weekdays.isEmpty,
            (0...23).contains(rule.startTime.hour),
            (0...59).contains(rule.startTime.minute),
            ScheduleEvaluator.isEndTimeSelectable(
                startTime: rule.startTime,
                endTime: rule.endTime
            )
        else {
            return nil
        }

        var calendar = inputCalendar
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        let weekday = Self.weekday(for: calendar.component(.weekday, from: today))
        let isActive = ScheduleEvaluator.isActive(
            weekdays: rule.weekdays,
            startTime: rule.startTime,
            endTime: rule.endTime,
            at: now,
            calendar: calendar,
            timeZone: timeZone
        )

        let startsToday = weekday.map(rule.weekdays.contains) ?? false
        isScheduledToday = rule.isEnabled && (startsToday || isActive)

        guard let nextStart = Self.nextStart(
            for: rule,
            at: now,
            calendar: calendar
        ) else {
            return nil
        }
        self.nextStart = nextStart

        if startsToday,
           let todayStart = Self.start(
               on: today,
               time: rule.startTime,
               calendar: calendar
           ) {
            sortDate = todayStart
        } else if isActive,
                  let previousDay = calendar.date(byAdding: .day, value: -1, to: today),
                  let previousStart = Self.start(
                      on: previousDay,
                      time: rule.startTime,
                      calendar: calendar
                  ) {
            sortDate = previousStart
        } else {
            sortDate = nextStart
        }
    }

    static func isOrderedBefore(_ lhs: HomeRuleItem, _ rhs: HomeRuleItem) -> Bool {
        if lhs.isScheduledToday != rhs.isScheduledToday {
            return lhs.isScheduledToday
        }
        if lhs.sortDate != rhs.sortDate {
            return lhs.sortDate < rhs.sortDate
        }
        if lhs.rule.createdAt != rhs.rule.createdAt {
            return lhs.rule.createdAt < rhs.rule.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func nextStart(
        for rule: RestrictionRuleSnapshot,
        at now: Date,
        calendar: Calendar
    ) -> Date? {
        let today = calendar.startOfDay(for: now)

        for dayOffset in 0...7 {
            guard
                let day = calendar.date(byAdding: .day, value: dayOffset, to: today),
                let weekday = weekday(for: calendar.component(.weekday, from: day)),
                rule.weekdays.contains(weekday),
                let candidate = start(
                    on: day,
                    time: rule.startTime,
                    calendar: calendar
                ),
                candidate >= now
            else {
                continue
            }

            return candidate
        }

        return nil
    }

    private static func start(
        on day: Date,
        time: TimeOfDay,
        calendar: Calendar
    ) -> Date? {
        calendar.nextDate(
            after: day.addingTimeInterval(-1),
            matching: DateComponents(hour: time.hour, minute: time.minute),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }

    private static func weekday(for calendarWeekday: Int) -> Weekday? {
        switch calendarWeekday {
        case 1: .sunday
        case 2: .monday
        case 3: .tuesday
        case 4: .wednesday
        case 5: .thursday
        case 6: .friday
        case 7: .saturday
        default: nil
        }
    }
}
