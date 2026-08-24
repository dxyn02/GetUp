@preconcurrency import FamilyControls
import Foundation
@preconcurrency import ManagedSettings

enum ManagedSettingsRestrictionAdapterError: Error, Equatable, Sendable {
    case missingAppGroupIdentifier
    case sharedDefaultsUnavailable
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
        static let isApplied = "getup.restriction.is-applied"
        static let ruleRevision = "getup.restriction.rule-revision"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func currentState() -> AppliedRestrictionState {
        let isApplied = defaults.bool(forKey: Key.isApplied)
        let revision = defaults.object(forKey: Key.ruleRevision) as? Int
        return AppliedRestrictionState(
            isApplied: isApplied,
            ruleRevision: isApplied ? revision : nil
        )
    }

    func saveState(_ newState: AppliedRestrictionState) {
        defaults.set(newState.isApplied, forKey: Key.isApplied)

        if let revision = newState.ruleRevision {
            defaults.set(revision, forKey: Key.ruleRevision)
        } else {
            defaults.removeObject(forKey: Key.ruleRevision)
        }
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

    func applyRestriction(for rule: RestrictionRuleSnapshot) async throws {
        let currentState = await stateStore.currentState()
        guard
            !currentState.isApplied
                || currentState.ruleRevision != rule.revision
        else {
            return
        }

        storeAccess.setShieldedApplications(
            rule.activitySelection.applicationTokens,
            named: SharedIdentifiers.managedSettingsStoreName
        )
        await stateStore.saveState(
            AppliedRestrictionState(
                isApplied: true,
                ruleRevision: rule.revision
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
        await stateStore.saveState(
            AppliedRestrictionState(
                isApplied: false,
                ruleRevision: nil
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
