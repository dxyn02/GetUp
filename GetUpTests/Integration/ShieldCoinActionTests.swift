import Foundation
@preconcurrency import ManagedSettings
import Testing
@testable import GetUp

@Suite("Shield coin action")
struct ShieldCoinActionTests {
    @Test("The one primary action spends the monthly free use first")
    func primaryActionUsesMonthlyFreeFirst() async throws {
        let fixture = try Fixture(
            balance: .fixture(freeAvailable: 1, purchasedAvailable: 3),
            releaseResult: .released(fundingSource: .monthlyFree)
        )

        let decision = await fixture.handler.handlePrimaryAction(
            context: fixture.context,
            operatingSystemVersion: Self.iOS26_5
        )

        #expect(decision.fundingSource == .monthlyFree)
        #expect(decision.response == .none)
        #expect(decision.keepsShield == false)
        #expect(await fixture.release.requests == [fixture.context.representative])
        #expect(await fixture.routes.savedRoutes.isEmpty)
    }

    @Test("The same primary action falls back to one purchased coin")
    func primaryActionFallsBackToPurchasedCoin() async throws {
        let fixture = try Fixture(
            balance: .fixture(freeAvailable: 0, purchasedAvailable: 2),
            releaseResult: .released(fundingSource: .purchased)
        )

        let decision = await fixture.handler.handlePrimaryAction(
            context: fixture.context,
            operatingSystemVersion: Self.iOS26_5
        )

        #expect(decision.fundingSource == .purchased)
        #expect(decision.response == .none)
        #expect(await fixture.release.requests.count == 1)
        #expect(await fixture.routes.savedRoutes.isEmpty)
    }

    @Test("Confirmed insufficient balance keeps the Shield and routes to the coin store")
    func insufficientBalanceRoutesToCoinStore() async throws {
        let fixture = try Fixture(
            balance: .fixture(freeAvailable: 0, purchasedAvailable: 0),
            releaseResult: .insufficientBalance
        )

        let decision = await fixture.handler.handlePrimaryAction(
            context: fixture.context,
            operatingSystemVersion: Self.iOS26_5
        )

        expectOpenParentApp(decision.response)
        #expect(decision.keepsShield)
        #expect(decision.fundingSource == nil)
        #expect(await fixture.routes.destinations == [.coinStore])
    }

    @Test(
        "Stale and unavailable ledgers route to iCloud recovery without attempting release",
        arguments: [CoinBalanceSyncState.stale, .unavailable]
    )
    func unavailableLedgerRoutesToICloudRecovery(syncState: CoinBalanceSyncState) async throws {
        let fixture = try Fixture(
            balance: .fixture(
                freeAvailable: 2,
                purchasedAvailable: 5,
                syncState: syncState
            ),
            releaseResult: .released(fundingSource: .monthlyFree)
        )

        let decision = await fixture.handler.handlePrimaryAction(
            context: fixture.context,
            operatingSystemVersion: Self.iOS26_5
        )

        expectOpenParentApp(decision.response)
        #expect(decision.keepsShield)
        #expect(await fixture.release.requests.isEmpty)
        #expect(await fixture.routes.destinations == [.iCloudRecovery])
    }

    @Test(
        "A deleted ledger routes to reset guidance without releasing or purchasing",
        arguments: [CoinBalanceSyncState.deletionConfirmed, .resetRequired]
    )
    func deletedLedgerRoutesToReset(syncState: CoinBalanceSyncState) async throws {
        let fixture = try Fixture(
            balance: .fixture(
                freeAvailable: 2,
                purchasedAvailable: 5,
                syncState: syncState
            ),
            releaseResult: .released(fundingSource: .monthlyFree)
        )

        let decision = await fixture.handler.handlePrimaryAction(
            context: fixture.context,
            operatingSystemVersion: Self.iOS26_5
        )

        expectOpenParentApp(decision.response)
        #expect(decision.keepsShield)
        #expect(await fixture.release.requests.isEmpty)
        #expect(await fixture.routes.destinations == [.ledgerReset])
    }

    @Test("Pending reconciliation takes priority over a new release")
    func reconciliationRoutesBeforeNewRelease() async throws {
        let fixture = try Fixture(
            balance: .fixture(freeAvailable: 1, purchasedAvailable: 1),
            hasPendingReconciliation: true,
            releaseResult: .released(fundingSource: .monthlyFree)
        )

        let decision = await fixture.handler.handlePrimaryAction(
            context: fixture.context,
            operatingSystemVersion: Self.iOS26_5
        )

        expectOpenParentApp(decision.response)
        #expect(decision.keepsShield)
        #expect(await fixture.release.requests.isEmpty)
        #expect(await fixture.routes.destinations == [.reconciliation])
    }

    @Test("Only the representative is released and another matching rule keeps the Shield")
    func multipleRulesKeepShieldAfterRepresentativeRelease() async throws {
        let fixture = try Fixture(
            balance: .fixture(freeAvailable: 1, purchasedAvailable: 0),
            activeRestrictionCount: 2,
            releaseResult: .released(fundingSource: .monthlyFree)
        )

        let decision = await fixture.handler.handlePrimaryAction(
            context: fixture.context,
            operatingSystemVersion: Self.iOS26_5
        )

        #expect(decision.response == .defer)
        #expect(decision.keepsShield)
        #expect(await fixture.release.requests == [fixture.context.representative])
        #expect(await fixture.release.requests.count == 1)
    }

    @Test("iOS before 26.5 saves the same route and closes instead of opening the app")
    func olderIOSClosesAfterSavingRoute() async throws {
        let modern = try Fixture(
            balance: .fixture(freeAvailable: 0, purchasedAvailable: 0),
            releaseResult: .insufficientBalance
        )
        let legacy = try Fixture(
            balance: .fixture(freeAvailable: 0, purchasedAvailable: 0),
            releaseResult: .insufficientBalance
        )

        let modernDecision = await modern.handler.handlePrimaryAction(
            context: modern.context,
            operatingSystemVersion: Self.iOS26_5
        )
        let legacyDecision = await legacy.handler.handlePrimaryAction(
            context: legacy.context,
            operatingSystemVersion: Self.iOS26_4
        )

        expectOpenParentApp(modernDecision.response)
        #expect(legacyDecision.response == .close)
        #expect(await modern.routes.destinations == [.coinStore])
        #expect(await legacy.routes.destinations == [.coinStore])
    }
}

private extension ShieldCoinActionTests {
    static let now = Date(timeIntervalSince1970: 1_788_192_000)
    static let routeID = UUID(uuidString: "00000000-0000-4000-8000-000000000701")!
    static let iOS26_5 = OperatingSystemVersion(majorVersion: 26, minorVersion: 5, patchVersion: 0)
    static let iOS26_4 = OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0)

    func expectOpenParentApp(_ response: ShieldActionResponse) {
        if #available(iOS 26.5, *) {
            #expect(response == .openParentalControlsApp)
        } else {
            Issue.record("This compatibility test requires iOS 26.5 or later")
        }
    }
}

private struct Fixture {
    let context: ShieldCoinActionContext
    let release: ShieldReleaseSpy
    let routes: PendingRouteSpy
    let handler: ShieldCoinActionHandler

    init(
        balance: CoinBalanceSnapshot,
        activeRestrictionCount: Int = 1,
        hasPendingReconciliation: Bool = false,
        releaseResult: ShieldReleaseAttemptResult
    ) throws {
        let representative = try RestrictionOccurrence(
            ruleID: UUID(uuidString: "00000000-0000-4000-8000-000000000702")!,
            ruleRevision: 4,
            startAt: ShieldCoinActionTests.now.addingTimeInterval(-600),
            endAt: ShieldCoinActionTests.now.addingTimeInterval(3_000),
            activatedAt: ShieldCoinActionTests.now.addingTimeInterval(-300)
        )
        let release = ShieldReleaseSpy(result: releaseResult)
        let routes = PendingRouteSpy()

        self.context = ShieldCoinActionContext(
            representative: representative,
            activeRestrictionCount: activeRestrictionCount,
            balance: balance,
            hasPendingReconciliation: hasPendingReconciliation
        )
        self.release = release
        self.routes = routes
        self.handler = ShieldCoinActionHandler(
            releaseRepresentative: { occurrence in
                await release.release(occurrence)
            },
            savePendingRoute: { route in
                try await routes.save(route)
            },
            makeRouteID: { ShieldCoinActionTests.routeID },
            now: { ShieldCoinActionTests.now }
        )
    }
}

private actor ShieldReleaseSpy {
    private let result: ShieldReleaseAttemptResult
    private(set) var requests: [RestrictionOccurrence] = []

    init(result: ShieldReleaseAttemptResult) {
        self.result = result
    }

    func release(_ occurrence: RestrictionOccurrence) -> ShieldReleaseAttemptResult {
        requests.append(occurrence)
        return result
    }
}

private actor PendingRouteSpy {
    private(set) var savedRoutes: [PendingAppRoute] = []

    var destinations: [PendingAppRouteDestination] {
        savedRoutes.map(\.destination)
    }

    func save(_ route: PendingAppRoute) throws {
        savedRoutes.append(route)
    }
}

private extension CoinBalanceSnapshot {
    static func fixture(
        freeAvailable: Int,
        purchasedAvailable: Int,
        syncState: CoinBalanceSyncState = .current
    ) throws -> CoinBalanceSnapshot {
        try CoinBalanceSnapshot(
            purchasedAvailable: purchasedAvailable,
            currentMonthID: "2026-09",
            freeAvailable: freeAvailable,
            syncState: syncState,
            syncedAt: ShieldCoinActionTests.now,
            ledgerEpochID: syncState == .current
                ? UUID(uuidString: "00000000-0000-4000-8000-000000000703")!
                : nil,
            hadConfirmedLedger: syncState == .current
        )
    }
}
