import Foundation
import Testing
@testable import GetUp

@Suite("Active restriction release routing")
@MainActor
struct ActiveRestrictionReleaseRouterTests {
    @Test("An eligible pending route is the only source of automatic navigation")
    func consumesEligibleRoute() async throws {
        let occurrenceID = "occurrence-current"
        let now = Date(timeIntervalSince1970: 1_788_192_000)
        let route = try PendingAppRoute(
            routeID: UUID(),
            destination: .coinStore,
            createdAt: now.addingTimeInterval(-60),
            occurrenceID: occurrenceID,
            consumedAt: nil
        )
        let recorder = RouteConsumptionRecorder(route: route)
        let router = ActiveRestrictionReleaseRouter { date, activeIDs in
            await recorder.consume(now: date, activeOccurrenceIDs: activeIDs)
        }

        await router.consumeIfEligible(
            now: now,
            activeOccurrenceIDs: [occurrenceID]
        )

        #expect(router.destination == .coinStore)
        #expect(router.consumptionState == .consumed)
        #expect(await recorder.requestCount == 1)
        #expect(await recorder.receivedOccurrenceIDs == [occurrenceID])
    }

    @Test("A discarded pending route never opens a destination")
    func discardedRouteDoesNotNavigate() async {
        let router = ActiveRestrictionReleaseRouter { _, _ in nil }

        await router.consumeIfEligible(
            now: Date(timeIntervalSince1970: 1_788_192_000),
            activeOccurrenceIDs: []
        )

        #expect(router.destination == nil)
        #expect(router.consumptionState == .consumed)
    }

    @Test("A repository failure is visible but does not guess a destination")
    func repositoryFailureDoesNotNavigate() async {
        let router = ActiveRestrictionReleaseRouter { _, _ in
            throw RouteConsumptionError.failed
        }

        await router.consumeIfEligible(
            now: Date(timeIntervalSince1970: 1_788_192_000),
            activeOccurrenceIDs: []
        )

        #expect(router.destination == nil)
        #expect(router.consumptionState == .failed)
    }

    @Test("The tapped active card carries only its rule selection into the sheet")
    func carriesPreferredRuleSelection() {
        let router = ActiveRestrictionReleaseRouter()
        let ruleID = UUID()

        router.prefer(ruleID: ruleID)
        #expect(router.preferredRuleID == ruleID)

        router.clearPreferredRule()
        #expect(router.preferredRuleID == nil)
    }

    @Test(
        "Every blocked release state opens only its matching recovery destination",
        arguments: [
            (ActiveRestrictionReleaseAvailability.insufficientBalance,
             PendingAppRouteDestination.coinStore),
            (.iCloudRecoveryRequired, .iCloudRecovery),
            (.ledgerResetRequired, .ledgerReset),
            (.reconciliationRequired, .reconciliation),
        ]
    )
    func mapsBlockedAvailability(
        availability: ActiveRestrictionReleaseAvailability,
        destination: PendingAppRouteDestination
    ) {
        let router = ActiveRestrictionReleaseRouter()

        router.present(for: availability)

        #expect(router.destination == destination)
        router.dismissDestination()
        #expect(router.destination == nil)
    }

    @Test(
        "Non-routing release states never invent a destination",
        arguments: [
            ActiveRestrictionReleaseAvailability.ready,
            .noActiveRestriction,
            .releaseFailed,
        ]
    )
    func ignoresNonRoutingAvailability(
        availability: ActiveRestrictionReleaseAvailability
    ) {
        let router = ActiveRestrictionReleaseRouter()

        router.present(for: availability)

        #expect(router.destination == nil)
    }
}

private enum RouteConsumptionError: Error {
    case failed
}

private actor RouteConsumptionRecorder {
    let route: PendingAppRoute?
    private(set) var requestCount = 0
    private(set) var receivedOccurrenceIDs: Set<String> = []

    init(route: PendingAppRoute?) {
        self.route = route
    }

    func consume(
        now: Date,
        activeOccurrenceIDs: Set<String>
    ) -> PendingAppRoute? {
        _ = now
        requestCount += 1
        receivedOccurrenceIDs = activeOccurrenceIDs
        return route
    }
}
