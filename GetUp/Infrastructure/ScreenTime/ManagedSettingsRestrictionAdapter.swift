@preconcurrency import FamilyControls
import Foundation
@preconcurrency import ManagedSettings

enum ManagedSettingsRestrictionAdapterError: Error, Equatable, Sendable {
    case missingAppGroupIdentifier
    case sharedDefaultsUnavailable
    case storeVerificationFailed
}

@MainActor
protocol ManagedSettingsStoreAccess: Sendable {
    func shieldedApplications(
        named storeName: String
    ) -> Set<ApplicationToken>?
    func setShieldedApplications(
        _ applications: Set<ApplicationToken>?,
        named storeName: String
    )
}

protocol RestrictionApplicationStateStoring: Sendable {
    func currentState() async -> AppliedRestrictionState
    func saveState(_ newState: AppliedRestrictionState) async
}

@MainActor
final class SystemManagedSettingsStoreAccess: ManagedSettingsStoreAccess {
    private var stores: [String: ManagedSettingsStore] = [:]

    func shieldedApplications(
        named storeName: String
    ) -> Set<ApplicationToken>? {
        store(named: storeName).shield.applications
    }

    func setShieldedApplications(
        _ applications: Set<ApplicationToken>?,
        named storeName: String
    ) {
        store(named: storeName).shield.applications = applications
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
    private enum Key {
        static let activeRuleRevisions = SharedIdentifiers.activeRuleRevisionsDefaultsKey
        static let legacyIsApplied = SharedIdentifiers.legacyRestrictionIsAppliedDefaultsKey
        static let legacyRuleRevision = SharedIdentifiers
            .legacyRestrictionRuleRevisionDefaultsKey
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func currentState() -> AppliedRestrictionState {
        guard
            let data = defaults.data(forKey: Key.activeRuleRevisions),
            let revisions = try? JSONDecoder().decode(
                Set<ActiveRuleRevision>.self,
                from: data
            )
        else {
            return AppliedRestrictionState(
                activeRuleRevisions: [],
                requiresReset: defaults.bool(forKey: Key.legacyIsApplied)
            )
        }
        return AppliedRestrictionState(activeRuleRevisions: revisions)
    }

    func saveState(_ newState: AppliedRestrictionState) {
        if let data = try? JSONEncoder().encode(newState.activeRuleRevisions) {
            defaults.set(data, forKey: Key.activeRuleRevisions)
        } else {
            defaults.removeObject(forKey: Key.activeRuleRevisions)
        }
        defaults.removeObject(forKey: Key.legacyIsApplied)
        defaults.removeObject(forKey: Key.legacyRuleRevision)
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
        guard currentState.activeRuleRevisions != activeRuleRevisions else {
            return
        }

        let applications = rules.reduce(into: Set<ApplicationToken>()) {
            $0.formUnion($1.activitySelection.applicationTokens)
        }
        storeAccess.setShieldedApplications(
            applications,
            named: SharedIdentifiers.managedSettingsStoreName
        )
        guard storeAccess.shieldedApplications(
            named: SharedIdentifiers.managedSettingsStoreName
        ) == applications else {
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
        guard currentState.isApplied else {
            return
        }

        storeAccess.setShieldedApplications(
            nil,
            named: SharedIdentifiers.managedSettingsStoreName
        )
        guard storeAccess.shieldedApplications(
            named: SharedIdentifiers.managedSettingsStoreName
        ) == nil else {
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
