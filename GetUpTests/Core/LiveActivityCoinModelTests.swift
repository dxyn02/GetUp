import Foundation
import Testing
@testable import GetUp

@Suite("Live Activity and coin domain models")
struct LiveActivityCoinModelTests {
    @Test("Restriction occurrence has a deterministic ID and round-trips through Codable")
    func occurrenceIdentityAndCodableRoundTrip() throws {
        let occurrence = try makeOccurrence()
        let recreated = try makeOccurrence()

        #expect(occurrence.id == recreated.id)
        #expect(try roundTrip(occurrence) == occurrence)
    }

    @Test("Restriction occurrence rejects a non-positive interval")
    func occurrenceRejectsInvalidInterval() {
        #expect(throws: LiveActivityCoinModelError.invalidOccurrenceInterval) {
            try makeOccurrence(startAt: Self.endAt, endAt: Self.startAt)
        }
    }

    @Test("Active restriction snapshot rejects duplicate occurrence IDs")
    func activeSnapshotRejectsDuplicateOccurrences() throws {
        let occurrence = try makeOccurrence()

        #expect(throws: LiveActivityCoinModelError.duplicateOccurrenceID(occurrence.id)) {
            try ActiveRestrictionSnapshot(
                revision: 1,
                occurrences: [occurrence, occurrence],
                observedAt: Self.activatedAt
            )
        }
    }

    @Test("Live Activity known distance requires a matching observation date")
    func liveActivityKnownDistanceRequiresObservationDate() throws {
        let valid = try RestrictionLiveActivityAttributes.ContentState(
            occurrenceID: "occurrence-1",
            ruleDisplayName: "Home",
            endsAt: Self.endAt,
            remainingDistance: .known(meters: 120),
            distanceObservedAt: Self.activatedAt,
            hasAdditionalRestrictions: false
        )

        #expect(try roundTrip(valid) == valid)
        #expect(throws: LiveActivityCoinModelError.missingDistanceObservation) {
            try RestrictionLiveActivityAttributes.ContentState(
                occurrenceID: "occurrence-1",
                ruleDisplayName: "Home",
                endsAt: Self.endAt,
                remainingDistance: .known(meters: 120),
                distanceObservedAt: nil,
                hasAdditionalRestrictions: false
            )
        }
    }

    @Test("Live Activity payload rejects coordinates and negative known distance by construction")
    func liveActivityDistanceInvariant() {
        #expect(throws: LiveActivityCoinModelError.invalidRemainingDistance) {
            try RestrictionLiveActivityAttributes.ContentState(
                occurrenceID: "occurrence-1",
                ruleDisplayName: "Work",
                endsAt: Self.endAt,
                remainingDistance: .known(meters: -10),
                distanceObservedAt: Self.activatedAt,
                hasAdditionalRestrictions: true
            )
        }
    }

    @Test("Coin account never exposes a negative available balance")
    func coinAccountRejectsOverReservation() {
        #expect(throws: LiveActivityCoinModelError.invalidPurchasedBalance) {
            try CoinAccount(
                purchasedAvailable: 1,
                purchasedReserved: 2,
                revision: 1,
                updatedAt: Self.activatedAt
            )
        }
    }

    @Test("Purchase grant quantity and adjustment stay within the verified purchase")
    func purchaseGrantInvariantAndCodableRoundTrip() throws {
        let grant = try PurchaseGrant(
            transactionID: 42,
            environment: .sandbox,
            productID: "com.dxyn02.GetUp.coin.3",
            quantity: 3,
            purchaseDate: Self.activatedAt,
            adjustedQuantity: 1
        )

        #expect(try roundTrip(grant) == grant)
        #expect(throws: LiveActivityCoinModelError.invalidPurchaseAdjustment) {
            try PurchaseGrant(
                transactionID: 42,
                environment: .sandbox,
                productID: "com.dxyn02.GetUp.coin.3",
                quantity: 3,
                purchaseDate: Self.activatedAt,
                adjustedQuantity: 4
            )
        }
    }

    @Test("Release command accepts only declared state transitions")
    func releaseCommandStateTransitionInvariant() throws {
        let requested = ReleaseCommand.requested(
            commandID: Self.commandID,
            occurrenceID: "occurrence-1",
            ruleID: Self.ruleID,
            requestedFrom: .shield,
            at: Self.activatedAt
        )
        let reserved = try requested.transitioning(
            to: .reserved,
            fundingSource: .monthlyFree,
            at: Self.activatedAt.addingTimeInterval(1)
        )

        #expect(reserved.state == .reserved)
        #expect(try roundTrip(reserved) == reserved)
        #expect(throws: LiveActivityCoinModelError.invalidReleaseCommandTransition) {
            try requested.transitioning(
                to: .committed,
                fundingSource: .monthlyFree,
                at: Self.activatedAt.addingTimeInterval(1)
            )
        }
    }

    @Test("Release exception is limited to one positive occurrence interval")
    func releaseExceptionInvariantAndCodableRoundTrip() throws {
        let exception = try ReleaseException(
            commandID: Self.commandID,
            occurrenceID: "occurrence-1",
            ruleID: Self.ruleID,
            ruleRevision: 3,
            effectiveAt: Self.activatedAt,
            expiresAt: Self.endAt
        )

        #expect(try roundTrip(exception) == exception)
        #expect(throws: LiveActivityCoinModelError.invalidReleaseExceptionInterval) {
            try ReleaseException(
                commandID: Self.commandID,
                occurrenceID: "occurrence-1",
                ruleID: Self.ruleID,
                ruleRevision: 3,
                effectiveAt: Self.endAt,
                expiresAt: Self.activatedAt
            )
        }
    }

    @Test("Pending app route preserves its one-time navigation context through Codable")
    func pendingRouteCodableRoundTrip() throws {
        let route = PendingAppRoute(
            routeID: Self.routeID,
            destination: .reconciliation,
            createdAt: Self.activatedAt,
            occurrenceID: "occurrence-1",
            consumedAt: nil
        )

        #expect(try roundTrip(route) == route)
    }
}

@Suite("Coin ledger current gate")
struct CoinLedgerCurrentGateTests {
    @Test("A successful fetch is current through exactly five monotonic minutes")
    func monotonicFreshnessBoundary() {
        let clock = ContinuousClock()
        let fetchedAt = clock.now
        let session = CoinLedgerSyncSession(
            initialFetchCompleted: true,
            lastSuccessfulFetchInstant: fetchedAt,
            accountSessionID: "icloud-account-a"
        )
        let context = makeContext()

        #expect(
            CoinLedgerCurrentGate.isCurrent(
                session: session,
                now: fetchedAt.advanced(by: .seconds(300)),
                context: context
            )
        )
        #expect(
            !CoinLedgerCurrentGate.isCurrent(
                session: session,
                now: fetchedAt.advanced(by: .seconds(301)),
                context: context
            )
        )
    }

    @Test("Changing wall clock does not change monotonic freshness")
    func wallClockDoesNotAuthorizeCurrentState() {
        let clock = ContinuousClock()
        let fetchedAt = clock.now
        let session = CoinLedgerSyncSession(
            initialFetchCompleted: true,
            lastSuccessfulFetchInstant: fetchedAt,
            accountSessionID: "icloud-account-a"
        )
        let oldWallClockMirror = CoinBalanceSnapshot.fixture(
            syncState: .current,
            syncedAt: Date(timeIntervalSince1970: 1)
        )
        let futureWallClockMirror = CoinBalanceSnapshot.fixture(
            syncState: .current,
            syncedAt: Date.distantFuture
        )

        #expect(
            CoinLedgerCurrentGate.isCurrent(
                session: session,
                now: fetchedAt.advanced(by: .seconds(120)),
                context: makeContext(mirror: oldWallClockMirror)
            )
        )
        #expect(
            CoinLedgerCurrentGate.isCurrent(
                session: session,
                now: fetchedAt.advanced(by: .seconds(120)),
                context: makeContext(mirror: futureWallClockMirror)
            )
        )
    }

    @Test("A new process cannot restore current from a persisted wall clock date")
    func processRestartRequiresNewFetch() {
        let restartedSession = CoinLedgerSyncSession.empty(accountSessionID: "icloud-account-a")
        let persistedCurrentMirror = CoinBalanceSnapshot.fixture(
            syncState: .current,
            syncedAt: Date()
        )

        #expect(
            !CoinLedgerCurrentGate.isCurrent(
                session: restartedSession,
                now: ContinuousClock().now,
                context: makeContext(mirror: persistedCurrentMirror)
            )
        )
    }

    @Test("Epoch mismatch, incomplete projection, or reconciliation blocks current")
    func consistencyGatesBlockCurrent() {
        let clock = ContinuousClock()
        let fetchedAt = clock.now
        let session = CoinLedgerSyncSession(
            initialFetchCompleted: true,
            lastSuccessfulFetchInstant: fetchedAt,
            accountSessionID: "icloud-account-a"
        )

        #expect(!CoinLedgerCurrentGate.isCurrent(
            session: session,
            now: fetchedAt,
            context: makeContext(accountEpochID: UUID())
        ))
        #expect(!CoinLedgerCurrentGate.isCurrent(
            session: session,
            now: fetchedAt,
            context: makeContext(projectionCompleted: false)
        ))
        #expect(!CoinLedgerCurrentGate.isCurrent(
            session: session,
            now: fetchedAt,
            context: makeContext(hasPendingReconciliation: true)
        ))
    }

    private func makeContext(
        mirror: CoinBalanceSnapshot = .fixture(),
        accountEpochID: UUID = epochID,
        projectionCompleted: Bool = true,
        hasPendingReconciliation: Bool = false
    ) -> CoinLedgerCurrentContext {
        CoinLedgerCurrentContext(
            iCloudAccountAvailable: true,
            mirror: mirror,
            ledgerEpochID: Self.epochID,
            accountEpochID: accountEpochID,
            projectionCompleted: projectionCompleted,
            hasPendingReconciliation: hasPendingReconciliation
        )
    }

    fileprivate static let epochID = UUID(uuidString: "00000000-0000-4000-8000-000000000201")!
}

private extension LiveActivityCoinModelTests {
    static let ruleID = UUID(uuidString: "00000000-0000-4000-8000-000000000101")!
    static let commandID = UUID(uuidString: "00000000-0000-4000-8000-000000000102")!
    static let routeID = UUID(uuidString: "00000000-0000-4000-8000-000000000103")!
    static let startAt = Date(timeIntervalSince1970: 1_788_192_000)
    static let endAt = startAt.addingTimeInterval(3_600)
    static let activatedAt = startAt.addingTimeInterval(10)

    func makeOccurrence(
        startAt: Date = Self.startAt,
        endAt: Date = Self.endAt
    ) throws -> RestrictionOccurrence {
        try RestrictionOccurrence(
            ruleID: Self.ruleID,
            ruleRevision: 3,
            startAt: startAt,
            endAt: endAt,
            activatedAt: Self.activatedAt
        )
    }

    func roundTrip<Value>(_ value: Value) throws -> Value
    where Value: Codable & Equatable {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(Value.self, from: data)
    }
}

private extension CoinBalanceSnapshot {
    static func fixture(
        syncState: CoinBalanceSyncState = .current,
        syncedAt: Date = Date(timeIntervalSince1970: 1_788_192_000)
    ) -> CoinBalanceSnapshot {
        CoinBalanceSnapshot(
            purchasedAvailable: 3,
            currentMonthID: "2026-09",
            freeAvailable: 2,
            syncState: syncState,
            syncedAt: syncedAt,
            ledgerEpochID: CoinLedgerCurrentGateTests.epochID,
            hadConfirmedLedger: true
        )
    }
}
