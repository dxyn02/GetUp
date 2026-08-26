@preconcurrency import CoreLocation
@preconcurrency import FamilyControls
import Foundation
@preconcurrency import ManagedSettings

enum ManagedSettingsRestrictionAdapterError: Error, Equatable, Sendable {
    case missingAppGroupIdentifier
    case sharedDefaultsUnavailable
    case storeVerificationFailed
}

struct ManagedSettingsShieldSelection: Equatable {
    let applications: Set<ApplicationToken>?
    let applicationCategories: ShieldSettings.ActivityCategoryPolicy<Application>?
    let webDomains: Set<WebDomainToken>?

    static let empty = ManagedSettingsShieldSelection(
        applications: nil,
        applicationCategories: nil,
        webDomains: nil
    )

    init(
        applications: Set<ApplicationToken>?,
        applicationCategories: ShieldSettings.ActivityCategoryPolicy<Application>?,
        webDomains: Set<WebDomainToken>?
    ) {
        self.applications = applications
        self.applicationCategories = applicationCategories
        self.webDomains = webDomains
    }

    init(rules: [RestrictionRuleSnapshot]) {
        let applications = rules.reduce(into: Set<ApplicationToken>()) {
            $0.formUnion($1.activitySelection.applicationTokens)
        }
        let categories = rules.reduce(into: Set<ActivityCategoryToken>()) {
            $0.formUnion($1.activitySelection.categoryTokens)
        }
        let webDomains = rules.reduce(into: Set<WebDomainToken>()) {
            $0.formUnion($1.activitySelection.webDomainTokens)
        }

        self.applications = applications.isEmpty ? nil : applications
        applicationCategories = categories.isEmpty
            ? nil
            : .specific(categories)
        self.webDomains = webDomains.isEmpty ? nil : webDomains
    }
}

protocol ManagedSettingsStoreAccess {
    func shieldSelection(
        named storeName: String
    ) -> ManagedSettingsShieldSelection
    func setShieldSelection(
        _ selection: ManagedSettingsShieldSelection,
        named storeName: String
    )
}

protocol RestrictionApplicationStateStoring: Sendable {
    func currentState() async -> AppliedRestrictionState
    func saveState(_ newState: AppliedRestrictionState) async
}

final class SystemManagedSettingsStoreAccess: ManagedSettingsStoreAccess {
    private var stores: [String: ManagedSettingsStore] = [:]

    func shieldSelection(
        named storeName: String
    ) -> ManagedSettingsShieldSelection {
        let shield = store(named: storeName).shield
        return ManagedSettingsShieldSelection(
            applications: shield.applications,
            applicationCategories: shield.applicationCategories,
            webDomains: shield.webDomains
        )
    }

    func setShieldSelection(
        _ selection: ManagedSettingsShieldSelection,
        named storeName: String
    ) {
        let store = store(named: storeName)
        store.shield.applications = selection.applications
        store.shield.applicationCategories = selection.applicationCategories
        store.shield.webDomains = selection.webDomains
    }

    private func store(named storeName: String) -> ManagedSettingsStore {
        if let existingStore = stores[storeName] {
            return existingStore
        }

        let store = ManagedSettingsStore(
            named: ManagedSettingsStore.Name(storeName)
        )
        stores[storeName] = store
        return store
    }
}

actor UserDefaultsRestrictionApplicationStateStore:
    RestrictionApplicationStateStoring
{
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func currentState() -> AppliedRestrictionState {
        RestrictionApplicationStateDefaultsCodec.load(from: defaults)
    }

    func saveState(_ newState: AppliedRestrictionState) {
        RestrictionApplicationStateDefaultsCodec.save(newState, to: defaults)
    }
}

enum RestrictionApplicationStateDefaultsCodec {
    static func load(from defaults: UserDefaults) -> AppliedRestrictionState {
        guard
            let data = defaults.data(
                forKey: SharedIdentifiers.activeRuleRevisionsDefaultsKey
            ),
            let revisions = try? JSONDecoder().decode(
                Set<ActiveRuleRevision>.self,
                from: data
            )
        else {
            return AppliedRestrictionState(
                activeRuleRevisions: [],
                requiresReset: defaults.bool(
                    forKey: SharedIdentifiers.legacyRestrictionIsAppliedDefaultsKey
                )
            )
        }
        return AppliedRestrictionState(activeRuleRevisions: revisions)
    }

    static func save(
        _ state: AppliedRestrictionState,
        to defaults: UserDefaults
    ) {
        if let data = try? JSONEncoder().encode(state.activeRuleRevisions) {
            defaults.set(
                data,
                forKey: SharedIdentifiers.activeRuleRevisionsDefaultsKey
            )
        } else {
            defaults.removeObject(
                forKey: SharedIdentifiers.activeRuleRevisionsDefaultsKey
            )
        }
        defaults.removeObject(
            forKey: SharedIdentifiers.legacyRestrictionIsAppliedDefaultsKey
        )
        defaults.removeObject(
            forKey: SharedIdentifiers.legacyRestrictionRuleRevisionDefaultsKey
        )
    }
}

struct DeviceActivityIntervalStartSnapshot {
    let rules: [RestrictionRuleSnapshot]
    let locationConditions: [LocationConditionSnapshot]
}

private struct DeviceActivityIntervalStartSnapshotFileReader {
    let containerURL: URL

    func load() throws -> DeviceActivityIntervalStartSnapshot {
        let ruleCollection = try loadCollection(
            RestrictionRuleCollectionSnapshot.self,
            fileName: SharedIdentifiers.restrictionRulesFileName
        )
        if let ruleCollection,
           ruleCollection.schemaVersion
            != RestrictionRuleCollectionSnapshot.currentSchemaVersion
        {
            throw SharedSnapshotRepositoryError.unsupportedSchema(
                fileName: SharedIdentifiers.restrictionRulesFileName,
                found: ruleCollection.schemaVersion,
                supported: RestrictionRuleCollectionSnapshot.currentSchemaVersion
            )
        }

        let locationCollection = try loadCollection(
            LocationConditionCollectionSnapshot.self,
            fileName: SharedIdentifiers.locationConditionFileName
        )
        if let locationCollection,
           locationCollection.schemaVersion
            != LocationConditionCollectionSnapshot.currentSchemaVersion
        {
            throw SharedSnapshotRepositoryError.unsupportedSchema(
                fileName: SharedIdentifiers.locationConditionFileName,
                found: locationCollection.schemaVersion,
                supported: LocationConditionCollectionSnapshot.currentSchemaVersion
            )
        }

        return DeviceActivityIntervalStartSnapshot(
            rules: ruleCollection?.rules ?? [],
            locationConditions: locationCollection?.conditions ?? []
        )
    }

    private func loadCollection<Collection: Decodable>(
        _ type: Collection.Type,
        fileName: String
    ) throws -> Collection? {
        let fileURL = containerURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw SharedSnapshotRepositoryError.readFailed(fileName: fileName)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw SharedSnapshotRepositoryError.decodingFailed(
                fileName: fileName
            )
        }
    }
}

struct DeviceActivityAuthorizationSnapshotReader {
    typealias CurrentSnapshot = () -> AuthorizationSnapshot

    private static let maximumTrustedAge: TimeInterval = 24 * 60 * 60

    private let defaults: UserDefaults
    private let currentSnapshot: CurrentSnapshot
    private let now: () -> Date

    init(
        defaults: UserDefaults,
        currentSnapshot: @escaping CurrentSnapshot = Self.systemSnapshot,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.currentSnapshot = currentSnapshot
        self.now = now
    }

    func snapshot() -> AuthorizationSnapshot {
        let current = currentSnapshot()
        if let record = AuthorizationSnapshotDefaultsCodec.load(from: defaults) {
            let age = now().timeIntervalSince(record.observedAt)
            if age >= 0, age < Self.maximumTrustedAge {
                let usesApplicationLocation = current.locationAuthorization
                    == .notDetermined
                let usesApplicationFamilyControls = current.familyControls
                    == .notDetermined
                return AuthorizationSnapshot(
                    familyControls: usesApplicationFamilyControls
                        ? record.snapshot.familyControls
                        : current.familyControls,
                    locationAuthorization: usesApplicationLocation
                        ? record.snapshot.locationAuthorization
                        : current.locationAuthorization,
                    locationAccuracy: usesApplicationLocation
                        ? record.snapshot.locationAccuracy
                        : current.locationAccuracy,
                    backgroundRefresh: record.snapshot.backgroundRefresh
                )
            }
        }
        return current
    }

    private static func systemSnapshot() -> AuthorizationSnapshot {
        let locationManager = CLLocationManager()
        return AuthorizationSnapshot(
            familyControls: familyControlsStatus(),
            locationAuthorization: locationAuthorizationStatus(
                locationManager.authorizationStatus
            ),
            locationAccuracy: locationAccuracyStatus(
                locationManager.accuracyAuthorization
            ),
            backgroundRefresh: .available
        )
    }

    private static func familyControlsStatus() -> FamilyControlsAuthorizationStatus {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved, .approvedWithDataAccess:
            .approved
        case .denied:
            .denied
        case .notDetermined:
            .notDetermined
        @unknown default:
            .notDetermined
        }
    }

    private static func locationAuthorizationStatus(
        _ status: CLAuthorizationStatus
    ) -> LocationAuthorizationStatus {
        switch status {
        case .authorizedAlways:
            .always
        case .authorizedWhenInUse:
            .whenInUse
        case .denied:
            .denied
        case .restricted:
            .restricted
        case .notDetermined:
            .notDetermined
        @unknown default:
            .notDetermined
        }
    }

    private static func locationAccuracyStatus(
        _ status: CLAccuracyAuthorization
    ) -> LocationAccuracyStatus {
        switch status {
        case .fullAccuracy:
            .full
        case .reducedAccuracy:
            .reduced
        @unknown default:
            .reduced
        }
    }
}

struct DeviceActivityIntervalStartHandler {
    typealias SnapshotLoader = () throws -> DeviceActivityIntervalStartSnapshot
    typealias AuthorizationSnapshotLoader = () -> AuthorizationSnapshot

    private let storeAccess: any ManagedSettingsStoreAccess
    private let defaults: UserDefaults
    private let loadSnapshot: SnapshotLoader
    private let authorizationSnapshot: AuthorizationSnapshotLoader
    private let now: () -> Date
    private let calendar: Calendar
    private let timeZone: TimeZone

    init(
        storeAccess: any ManagedSettingsStoreAccess,
        defaults: UserDefaults,
        loadSnapshot: @escaping SnapshotLoader,
        authorizationSnapshot: @escaping AuthorizationSnapshotLoader,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) {
        self.storeAccess = storeAccess
        self.defaults = defaults
        self.loadSnapshot = loadSnapshot
        self.authorizationSnapshot = authorizationSnapshot
        self.now = now
        self.calendar = calendar
        self.timeZone = timeZone
    }

    static func live(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) throws -> Self {
        guard
            let identifier = SharedIdentifiers.appGroupIdentifier(in: bundle)
        else {
            throw ManagedSettingsRestrictionAdapterError.missingAppGroupIdentifier
        }
        guard let defaults = UserDefaults(suiteName: identifier) else {
            throw ManagedSettingsRestrictionAdapterError.sharedDefaultsUnavailable
        }
        guard
            let containerURL = fileManager.containerURL(
                forSecurityApplicationGroupIdentifier: identifier
            )
        else {
            throw DependencyContainerError.appGroupContainerUnavailable
        }

        let snapshotReader = DeviceActivityIntervalStartSnapshotFileReader(
            containerURL: containerURL
        )
        let authorizationReader = DeviceActivityAuthorizationSnapshotReader(
            defaults: defaults
        )
        return Self(
            storeAccess: SystemManagedSettingsStoreAccess(),
            defaults: defaults,
            loadSnapshot: snapshotReader.load,
            authorizationSnapshot: authorizationReader.snapshot
        )
    }

    @discardableResult
    func handle(activityName: String) -> Bool {
        let observedAt = now()
        saveDiagnostic(
            IntervalStartDiagnosticRecord(
                stage: .callbackReceived,
                observedAt: observedAt,
                activityName: activityName,
                ruleCount: nil,
                locationConditionCount: nil,
                desiredRuleCount: nil,
                currentAppliedRuleCount: nil,
                startedRuleDecision: nil,
                startedLocationState: nil,
                startedLocationAgeSeconds: nil,
                authorization: nil,
                errorCode: nil
            )
        )
        guard
            let startedRuleID = SharedIdentifiers.ruleID(
                fromDeviceActivityName: activityName
            )
        else {
            saveDiagnostic(
                diagnostic(
                    stage: .invalidActivityName,
                    observedAt: observedAt,
                    activityName: activityName
                )
            )
            return false
        }

        do {
            let snapshot = try loadSnapshot()
            guard snapshot.rules.contains(where: { $0.id == startedRuleID }) else {
                saveDiagnostic(
                    diagnostic(
                        stage: .startedRuleMissing,
                        observedAt: observedAt,
                        activityName: activityName,
                        snapshot: snapshot
                    )
                )
                return false
            }

            let currentState = RestrictionApplicationStateDefaultsCodec.load(
                from: defaults
            )
            let authorization = authorizationSnapshot()
            let evaluation = RestrictionRuleSetEvaluator.evaluate(
                rules: snapshot.rules,
                locationConditions: snapshot.locationConditions,
                authorization: authorization,
                currentAppliedState: currentState,
                now: observedAt,
                calendar: calendar,
                timeZone: timeZone
            )
            let desiredState = AppliedRestrictionState(
                activeRuleRevisions: Set(
                    evaluation.desiredRules.map {
                        ActiveRuleRevision(ruleID: $0.id, revision: $0.revision)
                    }
                )
            )
            let desiredSelection = ManagedSettingsShieldSelection(
                rules: evaluation.desiredRules
            )
            let storeName = SharedIdentifiers.managedSettingsStoreName
            let currentSelection = storeAccess.shieldSelection(named: storeName)

            if currentSelection != desiredSelection {
                storeAccess.setShieldSelection(
                    desiredSelection,
                    named: storeName
                )
                guard
                    storeAccess.shieldSelection(named: storeName)
                        == desiredSelection
                else {
                    saveDiagnostic(
                        diagnostic(
                            stage: .storeVerificationFailed,
                            observedAt: observedAt,
                            activityName: activityName,
                            snapshot: snapshot,
                            evaluation: evaluation,
                            authorization: authorization,
                            currentState: currentState,
                            startedRuleID: startedRuleID
                        )
                    )
                    return false
                }
            }

            if currentState != desiredState {
                RestrictionApplicationStateDefaultsCodec.save(
                    desiredState,
                    to: defaults
                )
            }
            saveDiagnostic(
                diagnostic(
                    stage: .completed,
                    observedAt: observedAt,
                    activityName: activityName,
                    snapshot: snapshot,
                    evaluation: evaluation,
                    authorization: authorization,
                    currentState: currentState,
                    startedRuleID: startedRuleID
                )
            )
            return true
        } catch {
            saveDiagnostic(
                diagnostic(
                    stage: .snapshotReadFailed,
                    observedAt: observedAt,
                    activityName: activityName,
                    errorCode: DiagnosticErrorClassifier.classify(error).rawValue
                )
            )
            return false
        }
    }

    private func saveDiagnostic(_ record: IntervalStartDiagnosticRecord) {
        IntervalStartDiagnosticDefaultsCodec.save(record, to: defaults)
    }

    private func diagnostic(
        stage: IntervalStartDiagnosticStage,
        observedAt: Date,
        activityName: String,
        snapshot: DeviceActivityIntervalStartSnapshot? = nil,
        evaluation: RestrictionRuleSetEvaluation? = nil,
        authorization: AuthorizationSnapshot? = nil,
        currentState: AppliedRestrictionState? = nil,
        startedRuleID: UUID? = nil,
        errorCode: String? = nil
    ) -> IntervalStartDiagnosticRecord {
        let condition = startedRuleID.flatMap { ruleID in
            snapshot?.locationConditions.first { $0.ruleID == ruleID }
        }
        let decision = startedRuleID.flatMap { evaluation?.decisions[$0] }
        return IntervalStartDiagnosticRecord(
            stage: stage,
            observedAt: observedAt,
            activityName: activityName,
            ruleCount: snapshot?.rules.count,
            locationConditionCount: snapshot?.locationConditions.count,
            desiredRuleCount: evaluation?.desiredRules.count,
            currentAppliedRuleCount: currentState?.activeRuleRevisions.count,
            startedRuleDecision: decision.map { decisionName($0.reason) },
            startedLocationState: condition?.state,
            startedLocationAgeSeconds: condition.map {
                max(0, observedAt.timeIntervalSince($0.observedAt))
            },
            authorization: authorization,
            errorCode: errorCode
        )
    }

    private func decisionName(_ reason: EvaluationReason) -> String {
        switch reason {
        case .configurationMissing: "configurationMissing"
        case .ruleDisabled: "ruleDisabled"
        case .scheduleInactive: "scheduleInactive"
        case .missingPermissions: "missingPermissions"
        case .locationRevisionMismatch: "locationRevisionMismatch"
        case .locationOutside: "locationOutside"
        case .locationUnavailable: "locationUnavailable"
        case .conditionsSatisfied: "conditionsSatisfied"
        }
    }
}

enum IntervalStartDiagnosticDefaultsCodec {
    static func load(
        from defaults: UserDefaults
    ) -> IntervalStartDiagnosticRecord? {
        guard
            let data = defaults.data(
                forKey: SharedIdentifiers.intervalStartDiagnosticDefaultsKey
            )
        else {
            return nil
        }
        return try? JSONDecoder().decode(
            IntervalStartDiagnosticRecord.self,
            from: data
        )
    }

    static func save(
        _ record: IntervalStartDiagnosticRecord,
        to defaults: UserDefaults
    ) {
        guard let data = try? JSONEncoder().encode(record) else {
            return
        }
        defaults.set(
            data,
            forKey: SharedIdentifiers.intervalStartDiagnosticDefaultsKey
        )
    }
}

struct DeviceActivityIntervalEndHandler {
    private let storeAccess: any ManagedSettingsStoreAccess
    private let defaults: UserDefaults

    init(
        storeAccess: any ManagedSettingsStoreAccess,
        defaults: UserDefaults
    ) {
        self.storeAccess = storeAccess
        self.defaults = defaults
    }

    static func live(bundle: Bundle = .main) throws -> Self {
        guard
            let identifier = SharedIdentifiers.appGroupIdentifier(in: bundle)
        else {
            throw ManagedSettingsRestrictionAdapterError.missingAppGroupIdentifier
        }
        guard let defaults = UserDefaults(suiteName: identifier) else {
            throw ManagedSettingsRestrictionAdapterError.sharedDefaultsUnavailable
        }
        return Self(
            storeAccess: SystemManagedSettingsStoreAccess(),
            defaults: defaults
        )
    }

    @discardableResult
    func handle(activityName: String) -> Bool {
        guard
            let endedRuleID = SharedIdentifiers.ruleID(
                fromDeviceActivityName: activityName
            )
        else {
            return false
        }

        let currentState = RestrictionApplicationStateDefaultsCodec.load(
            from: defaults
        )
        guard currentState.activeRuleRevisions.contains(where: {
            $0.ruleID == endedRuleID
        }) else {
            return false
        }
        let remaining = currentState.activeRuleRevisions.filter {
            $0.ruleID != endedRuleID
        }

        // The shared store contains the union for every active rule. It is
        // safe to clear synchronously only when this callback ended the final
        // active rule; overlapping rules require the coordinator to rebuild
        // the union from their full selections.
        guard remaining.isEmpty else {
            return false
        }

        let storeName = SharedIdentifiers.managedSettingsStoreName
        storeAccess.setShieldSelection(.empty, named: storeName)
        guard storeAccess.shieldSelection(named: storeName) == .empty else {
            return false
        }
        RestrictionApplicationStateDefaultsCodec.save(
            AppliedRestrictionState(activeRuleRevisions: []),
            to: defaults
        )
        return true
    }
}

@MainActor
final class ManagedSettingsRestrictionAdapter: RestrictionApplying {
    private let storeAccess: any ManagedSettingsStoreAccess
    private let stateStore: any RestrictionApplicationStateStoring

    init(
        storeAccess: any ManagedSettingsStoreAccess,
        stateStore: any RestrictionApplicationStateStoring
    ) {
        self.storeAccess = storeAccess
        self.stateStore = stateStore
    }

    static func live(
        bundle: Bundle = .main
    ) throws -> ManagedSettingsRestrictionAdapter {
        guard
            let appGroupIdentifier = SharedIdentifiers.appGroupIdentifier(
                in: bundle
            )
        else {
            throw ManagedSettingsRestrictionAdapterError
                .missingAppGroupIdentifier
        }
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            throw ManagedSettingsRestrictionAdapterError
                .sharedDefaultsUnavailable
        }

        return ManagedSettingsRestrictionAdapter(
            storeAccess: SystemManagedSettingsStoreAccess(),
            stateStore: UserDefaultsRestrictionApplicationStateStore(
                defaults: defaults
            )
        )
    }

    func currentAppliedState() async -> AppliedRestrictionState {
        await stateStore.currentState()
    }

    func applyRestriction(for rules: [RestrictionRuleSnapshot]) async throws {
        let activeRuleRevisions = Set(
            rules.map { ActiveRuleRevision(ruleID: $0.id, revision: $0.revision) }
        )
        guard !activeRuleRevisions.isEmpty else {
            try await removeRestriction()
            return
        }

        let desiredSelection = ManagedSettingsShieldSelection(rules: rules)
        let currentState = await stateStore.currentState()
        let storeName = SharedIdentifiers.managedSettingsStoreName
        guard
            currentState.activeRuleRevisions != activeRuleRevisions
                || storeAccess.shieldSelection(named: storeName) != desiredSelection
        else {
            return
        }

        storeAccess.setShieldSelection(desiredSelection, named: storeName)
        guard storeAccess.shieldSelection(named: storeName) == desiredSelection else {
            throw ManagedSettingsRestrictionAdapterError.storeVerificationFailed
        }
        await stateStore.saveState(
            AppliedRestrictionState(
                activeRuleRevisions: activeRuleRevisions
            )
        )
    }

    func removeRestriction() async throws {
        let currentState = await stateStore.currentState()
        let storeName = SharedIdentifiers.managedSettingsStoreName
        guard
            currentState.isApplied
                || storeAccess.shieldSelection(named: storeName) != .empty
        else {
            return
        }

        storeAccess.setShieldSelection(.empty, named: storeName)
        guard storeAccess.shieldSelection(named: storeName) == .empty else {
            throw ManagedSettingsRestrictionAdapterError.storeVerificationFailed
        }
        await stateStore.saveState(
            AppliedRestrictionState(
                activeRuleRevisions: []
            )
        )
    }
}

@MainActor
extension DependencyContainer {
    func makeRestrictionAdapter(
        bundle: Bundle = .main
    ) throws -> ManagedSettingsRestrictionAdapter {
        try ManagedSettingsRestrictionAdapter.live(bundle: bundle)
    }
}
