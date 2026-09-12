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
        #expect(await fixture.routes.discardCount == 1)
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

    @Test("The tap result, not the displayed mirror, determines the actual funding source")
    func latestLedgerResultOverridesDisplayedMirror() async throws {
        let freeMirror = try Fixture(
            balance: .fixture(freeAvailable: 2, purchasedAvailable: 0),
            releaseResult: .released(fundingSource: .purchased)
        )
        let purchasedMirror = try Fixture(
            balance: .fixture(freeAvailable: 0, purchasedAvailable: 3),
            releaseResult: .released(fundingSource: .monthlyFree)
        )

        let purchasedDecision = await freeMirror.handler.handlePrimaryAction(
            context: freeMirror.context,
            operatingSystemVersion: Self.iOS26_5
        )
        let freeDecision = await purchasedMirror.handler.handlePrimaryAction(
            context: purchasedMirror.context,
            operatingSystemVersion: Self.iOS26_5
        )

        #expect(purchasedDecision.fundingSource == .purchased)
        #expect(freeDecision.fundingSource == .monthlyFree)
        #expect(await freeMirror.release.requests == [freeMirror.context.representative])
        #expect(await purchasedMirror.release.requests == [purchasedMirror.context.representative])
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
        "A non-current recoverable ledger routes to iCloud recovery without attempting release",
        arguments: [
            CoinBalanceSyncState.setupRequired,
            .syncing,
            .stale,
            .unavailable,
        ]
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

    @Test("A timeout or unknown release result routes to reconciliation")
    func unknownReleaseResultRoutesToReconciliation() async throws {
        let fixture = try Fixture(
            balance: .fixture(freeAvailable: 1, purchasedAvailable: 1),
            releaseResult: .reconciliationRequired
        )

        let decision = await fixture.handler.handlePrimaryAction(
            context: fixture.context,
            operatingSystemVersion: Self.iOS26_5
        )

        expectOpenParentApp(decision.response)
        #expect(decision.keepsShield)
        #expect(await fixture.routes.destinations == [.reconciliation])
    }

    @Test("A route persistence failure stays fail-closed")
    func routePersistenceFailureStaysFailClosed() async throws {
        let fixture = try Fixture(
            balance: .fixture(freeAvailable: 0, purchasedAvailable: 0),
            releaseResult: .insufficientBalance,
            shouldFailRouteSave: true
        )

        let decision = await fixture.handler.handlePrimaryAction(
            context: fixture.context,
            operatingSystemVersion: Self.iOS26_5
        )

        #expect(decision.response == .defer)
        #expect(decision.keepsShield)
        #expect(await fixture.routes.savedRoutes.isEmpty)
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
        releaseResult: ShieldReleaseAttemptResult,
        shouldFailRouteSave: Bool = false
    ) throws {
        let representative = try RestrictionOccurrence(
            ruleID: UUID(uuidString: "00000000-0000-4000-8000-000000000702")!,
            ruleRevision: 4,
            startAt: ShieldCoinActionTests.now.addingTimeInterval(-600),
            endAt: ShieldCoinActionTests.now.addingTimeInterval(3_000),
            activatedAt: ShieldCoinActionTests.now.addingTimeInterval(-300)
        )
        let release = ShieldReleaseSpy(result: releaseResult)
        let routes = PendingRouteSpy(shouldFailSave: shouldFailRouteSave)

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
            discardPendingRoute: {
                await routes.discard()
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
    private let shouldFailSave: Bool
    private(set) var savedRoutes: [PendingAppRoute] = []
    private(set) var discardCount = 0

    init(shouldFailSave: Bool = false) {
        self.shouldFailSave = shouldFailSave
    }

    var destinations: [PendingAppRouteDestination] {
        savedRoutes.map(\.destination)
    }

    func save(_ route: PendingAppRoute) throws {
        if shouldFailSave {
            throw PendingRouteSpyError.writeFailed
        }
        savedRoutes.append(route)
    }

    func discard() {
        discardCount += 1
        savedRoutes = []
    }
}

private enum PendingRouteSpyError: Error {
    case writeFailed
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
