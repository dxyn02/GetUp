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

        let shielded = store.shieldSelection(
            named: SharedIdentifiers.managedSettingsStoreName
        ).applications
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
            stores: [
                SharedIdentifiers.managedSettingsStoreName:
                    ManagedSettingsShieldSelection(
                        applications: selected,
                        applicationCategories: nil,
                        webDomains: nil
                    ),
            ]
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
            store.shieldSelection(
                named: SharedIdentifiers.managedSettingsStoreName
            ).applications == selected
        )
    }

    @Test("Applying GetUp restrictions preserves every other named store")
    func preservesOtherManagedSettingsStores() async throws {
        let selected = try Set([applicationToken(seed: 5)])
        let otherSelection = try Set([applicationToken(seed: 6)])
        let otherStoreName = "another-provider.restriction"
        let store = RecordingManagedSettingsStoreAccess(
            stores: [
                otherStoreName: ManagedSettingsShieldSelection(
                    applications: otherSelection,
                    applicationCategories: nil,
                    webDomains: nil
                ),
            ]
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
            store.shieldSelection(named: otherStoreName).applications
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
            store.shieldSelection(
                named: SharedIdentifiers.managedSettingsStoreName
            ).applications == [shared, firstOnly, secondOnly]
        )
    }

    @Test("Selected categories and web domains are applied as shield targets")
    func appliesCategoriesAndWebDomains() async throws {
        let category = try TestFixtures.activityCategoryToken(seed: 12)
        let webDomain = try TestFixtures.webDomainToken(seed: 13)
        let rule = TestFixtures.makeRule(
            revision: 3,
            activitySelection: selection(
                categoryTokens: [category],
                webDomainTokens: [webDomain]
            )
        )
        let store = RecordingManagedSettingsStoreAccess()
        let adapter = ManagedSettingsRestrictionAdapter(
            storeAccess: store,
            stateStore: RecordingRestrictionApplicationStateStore()
        )

        try await adapter.applyRestriction(for: [rule])

        let shield = store.shieldSelection(
            named: SharedIdentifiers.managedSettingsStoreName
        )
        #expect(shield.applications == nil)
        #expect(shield.applicationCategories == .specific([category]))
        #expect(shield.webDomains == [webDomain])
    }

    @Test("An unchanged revision repairs a missing category shield")
    func unchangedRevisionRepairsCategoryShield() async throws {
        let category = try TestFixtures.activityCategoryToken(seed: 14)
        let rule = TestFixtures.makeRule(
            revision: 6,
            activitySelection: selection(categoryTokens: [category])
        )
        let store = RecordingManagedSettingsStoreAccess()
        let stateStore = RecordingRestrictionApplicationStateStore(
            initialState: AppliedRestrictionState(
                activeRuleRevisions: [
                    ActiveRuleRevision(ruleID: rule.id, revision: 6),
                ]
            )
        )
        let adapter = ManagedSettingsRestrictionAdapter(
            storeAccess: store,
            stateStore: stateStore
        )

        try await adapter.applyRestriction(for: [rule])

        #expect(store.writeCount == 1)
        #expect(
            store.shieldSelection(
                named: SharedIdentifiers.managedSettingsStoreName
            ).applicationCategories == .specific([category])
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

    @Test("Removing a restriction clears apps, categories, and web domains")
    func removingClearsEveryShieldTarget() async throws {
        let application = try applicationToken(seed: 15)
        let category = try TestFixtures.activityCategoryToken(seed: 16)
        let webDomain = try TestFixtures.webDomainToken(seed: 17)
        let rule = TestFixtures.makeRule(revision: 2)
        let store = RecordingManagedSettingsStoreAccess(
            stores: [
                SharedIdentifiers.managedSettingsStoreName:
                    ManagedSettingsShieldSelection(
                        applications: [application],
                        applicationCategories: .specific([category]),
                        webDomains: [webDomain]
                    ),
            ]
        )
        let stateStore = RecordingRestrictionApplicationStateStore(
            initialState: AppliedRestrictionState(
                activeRuleRevisions: [
                    ActiveRuleRevision(ruleID: rule.id, revision: 2),
                ]
            )
        )
        let adapter = ManagedSettingsRestrictionAdapter(
            storeAccess: store,
            stateStore: stateStore
        )

        try await adapter.removeRestriction()

        #expect(
            store.shieldSelection(
                named: SharedIdentifiers.managedSettingsStoreName
            ) == .empty
        )
        #expect(await stateStore.currentState() == AppliedRestrictionState(
            activeRuleRevisions: []
        ))
    }

    @Test("Applying reports failure when the named store does not reflect the write")
    func applyingRequiresStoreReadbackConfirmation() async throws {
        let selected = try Set([applicationToken(seed: 10)])
        let rule = TestFixtures.makeRule(
            activitySelection: selection(applicationTokens: selected)
        )
        let store = RecordingManagedSettingsStoreAccess(ignoresWrites: true)
        let stateStore = RecordingRestrictionApplicationStateStore()
        let adapter = ManagedSettingsRestrictionAdapter(
            storeAccess: store,
            stateStore: stateStore
        )

        await #expect(
            throws: ManagedSettingsRestrictionAdapterError.storeVerificationFailed
        ) {
            try await adapter.applyRestriction(for: [rule])
        }

        #expect(await stateStore.writeCount == 0)
    }

    @Test("Removing reports failure when the named store remains shielded")
    func removingRequiresStoreReadbackConfirmation() async throws {
        let selected = try Set([applicationToken(seed: 11)])
        let rule = TestFixtures.makeRule(
            activitySelection: selection(applicationTokens: selected)
        )
        let store = RecordingManagedSettingsStoreAccess(
            stores: [
                SharedIdentifiers.managedSettingsStoreName:
                    ManagedSettingsShieldSelection(
                        applications: selected,
                        applicationCategories: nil,
                        webDomains: nil
                    ),
            ],
            ignoresWrites: true
        )
        let stateStore = RecordingRestrictionApplicationStateStore(
            initialState: AppliedRestrictionState(
                activeRuleRevisions: [
                    ActiveRuleRevision(ruleID: rule.id, revision: rule.revision),
                ]
            )
        )
        let adapter = ManagedSettingsRestrictionAdapter(
            storeAccess: store,
            stateStore: stateStore
        )

        await #expect(
            throws: ManagedSettingsRestrictionAdapterError.storeVerificationFailed
        ) {
            try await adapter.removeRestriction()
        }

        #expect(await stateStore.writeCount == 0)
    }

    private func selection(
        applicationTokens: Set<ApplicationToken> = [],
        categoryTokens: Set<ActivityCategoryToken> = [],
        webDomainTokens: Set<WebDomainToken> = []
    ) -> FamilyActivitySelection {
        var selection = FamilyActivitySelection()
        selection.applicationTokens = applicationTokens
        selection.categoryTokens = categoryTokens
        selection.webDomainTokens = webDomainTokens
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
    private var stores: [String: ManagedSettingsShieldSelection]
    private let ignoresWrites: Bool

    private(set) var writeCount = 0
    private(set) var writtenStoreNames: [String] = []

    init(
        stores: [String: ManagedSettingsShieldSelection] = [:],
        ignoresWrites: Bool = false
    ) {
        self.stores = stores
        self.ignoresWrites = ignoresWrites
    }

    func shieldSelection(named storeName: String)
        -> ManagedSettingsShieldSelection
    {
        stores[storeName] ?? .empty
    }

    func setShieldSelection(
        _ selection: ManagedSettingsShieldSelection,
        named storeName: String
    ) {
        writeCount += 1
        writtenStoreNames.append(storeName)
        if !ignoresWrites {
            stores[storeName] = selection
        }
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
