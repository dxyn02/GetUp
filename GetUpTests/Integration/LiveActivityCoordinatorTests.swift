import Foundation
import Testing
@testable import GetUp

@Suite("Live Activity coordinator")
struct LiveActivityCoordinatorTests {
    @Test("Background reconciliation never starts or queries ActivityKit")
    func backgroundDoesNotStart() async throws {
        let manager = LiveActivityManagerFake()
        let coordinator = makeCoordinator(manager: manager)
        let result = await coordinator.reconcile(
            context: .background,
            desiredActivity: try snapshot()
        )

        #expect(result.actions.isEmpty)
        #expect(result.failureCodes.isEmpty)
        #expect(await manager.authorizationRequestCount == 0)
        #expect(await manager.activeActivitiesRequestCount == 0)
        #expect(await manager.operations.isEmpty)
    }

    @Test("Foreground reconciliation requests the representative activity")
    func foregroundStartsActivity() async throws {
        let manager = LiveActivityManagerFake()
        let coordinator = makeCoordinator(manager: manager)
        let desired = try snapshot()
        let result = await coordinator.reconcile(
            context: .foreground,
            desiredActivity: desired
        )

        #expect(result.actions == [.request])
        #expect(result.failureCodes.isEmpty)
        #expect(await manager.operations == [.request])
        #expect(await manager.activities == [desired])
    }

    @Test("An identical foreground reconciliation is idempotent")
    func duplicateAdjustmentIsIgnored() async throws {
        let desired = try snapshot()
        let manager = LiveActivityManagerFake(activities: [desired])
        let coordinator = makeCoordinator(manager: manager)
        let result = await coordinator.reconcile(
            context: .foreground,
            desiredActivity: desired
        )

        #expect(result.actions.isEmpty)
        #expect(result.failureCodes.isEmpty)
        #expect(await manager.operations.isEmpty)
    }

    @Test("Duplicate activities are reduced to one representative")
    func duplicateActivitiesAreEnded() async throws {
        let desired = try snapshot(activityID: Self.activityID)
        let duplicate = try snapshot(activityID: Self.duplicateActivityID)
        let manager = LiveActivityManagerFake(activities: [duplicate, desired])
        let coordinator = makeCoordinator(manager: manager)
        let result = await coordinator.reconcile(
            context: .foreground,
            desiredActivity: desired
        )

        #expect(result.actions == [.end(Self.duplicateActivityID)])
        #expect(await manager.activities == [desired])
    }

    @Test("A changed representative updates the existing activity")
    func representativeChangeUpdatesExistingActivity() async throws {
        let current = try snapshot(occurrenceID: "occurrence-1")
        let desired = try snapshot(occurrenceID: "occurrence-2")
        let manager = LiveActivityManagerFake(activities: [current])
        let coordinator = makeCoordinator(manager: manager)
        let result = await coordinator.reconcile(
            context: .foreground,
            desiredActivity: desired
        )

        #expect(result.actions == [.update(Self.activityID)])
        #expect(await manager.activities.first?.contentState == desired.contentState)
    }

    @Test("A manually removed activity is recreated without suppression")
    func manualRemovalIsRecreated() async throws {
        let desired = try snapshot()
        let manager = LiveActivityManagerFake()
        let coordinator = makeCoordinator(manager: manager)

        _ = await coordinator.reconcile(context: .foreground, desiredActivity: desired)
        await manager.removeAllActivities()
        let second = await coordinator.reconcile(
            context: .foreground,
            desiredActivity: desired
        )

        #expect(second.actions == [.request])
        #expect(await manager.operations == [.request, .request])
    }

    @Test("No desired occurrence ends every activity immediately")
    func noDesiredOccurrenceEndsActivities() async throws {
        let first = try snapshot(activityID: Self.activityID)
        let second = try snapshot(activityID: Self.duplicateActivityID)
        let manager = LiveActivityManagerFake(activities: [first, second])
        let coordinator = makeCoordinator(manager: manager)
        let result = await coordinator.reconcile(
            context: .foreground,
            desiredActivity: nil
        )

        #expect(result.actions == [
            .end(Self.activityID),
            .end(Self.duplicateActivityID),
        ])
        #expect(await manager.activities.isEmpty)
        #expect(await manager.endedContentStates[Self.activityID]?.endsAt == Self.now)
        #expect(await manager.endedContentStates[Self.duplicateActivityID]?.endsAt == Self.now)
    }

    @Test("Disabled and unsupported authorization fail safely")
    func unavailableAuthorizationIsIsolated() async throws {
        for authorization in [
            RestrictionLiveActivityAuthorizationStatus.disabled,
            .unsupported,
        ] {
            let manager = LiveActivityManagerFake(authorization: authorization)
            let coordinator = makeCoordinator(manager: manager)
            let result = await coordinator.reconcile(
                context: .foreground,
                desiredActivity: try snapshot()
            )

            #expect(result.actions.isEmpty)
            #expect(result.failureCodes == [.activityAuthorizationDenied])
            #expect(await manager.operations.isEmpty)
        }
    }

    @Test("Request, update, and end failures never escape the coordinator")
    func activityFailuresAreIsolated() async throws {
        let desired = try snapshot()
        let changed = try snapshot(occurrenceID: "occurrence-2")

        let requestManager = LiveActivityManagerFake(failures: [
            .request: .requestFailed,
        ])
        let requestResult = await makeCoordinator(manager: requestManager)
            .reconcile(context: .foreground, desiredActivity: desired)
        #expect(requestResult.failureCodes == [.activityRequestFailed])

        let updateManager = LiveActivityManagerFake(
            activities: [desired],
            failures: [.update(Self.activityID): .updateFailed]
        )
        let updateResult = await makeCoordinator(manager: updateManager)
            .reconcile(context: .foreground, desiredActivity: changed)
        #expect(updateResult.failureCodes == [.activityUpdateFailed])

        let endManager = LiveActivityManagerFake(
            activities: [desired],
            failures: [.end(Self.activityID): .endFailed]
        )
        let endResult = await makeCoordinator(manager: endManager)
            .reconcile(context: .foreground, desiredActivity: nil)
        #expect(endResult.failureCodes == [.activityEndFailed])
    }

    private func snapshot(
        activityID: UUID = Self.activityID,
        occurrenceID: String = "occurrence-1"
    ) throws -> RestrictionLiveActivitySnapshot {
        RestrictionLiveActivitySnapshot(
            attributes: RestrictionLiveActivityAttributes(
                activityID: activityID,
                restrictionStartedAt: Self.now.addingTimeInterval(-60)
            ),
            contentState: try RestrictionLiveActivityAttributes.ContentState(
                occurrenceID: occurrenceID,
                ruleDisplayName: "집중 시간",
                endsAt: Self.now.addingTimeInterval(3_600),
                remainingDistance: .known(meters: 100),
                distanceObservedAt: Self.now,
                hasAdditionalRestrictions: false
            )
        )
    }

    private func makeCoordinator(
        manager: LiveActivityManagerFake
    ) -> LiveActivityCoordinator {
        LiveActivityCoordinator(
            manager: manager,
            clock: FixedClock(now: Self.now)
        )
    }

    private static let now = Date(timeIntervalSince1970: 1_788_192_300)
    private static let activityID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000201"
    )!
    private static let duplicateActivityID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000202"
    )!
}
