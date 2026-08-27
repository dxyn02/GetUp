@preconcurrency import FamilyControls
import Foundation
@preconcurrency import ManagedSettings
import Testing
@testable import GetUp

@MainActor
@Suite("Managed Settings restriction adapter")
struct ManagedSettingsRestrictionAdapterTests {
    @Test("The interval extension uses a recent app authorization snapshot")
    func intervalAuthorizationUsesRecentApplicationSnapshot() throws {
        let suiteName = "ManagedSettingsRestrictionAdapterTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let approved = TestFixtures.makeAuthorization()
        AuthorizationSnapshotDefaultsCodec.save(
            AuthorizationSnapshotRecord(
                snapshot: approved,
                observedAt: TestFixtures.now
            ),
            to: defaults
        )
        let reader = DeviceActivityAuthorizationSnapshotReader(
            defaults: defaults,
            currentSnapshot: {
                TestFixtures.makeAuthorization(
                    locationAuthorization: .notDetermined,
                    locationAccuracy: .reduced
                )
            },
            now: { TestFixtures.now }
        )

        #expect(reader.snapshot() == approved)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("The interval extension honors a live Family Controls revocation")
    func intervalAuthorizationHonorsLiveFamilyControlsRevocation() throws {
        let suiteName = "ManagedSettingsRestrictionAdapterTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        AuthorizationSnapshotDefaultsCodec.save(
            AuthorizationSnapshotRecord(
                snapshot: TestFixtures.makeAuthorization(),
                observedAt: TestFixtures.now
            ),
            to: defaults
        )
        let reader = DeviceActivityAuthorizationSnapshotReader(
            defaults: defaults,
            currentSnapshot: {
                TestFixtures.makeAuthorization(
                    familyControls: .denied,
                    locationAuthorization: .notDetermined,
                    locationAccuracy: .reduced
                )
            },
            now: { TestFixtures.now }
        )

        #expect(
            reader.snapshot()
                == TestFixtures.makeAuthorization(familyControls: .denied)
        )
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("The interval extension fills an undetermined Family Controls status")
    func intervalAuthorizationFillsUndeterminedFamilyControlsStatus() throws {
        let suiteName = "ManagedSettingsRestrictionAdapterTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let approved = TestFixtures.makeAuthorization()
        AuthorizationSnapshotDefaultsCodec.save(
            AuthorizationSnapshotRecord(
                snapshot: approved,
                observedAt: TestFixtures.now
            ),
            to: defaults
        )
        let reader = DeviceActivityAuthorizationSnapshotReader(
            defaults: defaults,
            currentSnapshot: {
                TestFixtures.makeAuthorization(familyControls: .notDetermined)
            },
            now: { TestFixtures.now }
        )

        #expect(reader.snapshot() == approved)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("The interval extension honors a live location revocation")
    func intervalAuthorizationHonorsLiveLocationRevocation() throws {
        let suiteName = "ManagedSettingsRestrictionAdapterTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        AuthorizationSnapshotDefaultsCodec.save(
            AuthorizationSnapshotRecord(
                snapshot: TestFixtures.makeAuthorization(),
                observedAt: TestFixtures.now
            ),
            to: defaults
        )
        let current = TestFixtures.makeAuthorization(
            locationAuthorization: .denied,
            locationAccuracy: .reduced
        )
        let reader = DeviceActivityAuthorizationSnapshotReader(
            defaults: defaults,
            currentSnapshot: { current },
            now: { TestFixtures.now }
        )

        #expect(reader.snapshot() == current)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("The interval extension rejects a stale app authorization snapshot")
    func intervalAuthorizationRejectsStaleApplicationSnapshot() throws {
        let suiteName = "ManagedSettingsRestrictionAdapterTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        AuthorizationSnapshotDefaultsCodec.save(
            AuthorizationSnapshotRecord(
                snapshot: TestFixtures.makeAuthorization(),
                observedAt: TestFixtures.now.addingTimeInterval(-24 * 60 * 60)
            ),
            to: defaults
        )
        let current = TestFixtures.makeAuthorization(
            familyControls: .denied,
            locationAuthorization: .notDetermined,
            locationAccuracy: .reduced
        )
        let reader = DeviceActivityAuthorizationSnapshotReader(
            defaults: defaults,
            currentSnapshot: { current },
            now: { TestFixtures.now }
        )

        #expect(reader.snapshot() == current)
        defaults.removePersistentDomain(forName: suiteName)
    }

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

    @Test("The interval start handler synchronously applies every satisfied rule")
    func intervalStartSynchronouslyAppliesSatisfiedRules() throws {
        let firstApplication = try applicationToken(seed: 18)
        let secondApplication = try applicationToken(seed: 19)
        let first = TestFixtures.makeRule(
            activitySelection: selection(applicationTokens: [firstApplication])
        )
        let second = TestFixtures.makeRule(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000218")!,
            revision: 2,
            activitySelection: selection(applicationTokens: [secondApplication])
        )
        let store = RecordingManagedSettingsStoreAccess()
        let suiteName = "ManagedSettingsRestrictionAdapterTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let handler = DeviceActivityIntervalStartHandler(
            storeAccess: store,
            defaults: defaults,
            loadSnapshot: {
                DeviceActivityIntervalStartSnapshot(
                    rules: [first, second],
                    locationConditions: [
                        TestFixtures.makeLocationCondition(
                            ruleID: first.id,
                            ruleRevision: first.revision
                        ),
                        TestFixtures.makeLocationCondition(
                            ruleID: second.id,
                            ruleRevision: second.revision
                        ),
                    ]
                )
            },
            authorizationSnapshot: { TestFixtures.makeAuthorization() },
            now: { TestFixtures.now },
            calendar: TestFixtures.calendar,
            timeZone: TestFixtures.timeZone
        )

        let didHandle = handler.handle(
            activityName: "\(SharedIdentifiers.deviceActivityNamePrefix)."
                + "\(first.id.uuidString.lowercased()).monday"
        )

        #expect(didHandle)
        #expect(store.writeCount == 1)
        #expect(
            store.shieldSelection(
                named: SharedIdentifiers.managedSettingsStoreName
            ).applications == [firstApplication, secondApplication]
        )
        #expect(
            RestrictionApplicationStateDefaultsCodec.load(from: defaults)
                == AppliedRestrictionState(activeRuleRevisions: [
                    ActiveRuleRevision(ruleID: first.id, revision: first.revision),
                    ActiveRuleRevision(ruleID: second.id, revision: second.revision),
                ])
        )
        let diagnostic = try #require(
            IntervalStartDiagnosticDefaultsCodec.load(from: defaults)
        )
        #expect(diagnostic.stage == .completed)
        #expect(diagnostic.ruleCount == 2)
        #expect(diagnostic.locationConditionCount == 2)
        #expect(diagnostic.desiredRuleCount == 2)
        #expect(diagnostic.startedRuleDecision == "conditionsSatisfied")
        #expect(diagnostic.authorization == TestFixtures.makeAuthorization())
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("The interval start handler does not apply an outside rule")
    func intervalStartDoesNotApplyOutsideRule() throws {
        let rule = TestFixtures.makeRule(
            activitySelection: selection(
                applicationTokens: [try applicationToken(seed: 20)]
            )
        )
        let store = RecordingManagedSettingsStoreAccess()
        let suiteName = "ManagedSettingsRestrictionAdapterTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let handler = DeviceActivityIntervalStartHandler(
            storeAccess: store,
            defaults: defaults,
            loadSnapshot: {
                DeviceActivityIntervalStartSnapshot(
                    rules: [rule],
                    locationConditions: [
                        TestFixtures.makeLocationCondition(
                            ruleID: rule.id,
                            state: .outside
                        ),
                    ]
                )
            },
            authorizationSnapshot: { TestFixtures.makeAuthorization() },
            now: { TestFixtures.now },
            calendar: TestFixtures.calendar,
            timeZone: TestFixtures.timeZone
        )

        let didHandle = handler.handle(
            activityName: "\(SharedIdentifiers.deviceActivityNamePrefix)."
                + "\(rule.id.uuidString.lowercased()).monday"
        )

        #expect(didHandle)
        #expect(store.writeCount == 0)
        #expect(store.shieldSelection(named: SharedIdentifiers.managedSettingsStoreName) == .empty)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("The interval start handler does not apply a rule without required permissions")
    func intervalStartDoesNotApplyWithoutRequiredPermissions() throws {
        let rule = TestFixtures.makeRule(
            activitySelection: selection(
                applicationTokens: [try applicationToken(seed: 22)]
            )
        )
        let store = RecordingManagedSettingsStoreAccess()
        let suiteName = "ManagedSettingsRestrictionAdapterTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let handler = DeviceActivityIntervalStartHandler(
            storeAccess: store,
            defaults: defaults,
            loadSnapshot: {
                DeviceActivityIntervalStartSnapshot(
                    rules: [rule],
                    locationConditions: [
                        TestFixtures.makeLocationCondition(ruleID: rule.id),
                    ]
                )
            },
            authorizationSnapshot: {
                TestFixtures.makeAuthorization(familyControls: .denied)
            },
            now: { TestFixtures.now },
            calendar: TestFixtures.calendar,
            timeZone: TestFixtures.timeZone
        )

        let didHandle = handler.handle(
            activityName: "\(SharedIdentifiers.deviceActivityNamePrefix)."
                + "\(rule.id.uuidString.lowercased()).monday"
        )

        #expect(didHandle)
        #expect(store.writeCount == 0)
        #expect(
            store.shieldSelection(
                named: SharedIdentifiers.managedSettingsStoreName
            ) == .empty
        )
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("The interval start handler preserves state when snapshots cannot be read")
    func intervalStartSnapshotFailurePreservesState() throws {
        let rule = TestFixtures.makeRule(
            activitySelection: selection(
                applicationTokens: [try applicationToken(seed: 21)]
            )
        )
        let storeName = SharedIdentifiers.managedSettingsStoreName
        let shield = ManagedSettingsShieldSelection(rules: [rule])
        let store = RecordingManagedSettingsStoreAccess(stores: [storeName: shield])
        let suiteName = "ManagedSettingsRestrictionAdapterTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let initialState = AppliedRestrictionState(activeRuleRevisions: [
            ActiveRuleRevision(ruleID: rule.id, revision: rule.revision),
        ])
        RestrictionApplicationStateDefaultsCodec.save(initialState, to: defaults)
        let handler = DeviceActivityIntervalStartHandler(
            storeAccess: store,
            defaults: defaults,
            loadSnapshot: {
                throw SharedSnapshotRepositoryError.readFailed(
                    fileName: SharedIdentifiers.restrictionRulesFileName
                )
            },
            authorizationSnapshot: { TestFixtures.makeAuthorization() },
            now: { TestFixtures.now },
            calendar: TestFixtures.calendar,
            timeZone: TestFixtures.timeZone
        )

        let didHandle = handler.handle(
            activityName: "\(SharedIdentifiers.deviceActivityNamePrefix)."
                + "\(rule.id.uuidString.lowercased()).monday"
        )

        #expect(!didHandle)
        #expect(store.writeCount == 0)
        #expect(store.shieldSelection(named: storeName) == shield)
        #expect(RestrictionApplicationStateDefaultsCodec.load(from: defaults) == initialState)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("The interval start handler does not persist state when the store rejects its write")
    func intervalStartStoreFailureDoesNotPersistState() throws {
        let rule = TestFixtures.makeRule(
            activitySelection: selection(
                applicationTokens: [try applicationToken(seed: 23)]
            )
        )
        let storeName = SharedIdentifiers.managedSettingsStoreName
        let store = RecordingManagedSettingsStoreAccess(ignoresWrites: true)
        let suiteName = "ManagedSettingsRestrictionAdapterTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let handler = DeviceActivityIntervalStartHandler(
            storeAccess: store,
            defaults: defaults,
            loadSnapshot: {
                DeviceActivityIntervalStartSnapshot(
                    rules: [rule],
                    locationConditions: [
                        TestFixtures.makeLocationCondition(ruleID: rule.id),
                    ]
                )
            },
            authorizationSnapshot: { TestFixtures.makeAuthorization() },
            now: { TestFixtures.now },
            calendar: TestFixtures.calendar,
            timeZone: TestFixtures.timeZone
        )

        let didHandle = handler.handle(
            activityName: "\(SharedIdentifiers.deviceActivityNamePrefix)."
                + "\(rule.id.uuidString.lowercased()).monday"
        )

        #expect(!didHandle)
        #expect(store.writeCount == 1)
        #expect(store.shieldSelection(named: storeName) == .empty)
        #expect(
            RestrictionApplicationStateDefaultsCodec.load(from: defaults)
                == AppliedRestrictionState(activeRuleRevisions: [])
        )
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("The interval end handler synchronously clears the final active rule")
    func intervalEndSynchronouslyClearsFinalRule() throws {
        let application = try applicationToken(seed: 21)
        let rule = TestFixtures.makeRule(
            revision: 3,
            activitySelection: selection(applicationTokens: [application])
        )
        let storeName = SharedIdentifiers.managedSettingsStoreName
        let store = RecordingManagedSettingsStoreAccess(stores: [
            storeName: ManagedSettingsShieldSelection(rules: [rule]),
        ])
        let suiteName = "ManagedSettingsRestrictionAdapterTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        RestrictionApplicationStateDefaultsCodec.save(
            AppliedRestrictionState(activeRuleRevisions: [
                ActiveRuleRevision(ruleID: rule.id, revision: rule.revision),
            ]),
            to: defaults
        )
        let handler = DeviceActivityIntervalEndHandler(
            storeAccess: store,
            defaults: defaults
        )

        let didHandle = handler.handle(
            activityName: "\(SharedIdentifiers.deviceActivityNamePrefix)."
                + "\(rule.id.uuidString.lowercased()).monday"
        )

        #expect(didHandle)
        #expect(store.shieldSelection(named: storeName) == .empty)
        #expect(
            RestrictionApplicationStateDefaultsCodec.load(from: defaults)
                == AppliedRestrictionState(activeRuleRevisions: [])
        )
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("The interval end handler defers when another rule remains active")
    func intervalEndDefersOverlappingRuleRecalculation() throws {
        let first = TestFixtures.makeRule(
            activitySelection: selection(
                applicationTokens: [try applicationToken(seed: 22)]
            )
        )
        let second = TestFixtures.makeRule(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000202")!,
            revision: 2,
            activitySelection: selection(
                applicationTokens: [try applicationToken(seed: 23)]
            )
        )
        let storeName = SharedIdentifiers.managedSettingsStoreName
        let union = ManagedSettingsShieldSelection(rules: [first, second])
        let store = RecordingManagedSettingsStoreAccess(stores: [
            storeName: union,
        ])
        let suiteName = "ManagedSettingsRestrictionAdapterTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let initialState = AppliedRestrictionState(activeRuleRevisions: [
            ActiveRuleRevision(ruleID: first.id, revision: first.revision),
            ActiveRuleRevision(ruleID: second.id, revision: second.revision),
        ])
        RestrictionApplicationStateDefaultsCodec.save(initialState, to: defaults)
        let handler = DeviceActivityIntervalEndHandler(
            storeAccess: store,
            defaults: defaults
        )

        let didHandle = handler.handle(
            activityName: "\(SharedIdentifiers.deviceActivityNamePrefix)."
                + "\(first.id.uuidString.lowercased()).monday"
        )

        #expect(!didHandle)
        #expect(store.shieldSelection(named: storeName) == union)
        #expect(
            RestrictionApplicationStateDefaultsCodec.load(from: defaults)
                == initialState
        )
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("The interval end handler ignores a stale callback")
    func intervalEndIgnoresStaleCallback() throws {
        let active = TestFixtures.makeRule(
            activitySelection: selection(
                applicationTokens: [try applicationToken(seed: 24)]
            )
        )
        let staleRuleID = UUID(
            uuidString: "00000000-0000-4000-8000-000000000299"
        )!
        let storeName = SharedIdentifiers.managedSettingsStoreName
        let shield = ManagedSettingsShieldSelection(rules: [active])
        let store = RecordingManagedSettingsStoreAccess(stores: [
            storeName: shield,
        ])
        let suiteName = "ManagedSettingsRestrictionAdapterTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let initialState = AppliedRestrictionState(activeRuleRevisions: [
            ActiveRuleRevision(ruleID: active.id, revision: active.revision),
        ])
        RestrictionApplicationStateDefaultsCodec.save(initialState, to: defaults)
        let handler = DeviceActivityIntervalEndHandler(
            storeAccess: store,
            defaults: defaults
        )

        let didHandle = handler.handle(
            activityName: "\(SharedIdentifiers.deviceActivityNamePrefix)."
                + "\(staleRuleID.uuidString.lowercased()).monday"
        )

        #expect(!didHandle)
        #expect(store.shieldSelection(named: storeName) == shield)
        #expect(
            RestrictionApplicationStateDefaultsCodec.load(from: defaults)
                == initialState
        )
        defaults.removePersistentDomain(forName: suiteName)
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

    @Test("An unchanged revision repairs a missing application shield")
    func unchangedRevisionRepairsApplicationShield() async throws {
        let application = try applicationToken(seed: 25)
        let rule = TestFixtures.makeRule(
            revision: 7,
            activitySelection: selection(applicationTokens: [application])
        )
        let store = RecordingManagedSettingsStoreAccess()
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

        try await adapter.applyRestriction(for: [rule])

        #expect(store.writeCount == 1)
        #expect(
            store.shieldSelection(
                named: SharedIdentifiers.managedSettingsStoreName
            ).applications == [application]
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
