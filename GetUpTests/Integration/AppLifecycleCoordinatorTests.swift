import Foundation
import Testing
@testable import GetUp

@Suite("App lifecycle recovery coordinator")
struct AppLifecycleCoordinatorTests {
    @Test("Recovery rebuilds schedules, regions, locations, then restriction state")
    func restoresEveryEnabledRule() async throws {
        let enabled = TestFixtures.makeRule()
        let disabled = TestFixtures.makeRule(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000301")!,
            isEnabled: false
        )
        let schedule = RecoveryScheduleManager()
        let location = RecoveryLocationMonitor()
        let restriction = RecoveryRestrictionRecorder()
        let coordinator = AppLifecycleCoordinator(
            ruleRepository: RecoveryRuleRepository(rules: [enabled, disabled]),
            scheduleManager: schedule,
            locationMonitor: location,
            restoreRestriction: { try await restriction.restore() }
        )

        let result = try await coordinator.restore()

        #expect(await schedule.didRemoveAll)
        #expect(await schedule.replacedRuleIDs == [enabled.id])
        #expect(await location.didStopAll)
        #expect(await location.replacedRuleIDs == [enabled.id])
        #expect(await location.refreshedRuleIDs == [enabled.id])
        #expect(await restriction.restoreCount == 1)
        #expect(result.recoveredRuleIDs == [enabled.id])
        #expect(result.failures.isEmpty)
    }

    @Test("A platform registration failure does not skip restriction reconciliation")
    func bestEffortRecoveryStillReconcilesRestriction() async throws {
        let rule = TestFixtures.makeRule()
        let schedule = RecoveryScheduleManager(shouldFailReplacement: true)
        let location = RecoveryLocationMonitor(shouldFailReplacement: true)
        let restriction = RecoveryRestrictionRecorder()
        let coordinator = AppLifecycleCoordinator(
            ruleRepository: RecoveryRuleRepository(rules: [rule]),
            scheduleManager: schedule,
            locationMonitor: location,
            restoreRestriction: { try await restriction.restore() }
        )

        let result = try await coordinator.restore()

        #expect(await restriction.restoreCount == 1)
        #expect(result.failures == [.schedule(ruleID: rule.id), .location(ruleID: rule.id)])
    }

    @Test("An unreadable protected snapshot preserves registrations and restriction state")
    func protectedSnapshotFailurePerformsNoRecoveryWrites() async {
        let schedule = RecoveryScheduleManager()
        let location = RecoveryLocationMonitor()
        let restriction = RecoveryRestrictionRecorder()
        let coordinator = AppLifecycleCoordinator(
            ruleRepository: RecoveryRuleRepository(rules: [], shouldFailLoad: true),
            scheduleManager: schedule,
            locationMonitor: location,
            restoreRestriction: { try await restriction.restore() }
        )

        do {
            _ = try await coordinator.restore()
            Issue.record("보호된 snapshot read 실패가 전달되어야 합니다.")
        } catch {
            #expect(await schedule.didRemoveAll == false)
            #expect(await location.didStopAll == false)
            #expect(await restriction.restoreCount == 0)
        }
    }
}

private actor RecoveryRuleRepository: RuleRepository {
    private var collection: RestrictionRuleCollectionSnapshot?
    private let shouldFailLoad: Bool

    init(
        rules: [RestrictionRuleSnapshot],
        shouldFailLoad: Bool = false
    ) {
        collection = RestrictionRuleCollectionSnapshot(revision: 1, rules: rules)
        self.shouldFailLoad = shouldFailLoad
    }

    func loadRuleCollection() throws -> RestrictionRuleCollectionSnapshot? {
        if shouldFailLoad { throw RecoveryFailure.expected }
        return collection
    }
    func saveRuleCollection(_ collection: RestrictionRuleCollectionSnapshot) {
        self.collection = collection
    }
    func deleteRuleCollection() { collection = nil }
}

private actor RecoveryScheduleManager: ScheduleManaging {
    private(set) var didRemoveAll = false
    private(set) var replacedRuleIDs: [UUID] = []
    private let shouldFailReplacement: Bool

    init(shouldFailReplacement: Bool = false) {
        self.shouldFailReplacement = shouldFailReplacement
    }

    func replaceSchedules(for rule: RestrictionRuleSnapshot) throws {
        if shouldFailReplacement { throw RecoveryFailure.expected }
        replacedRuleIDs.append(rule.id)
    }

    func removeSchedules() { didRemoveAll = true }
}

private actor RecoveryLocationMonitor: LocationMonitoring {
    private(set) var didStopAll = false
    private(set) var replacedRuleIDs: [UUID] = []
    private(set) var refreshedRuleIDs: [UUID] = []
    private let shouldFailReplacement: Bool

    init(shouldFailReplacement: Bool = false) {
        self.shouldFailReplacement = shouldFailReplacement
    }

    func replaceMonitoring(for rule: RestrictionRuleSnapshot) throws {
        if shouldFailReplacement { throw RecoveryFailure.expected }
        replacedRuleIDs.append(rule.id)
    }

    func stopMonitoring() { didStopAll = true }

    func refreshLocationCondition(
        for rule: RestrictionRuleSnapshot,
        source: LocationConditionSource
    ) -> LocationConditionSnapshot {
        refreshedRuleIDs.append(rule.id)
        return TestFixtures.makeLocationCondition(
            ruleID: rule.id,
            ruleRevision: rule.revision,
            source: source
        )
    }
}

private actor RecoveryRestrictionRecorder {
    private(set) var restoreCount = 0

    func restore() throws { restoreCount += 1 }
}

private enum RecoveryFailure: Error {
    case expected
}
