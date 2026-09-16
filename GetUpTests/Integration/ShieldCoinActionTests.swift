import Foundation
@preconcurrency import ManagedSettings
import Testing
@testable import GetUp

@Suite("Shield coin action")
struct ShieldCoinActionTests {
    @Test("Production primary stores a release handoff without executing ledger work")
    func productionPrimaryStoresReleaseHandoff() async throws {
        let routes = PendingRouteSpy()
        let handler = ShieldReleaseRouteHandler(
            loadRoute: { nil },
            saveRoute: { try await routes.save($0) },
            makeRouteID: { Self.routeID },
            makeCommandID: { Self.commandID },
            now: { Self.now }
        )

        let response = await handler.handlePrimaryAction(
            occurrenceID: "occurrence-1",
            operatingSystemVersion: Self.iOS26_5
        )

        expectOpenParentApp(response)
        let route = try #require(await routes.savedRoutes.first)
        #expect(route.destination == .releaseProcessing)
        #expect(route.state == .pending)
        #expect(route.commandID == Self.commandID)
        #expect(route.occurrenceID == "occurrence-1")
    }

    @Test("Production primary preserves an existing command on duplicate delivery")
    func productionDuplicateReusesCommand() async throws {
        let existing = try PendingAppRoute.releaseProcessing(
            routeID: Self.routeID,
            commandID: Self.commandID,
            createdAt: Self.now,
            occurrenceID: "occurrence-1"
        ).claiming(at: Self.now)
        let routes = PendingRouteSpy()
        let handler = ShieldReleaseRouteHandler(
            loadRoute: { existing },
            saveRoute: { try await routes.save($0) },
            makeRouteID: UUID.init,
            makeCommandID: UUID.init,
            now: { Self.now }
        )

        let response = await handler.handlePrimaryAction(
            occurrenceID: "occurrence-1",
            operatingSystemVersion: Self.iOS26_5
        )

        expectOpenParentApp(response)
        #expect(await routes.savedRoutes.isEmpty)
    }

    @Test("A pending duplicate reuses its command within five minutes")
    func pendingDuplicateReusesCommand() async throws {
        let existing = try PendingAppRoute.releaseProcessing(
            routeID: Self.routeID,
            commandID: Self.commandID,
            createdAt: Self.now,
            occurrenceID: "occurrence-1"
        )
        let routes = PendingRouteSpy()
        let handler = ShieldReleaseRouteHandler(
            loadRoute: { existing },
            saveRoute: { try await routes.save($0) },
            now: { Self.now.addingTimeInterval(299) }
        )

        let response = await handler.handlePrimaryAction(
            occurrenceID: "occurrence-1",
            operatingSystemVersion: Self.iOS26_5
        )

        expectOpenParentApp(response)
        #expect(await routes.savedRoutes.isEmpty)
    }

    @Test("An expired pending route receives a new command rather than opening a dead handoff")
    func expiredPendingRouteIsReplaced() async throws {
        let existing = try PendingAppRoute.releaseProcessing(
            routeID: Self.routeID,
            commandID: Self.commandID,
            createdAt: Self.now,
            occurrenceID: "occurrence-1"
        )
        let routes = PendingRouteSpy()
        let handler = ShieldReleaseRouteHandler(
            loadRoute: { existing },
            saveRoute: { try await routes.save($0) },
            makeCommandID: { Self.replacementCommandID },
            now: { Self.now.addingTimeInterval(300) }
        )

        let response = await handler.handlePrimaryAction(
            occurrenceID: "occurrence-1",
            operatingSystemVersion: Self.iOS26_5
        )

        expectOpenParentApp(response)
        #expect(await routes.savedRoutes.first?.commandID == Self.replacementCommandID)
    }

    @Test("Production primary keeps a saved route on the iOS 26.4 fallback")
    func productionLegacyFallbackKeepsRoute() async throws {
        let routes = PendingRouteSpy()
        let handler = ShieldReleaseRouteHandler(
            loadRoute: { nil },
            saveRoute: { try await routes.save($0) },
            now: { Self.now }
        )

        let response = await handler.handlePrimaryAction(
            occurrenceID: "occurrence-1",
            operatingSystemVersion: Self.iOS26_4
        )

        #expect(response == .close)
        #expect(await routes.destinations == [.releaseProcessing])
    }

    @Test("Production route write failure never reports an unlock")
    func productionWriteFailureStaysClosed() async throws {
        let routes = PendingRouteSpy(shouldFailSave: true)
        let handler = ShieldReleaseRouteHandler(
            loadRoute: { nil },
            saveRoute: { try await routes.save($0) },
            now: { Self.now }
        )

        let response = await handler.handlePrimaryAction(
            occurrenceID: "occurrence-1",
            operatingSystemVersion: Self.iOS26_5
        )

        #expect(response == .defer)
        #expect(await routes.savedRoutes.isEmpty)
    }

    @Test("A missing current-period allowance reaches atomic Shield reservation")
    func missingAllowanceBypassesConfirmedZeroShortcut() throws {
        let balance = try CoinBalanceSnapshot.fixture(
            freeAvailable: 0,
            purchasedAvailable: 0
        )

        #expect(
            ShieldFreshLedgerReleaseGate.shouldAttemptRelease(
                balance: balance,
                hasCurrentAllowance: false
            )
        )
        #expect(
            !ShieldFreshLedgerReleaseGate.shouldAttemptRelease(
                balance: balance,
                hasCurrentAllowance: true
            )
        )
    }

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
        #expect(decision.reason == .released)
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
        #expect(decision.reason == .insufficientBalance)
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
        #expect(decision.reason == .releasedOtherRestrictionsRemain)
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
        #expect(decision.reason == .routePersistenceFailed)
        #expect(await fixture.routes.savedRoutes.isEmpty)
    }

    @Test("A rejected release records the fail-closed reason")
    func rejectedReleaseRecordsFailClosedReason() async throws {
        let fixture = try Fixture(
            balance: .fixture(freeAvailable: 2, purchasedAvailable: 0),
            releaseResult: .rejected
        )

        let decision = await fixture.handler.handlePrimaryAction(
            context: fixture.context,
            operatingSystemVersion: Self.iOS26_5
        )

        #expect(decision.response == .defer)
        #expect(decision.keepsShield)
        #expect(decision.reason == .releaseRejected)
        #expect(await fixture.release.requests == [fixture.context.representative])
    }
}

private extension ShieldCoinActionTests {
    static let now = Date(timeIntervalSince1970: 1_788_192_000)
    static let routeID = UUID(uuidString: "00000000-0000-4000-8000-000000000701")!
    static let commandID = UUID(uuidString: "00000000-0000-4000-8000-000000000704")!
    static let replacementCommandID = UUID(uuidString: "00000000-0000-4000-8000-000000000705")!
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
            releaseRepresentative: { context in
                await release.release(context.representative)
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
