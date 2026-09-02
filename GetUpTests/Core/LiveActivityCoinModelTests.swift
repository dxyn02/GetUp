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

    @Test("Every occurrence identity field contributes to its deterministic ID")
    func occurrenceIdentityInputsAreDistinct() throws {
        let occurrence = try makeOccurrence()
        let otherRule = try RestrictionOccurrence(
            ruleID: UUID(uuidString: "00000000-0000-4000-8000-000000000104")!,
            ruleRevision: occurrence.ruleRevision,
            startAt: occurrence.startAt,
            endAt: occurrence.endAt,
            activatedAt: occurrence.activatedAt
        )
        let otherRevision = try RestrictionOccurrence(
            ruleID: occurrence.ruleID,
            ruleRevision: occurrence.ruleRevision + 1,
            startAt: occurrence.startAt,
            endAt: occurrence.endAt,
            activatedAt: occurrence.activatedAt
        )
        let otherStart = try RestrictionOccurrence(
            ruleID: occurrence.ruleID,
            ruleRevision: occurrence.ruleRevision,
            startAt: occurrence.startAt.addingTimeInterval(1),
            endAt: occurrence.endAt,
            activatedAt: occurrence.activatedAt
        )
        let otherEnd = try RestrictionOccurrence(
            ruleID: occurrence.ruleID,
            ruleRevision: occurrence.ruleRevision,
            startAt: occurrence.startAt,
            endAt: occurrence.endAt.addingTimeInterval(1),
            activatedAt: occurrence.activatedAt
        )
        let otherActivation = try RestrictionOccurrence(
            ruleID: occurrence.ruleID,
            ruleRevision: occurrence.ruleRevision,
            startAt: occurrence.startAt,
            endAt: occurrence.endAt,
            activatedAt: occurrence.activatedAt.addingTimeInterval(1)
        )

        #expect(Set([
            occurrence.id,
            otherRule.id,
            otherRevision.id,
            otherStart.id,
            otherEnd.id,
        ]).count == 5)
        #expect(otherActivation.id == occurrence.id)
    }

    @Test("Restriction occurrence rejects a persisted ID that does not match its fields")
    func occurrenceRejectsForgedPersistedID() throws {
        let data = try JSONEncoder().encode(makeOccurrence())
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["id"] = "forged-occurrence-id"
        let forgedData = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: LiveActivityCoinModelError.invalidOccurrenceID) {
            _ = try JSONDecoder().decode(RestrictionOccurrence.self, from: forgedData)
        }
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

    @Test("Live Activity unavailable distance carries no observation date")
    func liveActivityUnavailableDistanceHasNoObservation() throws {
        let valid = try RestrictionLiveActivityAttributes.ContentState(
            occurrenceID: "occurrence-1",
            ruleDisplayName: "Home",
            endsAt: Self.endAt,
            remainingDistance: .unavailable,
            distanceObservedAt: nil,
            hasAdditionalRestrictions: false
        )

        #expect(try roundTrip(valid) == valid)
        #expect(throws: LiveActivityCoinModelError.unexpectedDistanceObservation) {
            try RestrictionLiveActivityAttributes.ContentState(
                occurrenceID: "occurrence-1",
                ruleDisplayName: "Home",
                endsAt: Self.endAt,
                remainingDistance: .unavailable,
                distanceObservedAt: Self.activatedAt,
                hasAdditionalRestrictions: false
            )
        }
    }

    @Test("Live Activity attributes and content state remain below four kilobytes")
    func liveActivityPayloadSize() throws {
        let attributes = RestrictionLiveActivityAttributes(
            activityID: Self.routeID,
            restrictionStartedAt: Self.activatedAt
        )
        let contentState = try RestrictionLiveActivityAttributes.ContentState(
            occurrenceID: try makeOccurrence().id,
            ruleDisplayName: String(repeating: "집", count: SavedPlaceNamePolicy.maximumLength),
            endsAt: Self.endAt,
            remainingDistance: .known(meters: 1_000),
            distanceObservedAt: Self.activatedAt,
            hasAdditionalRestrictions: true
        )
        let encoder = JSONEncoder()
        let attributesData = try encoder.encode(attributes)
        let contentStateData = try encoder.encode(contentState)
        let payloadSize = attributesData.count + contentStateData.count
        let encodedPayload = String(decoding: attributesData, as: UTF8.self)
            + String(decoding: contentStateData, as: UTF8.self)

        #expect(payloadSize < RestrictionLiveActivityAttributes.maximumPayloadSizeInBytes)
        for forbiddenFragment in ["latitude", "longitude", "accuracy", "coordinate", "address"] {
            #expect(!encodedPayload.lowercased().contains(forbiddenFragment))
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

    @Test("Coin account exposes only unreserved purchased balance")
    func coinAccountUsableBalanceAndCodableRoundTrip() throws {
        let account = try CoinAccount(
            purchasedAvailable: 5,
            purchasedReserved: 2,
            revision: 3,
            updatedAt: Self.activatedAt
        )

        #expect(account.purchasedUsable == 3)
        #expect(try roundTrip(account) == account)
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

    @Test("Ledger event requires a positive quantity and round-trips through Codable")
    func coinLedgerEventInvariantAndCodableRoundTrip() throws {
        let event = try CoinLedgerEvent(
            eventID: "free:2026-09",
            kind: .freeGrant,
            source: .monthlyFree,
            quantity: 2,
            relatedTransactionID: nil,
            relatedCommandID: nil,
            occurrenceID: nil,
            createdAt: Self.activatedAt
        )

        #expect(try roundTrip(event) == event)
        #expect(throws: LiveActivityCoinModelError.invalidCoinLedgerEvent) {
            try CoinLedgerEvent(
                eventID: "free:2026-09",
                kind: .freeGrant,
                source: .monthlyFree,
                quantity: 0,
                relatedTransactionID: nil,
                relatedCommandID: nil,
                occurrenceID: nil,
                createdAt: Self.activatedAt
            )
        }
    }

    @Test("Setup-required balance mirror cannot authorize coin operations")
    func setupRequiredBalanceSnapshot() throws {
        let epoch = LedgerEpoch(
            epochID: Self.routeID,
            createdAt: Self.activatedAt,
            reason: .initialSetup,
            suppressedFreeMonthID: nil,
            disclosureVersion: 1
        )
        let snapshot = try CoinBalanceSnapshot(
            purchasedAvailable: 0,
            currentMonthID: "2026-09",
            freeAvailable: 0,
            syncState: .setupRequired,
            syncedAt: Self.activatedAt,
            ledgerEpochID: nil,
            hadConfirmedLedger: false
        )

        #expect(try roundTrip(epoch) == epoch)
        #expect(try roundTrip(snapshot) == snapshot)
        #expect(snapshot.syncState == .setupRequired)
        #expect(throws: LiveActivityCoinModelError.invalidCoinBalanceSnapshot) {
            try CoinBalanceSnapshot(
                purchasedAvailable: 0,
                currentMonthID: "2026-09",
                freeAvailable: 2,
                syncState: .current,
                syncedAt: Self.activatedAt,
                ledgerEpochID: nil,
                hadConfirmedLedger: false
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
        try! CoinBalanceSnapshot(
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
