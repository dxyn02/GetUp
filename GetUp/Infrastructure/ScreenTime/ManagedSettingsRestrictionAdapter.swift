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
            let ruleID = SharedIdentifiers.ruleID(
                fromDeviceActivityName: activityName
            )
        else {
            return false
        }

        let currentState = RestrictionApplicationStateDefaultsCodec.load(
            from: defaults
        )
        let remaining = currentState.activeRuleRevisions.filter {
            $0.ruleID != ruleID
        }

        // Versions before rule-specific stores wrote the union to one legacy
        // store. Clear that store only after every remaining rule already has
        // an independent shield; otherwise the async coordinator must migrate
        // the union with the full rule data before it can safely split it.
        let legacyStoreName = SharedIdentifiers.managedSettingsStoreName
        if storeAccess.shieldSelection(named: legacyStoreName) != .empty {
            let canSafelyClearLegacyStore = remaining.allSatisfy { revision in
                storeAccess.shieldSelection(
                    named: SharedIdentifiers.managedSettingsStoreName(
                        for: revision.ruleID
                    )
                ) != .empty
            }
            guard canSafelyClearLegacyStore else {
                return false
            }
            storeAccess.setShieldSelection(.empty, named: legacyStoreName)
            guard
                storeAccess.shieldSelection(named: legacyStoreName) == .empty
            else {
                return false
            }
        }

        let storeName = SharedIdentifiers.managedSettingsStoreName(for: ruleID)
        storeAccess.setShieldSelection(.empty, named: storeName)
        guard storeAccess.shieldSelection(named: storeName) == .empty else {
            return false
        }

        RestrictionApplicationStateDefaultsCodec.save(
            AppliedRestrictionState(activeRuleRevisions: remaining),
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

        let currentState = await stateStore.currentState()
        var performedWrite = false

        for rule in rules {
            let storeName = SharedIdentifiers.managedSettingsStoreName(for: rule.id)
            let desiredSelection = ManagedSettingsShieldSelection(rules: [rule])
            if storeAccess.shieldSelection(named: storeName) != desiredSelection {
                storeAccess.setShieldSelection(desiredSelection, named: storeName)
                guard storeAccess.shieldSelection(named: storeName) == desiredSelection else {
                    throw ManagedSettingsRestrictionAdapterError.storeVerificationFailed
                }
                performedWrite = true
            }
        }

        let desiredRuleIDs = Set(rules.map(\.id))
        let staleRuleIDs = Set(
            currentState.activeRuleRevisions.map(\.ruleID)
        ).subtracting(desiredRuleIDs)
        for ruleID in staleRuleIDs {
            let storeName = SharedIdentifiers.managedSettingsStoreName(for: ruleID)
            storeAccess.setShieldSelection(.empty, named: storeName)
            guard storeAccess.shieldSelection(named: storeName) == .empty else {
                throw ManagedSettingsRestrictionAdapterError.storeVerificationFailed
            }
            performedWrite = true
        }

        let legacyStoreName = SharedIdentifiers.managedSettingsStoreName
        if currentState.requiresReset
            || storeAccess.shieldSelection(named: legacyStoreName) != .empty
        {
            storeAccess.setShieldSelection(.empty, named: legacyStoreName)
            guard storeAccess.shieldSelection(named: legacyStoreName) == .empty else {
                throw ManagedSettingsRestrictionAdapterError.storeVerificationFailed
            }
            performedWrite = true
        }

        if performedWrite
            || currentState.activeRuleRevisions != activeRuleRevisions
            || currentState.requiresReset
        {
            await stateStore.saveState(
                AppliedRestrictionState(
                    activeRuleRevisions: activeRuleRevisions
                )
            )
        }
    }

    func removeRestriction() async throws {
        let currentState = await stateStore.currentState()
        var storeNames = Set(
            currentState.activeRuleRevisions.map {
                SharedIdentifiers.managedSettingsStoreName(for: $0.ruleID)
            }
        )
        storeNames.insert(SharedIdentifiers.managedSettingsStoreName)
        var performedWrite = false

        for storeName in storeNames {
            if currentState.requiresReset
                || storeAccess.shieldSelection(named: storeName) != .empty
            {
                storeAccess.setShieldSelection(.empty, named: storeName)
                guard storeAccess.shieldSelection(named: storeName) == .empty else {
                    throw ManagedSettingsRestrictionAdapterError.storeVerificationFailed
                }
                performedWrite = true
            }
        }

        guard currentState.isApplied || currentState.requiresReset || performedWrite else {
            return
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
