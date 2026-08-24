@preconcurrency import FamilyControls
import Foundation
@preconcurrency import ManagedSettings
import Testing
@testable import GetUp

@MainActor
@Suite("Managed Settings restriction adapter")
struct ManagedSettingsRestrictionAdapterTests {
    @Test("Applying a rule shields exactly its selected applications")
    func appliesOnlySelectedApplicationTokens() async throws {
        let selected = try Set([
            applicationToken(seed: 1),
            applicationToken(seed: 2),
        ])
        let unselected = try applicationToken(seed: 3)
        let store = RecordingManagedSettingsStoreAccess()
        let stateStore = RecordingRestrictionApplicationStateStore()
        let adapter = ManagedSettingsRestrictionAdapter(
            storeAccess: store,
            stateStore: stateStore
        )
        let rule = TestFixtures.makeRule(
            revision: 4,
            activitySelection: selection(applicationTokens: selected)
        )

        try await adapter.applyRestriction(for: [rule])

        let shielded = store.shieldedApplications(
            named: SharedIdentifiers.managedSettingsStoreName
        )
        #expect(shielded == selected)
        #expect(shielded?.contains(unselected) == false)
        #expect(store.writeCount == 1)
        #expect(
            await stateStore.currentState()
                == AppliedRestrictionState(
                    activeRuleRevisions: [
                        ActiveRuleRevision(ruleID: rule.id, revision: 4),
                    ]
                )
        )
    }

    @Test("Applying an already-applied revision performs no writes")
    func identicalRevisionHasNoEffect() async throws {
        let selected = try Set([applicationToken(seed: 4)])
        let rule = TestFixtures.makeRule(
            revision: 8,
            activitySelection: selection(applicationTokens: selected)
        )
        let store = RecordingManagedSettingsStoreAccess(
            stores: [SharedIdentifiers.managedSettingsStoreName: selected]
        )
        let stateStore = RecordingRestrictionApplicationStateStore(
            initialState: AppliedRestrictionState(
                activeRuleRevisions: [
                    ActiveRuleRevision(ruleID: rule.id, revision: 8),
                ]
            )
        )
        let adapter = ManagedSettingsRestrictionAdapter(
            storeAccess: store,
            stateStore: stateStore
        )

        try await adapter.applyRestriction(for: [rule])

        #expect(store.writeCount == 0)
        #expect(await stateStore.writeCount == 0)
        #expect(
            store.shieldedApplications(
                named: SharedIdentifiers.managedSettingsStoreName
            ) == selected
        )
    }

    @Test("Applying GetUp restrictions preserves every other named store")
    func preservesOtherManagedSettingsStores() async throws {
        let selected = try Set([applicationToken(seed: 5)])
        let otherSelection = try Set([applicationToken(seed: 6)])
        let otherStoreName = "another-provider.restriction"
        let store = RecordingManagedSettingsStoreAccess(
            stores: [otherStoreName: otherSelection]
        )
        let stateStore = RecordingRestrictionApplicationStateStore()
        let adapter = ManagedSettingsRestrictionAdapter(
            storeAccess: store,
            stateStore: stateStore
        )
        let rule = TestFixtures.makeRule(
            revision: 9,
            activitySelection: selection(applicationTokens: selected)
        )

        try await adapter.applyRestriction(for: [rule])

        #expect(
            store.shieldedApplications(named: otherStoreName)
                == otherSelection
        )
        #expect(
            store.writtenStoreNames
                == [SharedIdentifiers.managedSettingsStoreName]
        )
    }

    @Test("Multiple active rules apply the de-duplicated application union")
    func appliesUnionAcrossActiveRules() async throws {
        let shared = try applicationToken(seed: 7)
        let firstOnly = try applicationToken(seed: 8)
        let secondOnly = try applicationToken(seed: 9)
        let first = TestFixtures.makeRule(
            activitySelection: selection(applicationTokens: [shared, firstOnly])
        )
        let second = TestFixtures.makeRule(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000201")!,
            activitySelection: selection(applicationTokens: [shared, secondOnly])
        )
        let store = RecordingManagedSettingsStoreAccess()
        let adapter = ManagedSettingsRestrictionAdapter(
            storeAccess: store,
            stateStore: RecordingRestrictionApplicationStateStore()
        )

        try await adapter.applyRestriction(for: [first, second])

        #expect(
            store.shieldedApplications(
                named: SharedIdentifiers.managedSettingsStoreName
            ) == [shared, firstOnly, secondOnly]
        )
    }

    @Test("A legacy applied flag forces the old named store to be cleared")
    func legacyAppliedStateRequiresReset() async throws {
        let stateStore = RecordingRestrictionApplicationStateStore(
            initialState: AppliedRestrictionState(
                activeRuleRevisions: [],
                requiresReset: true
            )
        )
        let store = RecordingManagedSettingsStoreAccess()
        let adapter = ManagedSettingsRestrictionAdapter(
            storeAccess: store,
            stateStore: stateStore
        )

        #expect(await adapter.currentAppliedState().requiresReset)

        try await adapter.removeRestriction()

        #expect(store.writeCount == 1)
        #expect(await adapter.currentAppliedState() == AppliedRestrictionState(
            activeRuleRevisions: []
        ))
    }

    private func selection(
        applicationTokens: Set<ApplicationToken>
    ) -> FamilyActivitySelection {
        var selection = FamilyActivitySelection()
        selection.applicationTokens = applicationTokens
        return selection
    }

    private func applicationToken(seed: UInt8) throws -> ApplicationToken {
        let encodedData = try JSONEncoder().encode(["data": Data([seed])])
        return try JSONDecoder().decode(
            ApplicationToken.self,
            from: encodedData
        )
    }
}

@MainActor
private final class RecordingManagedSettingsStoreAccess:
    ManagedSettingsStoreAccess
{
    private var stores: [String: Set<ApplicationToken>]

    private(set) var writeCount = 0
    private(set) var writtenStoreNames: [String] = []

    init(stores: [String: Set<ApplicationToken>] = [:]) {
        self.stores = stores
    }

    func shieldedApplications(named storeName: String)
        -> Set<ApplicationToken>?
    {
        stores[storeName]
    }

    func setShieldedApplications(
        _ applications: Set<ApplicationToken>?,
        named storeName: String
    ) {
        writeCount += 1
        writtenStoreNames.append(storeName)
        stores[storeName] = applications
    }
}

private actor RecordingRestrictionApplicationStateStore:
    RestrictionApplicationStateStoring
{
    private var state: AppliedRestrictionState
    private(set) var writeCount = 0

    init(
        initialState: AppliedRestrictionState = AppliedRestrictionState(
            activeRuleRevisions: []
        )
    ) {
        state = initialState
    }

    func currentState() -> AppliedRestrictionState {
        state
    }

    func saveState(_ newState: AppliedRestrictionState) {
        writeCount += 1
        state = newState
    }
}
