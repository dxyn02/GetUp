import Foundation
import Testing
@testable import GetUp

enum LiveActivityCoinScript<Value: Sendable, Failure: Error & Sendable>: Sendable {
    case success(Value)
    case failure(Failure)

    func get() throws -> Value {
        switch self {
        case .success(let value): value
        case .failure(let error): throw error
        }
    }
}

final class LiveActivityCoinMonotonicClock: @unchecked Sendable {
    let origin: ContinuousClock.Instant

    private let lock = NSLock()
    private var elapsed: Duration

    init(
        origin: ContinuousClock.Instant = ContinuousClock().now,
        elapsed: Duration = .zero
    ) {
        self.origin = origin
        self.elapsed = elapsed
    }

    var now: ContinuousClock.Instant {
        lock.withLock { origin.advanced(by: elapsed) }
    }

    func advance(by duration: Duration) {
        lock.withLock { elapsed += duration }
    }

    func setElapsed(_ duration: Duration) {
        lock.withLock { elapsed = duration }
    }

    func successfulFetchSession(accountSessionID: String) -> CoinLedgerSyncSession {
        CoinLedgerSyncSession(
            initialFetchCompleted: true,
            lastSuccessfulFetchInstant: now,
            accountSessionID: accountSessionID
        )
    }

    func restartedSession(accountSessionID: String) -> CoinLedgerSyncSession {
        .empty(accountSessionID: accountSessionID)
    }
}

final class LiveActivityCoinWallClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var currentDate: Date

    init(now: Date) {
        currentDate = now
    }

    var now: Date {
        lock.withLock { currentDate }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { currentDate = currentDate.addingTimeInterval(interval) }
    }

    func setNow(_ date: Date) {
        lock.withLock { currentDate = date }
    }
}

enum ShieldReleaseTimingFixture: CaseIterable, Sendable {
    case confirmedAtFourPointNineSeconds
    case unconfirmedAtFiveSeconds
    case committedAfterDeadline

    static let deadline: Duration = .seconds(5)

    var confirmationDelay: Duration {
        switch self {
        case .confirmedAtFourPointNineSeconds: .milliseconds(4_900)
        case .unconfirmedAtFiveSeconds: .seconds(5)
        case .committedAfterDeadline: .milliseconds(5_100)
        }
    }

    var isConfirmedBeforeDeadline: Bool {
        confirmationDelay < Self.deadline
    }

    var eventuallyCommitsOnServer: Bool {
        self != .unconfirmedAtFiveSeconds
    }
}

actor LiveActivityManagerFake: RestrictionLiveActivityManaging {
    enum Operation: Equatable, Hashable, Sendable {
        case request
        case update(UUID)
        case end(UUID)
    }

    var authorization: RestrictionLiveActivityAuthorizationStatus
    var activities: [RestrictionLiveActivitySnapshot]
    private var failures: [Operation: RestrictionLiveActivityError]
    private(set) var operations: [Operation] = []
    private(set) var endedContentStates: [UUID: RestrictionLiveActivityAttributes.ContentState] = [:]
    private(set) var authorizationRequestCount = 0
    private(set) var activeActivitiesRequestCount = 0

    init(
        authorization: RestrictionLiveActivityAuthorizationStatus = .enabled,
        activities: [RestrictionLiveActivitySnapshot] = [],
        failures: [Operation: RestrictionLiveActivityError] = [:]
    ) {
        self.authorization = authorization
        self.activities = activities
        self.failures = failures
    }

    func authorizationStatus() async -> RestrictionLiveActivityAuthorizationStatus {
        authorizationRequestCount += 1
        return authorization
    }

    func activeActivities() async -> [RestrictionLiveActivitySnapshot] {
        activeActivitiesRequestCount += 1
        return activities
    }

    func request(
        attributes: RestrictionLiveActivityAttributes,
        contentState: RestrictionLiveActivityAttributes.ContentState
    ) async throws {
        try record(.request)
        activities.append(
            RestrictionLiveActivitySnapshot(
                attributes: attributes,
                contentState: contentState
            )
        )
    }

    func update(
        activityID: UUID,
        contentState: RestrictionLiveActivityAttributes.ContentState
    ) async throws {
        try record(.update(activityID))
        guard let index = activities.firstIndex(where: {
            $0.attributes.activityID == activityID
        }) else {
            throw RestrictionLiveActivityError.updateFailed
        }
        activities[index] = RestrictionLiveActivitySnapshot(
            attributes: activities[index].attributes,
            contentState: contentState
        )
    }

    func end(
        activityID: UUID,
        finalContentState: RestrictionLiveActivityAttributes.ContentState
    ) async throws {
        try record(.end(activityID))
        guard let index = activities.firstIndex(where: {
            $0.attributes.activityID == activityID
        }) else {
            throw RestrictionLiveActivityError.endFailed
        }
        endedContentStates[activityID] = finalContentState
        activities.remove(at: index)
    }

    func setFailure(_ error: RestrictionLiveActivityError?, for operation: Operation) {
        failures[operation] = error
    }

    func removeAllActivities() {
        activities.removeAll()
    }

    private func record(_ operation: Operation) throws {
        operations.append(operation)
        if let error = failures[operation] {
            throw error
        }
    }
}

actor CoinLedgerCloudDatabaseFake: CoinLedgerCloudDatabase {
    private var fetchScripts: [LiveActivityCoinScript<
        [CloudKitRecordSnapshot], CoinLedgerDatabaseError
    >]
    private var modifyScripts: [LiveActivityCoinScript<
        [CloudKitRecordSnapshot], CoinLedgerDatabaseError
    >]
    private(set) var fetchRequests: [CoinLedgerFetchRequest] = []
    private(set) var modifyRequests: [CoinLedgerModifyRequest] = []

    init(
        fetch: [LiveActivityCoinScript<
            [CloudKitRecordSnapshot], CoinLedgerDatabaseError
        >] = [],
        modify: [LiveActivityCoinScript<
            [CloudKitRecordSnapshot], CoinLedgerDatabaseError
        >] = []
    ) {
        fetchScripts = fetch
        modifyScripts = modify
    }

    func fetch(_ request: CoinLedgerFetchRequest) async throws -> [CloudKitRecordSnapshot] {
        fetchRequests.append(request)
        guard !fetchScripts.isEmpty else {
            throw CoinLedgerDatabaseError.unexpectedRequest
        }
        return try fetchScripts.removeFirst().get()
    }

    func modify(_ request: CoinLedgerModifyRequest) async throws -> [CloudKitRecordSnapshot] {
        modifyRequests.append(request)
        guard !modifyScripts.isEmpty else {
            throw CoinLedgerDatabaseError.unexpectedRequest
        }
        return try modifyScripts.removeFirst().get()
    }
}

actor CoinStorefrontFake: CoinStorefront {
    private var productScripts: [LiveActivityCoinScript<[CoinStoreProduct], CoinStoreError>]
    private var purchaseScripts: [LiveActivityCoinScript<CoinStorePurchaseResult, CoinStoreError>]
    private var finishScripts: [LiveActivityCoinScript<Void, CoinStoreError>]
    private let unfinished: [CoinStoreTransactionUpdate]
    nonisolated let updates: AsyncStream<CoinStoreTransactionUpdate>

    private(set) var productRequests: [Set<String>] = []
    private(set) var purchaseRequests: [String] = []
    private(set) var finishRequests: [UInt64] = []

    init(
        products: [LiveActivityCoinScript<[CoinStoreProduct], CoinStoreError>] = [],
        purchases: [LiveActivityCoinScript<CoinStorePurchaseResult, CoinStoreError>] = [],
        finishes: [LiveActivityCoinScript<Void, CoinStoreError>] = [],
        unfinished: [CoinStoreTransactionUpdate] = [],
        updates: [CoinStoreTransactionUpdate] = []
    ) {
        productScripts = products
        purchaseScripts = purchases
        finishScripts = finishes
        self.unfinished = unfinished
        self.updates = AsyncStream { continuation in
            for update in updates {
                continuation.yield(update)
            }
            continuation.finish()
        }
    }

    func products(for identifiers: Set<String>) async throws -> [CoinStoreProduct] {
        productRequests.append(identifiers)
        guard !productScripts.isEmpty else {
            throw CoinStoreError.productUnavailable
        }
        return try productScripts.removeFirst().get()
    }

    func purchase(productID: String) async throws -> CoinStorePurchaseResult {
        purchaseRequests.append(productID)
        guard !purchaseScripts.isEmpty else {
            throw CoinStoreError.purchaseFailed
        }
        return try purchaseScripts.removeFirst().get()
    }

    func unfinishedTransactions() async -> [CoinStoreTransactionUpdate] {
        unfinished
    }

    nonisolated func transactionUpdates() -> AsyncStream<CoinStoreTransactionUpdate> {
        updates
    }

    func finish(transactionID: UInt64) async throws {
        finishRequests.append(transactionID)
        guard !finishScripts.isEmpty else {
            throw CoinStoreError.finishFailed
        }
        _ = try finishScripts.removeFirst().get()
    }
}

actor CoinLedgerRepositoryFake: CoinLedgerRepository {
    enum Operation: Equatable, Sendable {
        case createAllowance
        case reserveMonthlyFree
        case reservePurchased
        case fetchCommand(UUID)
        case markApplied(UUID)
        case commit(UUID)
        case compensate(UUID)
        case grantPurchase(UInt64)
    }

    private var allowanceScripts: [LiveActivityCoinScript<MonthlyAllowance, CoinLedgerRepositoryError>]
    private var monthlyReservationScripts: [LiveActivityCoinScript<CoinReleaseReservation, CoinLedgerRepositoryError>]
    private var purchasedReservationScripts: [LiveActivityCoinScript<CoinReleaseReservation, CoinLedgerRepositoryError>]
    private var commandScripts: [LiveActivityCoinScript<ReleaseCommand?, CoinLedgerRepositoryError>]
    private var transitionScripts: [LiveActivityCoinScript<ReleaseCommand, CoinLedgerRepositoryError>]
    private var purchaseGrantScripts: [LiveActivityCoinScript<PurchaseGrant, CoinLedgerRepositoryError>]
    private(set) var operations: [Operation] = []

    init(
        allowances: [LiveActivityCoinScript<MonthlyAllowance, CoinLedgerRepositoryError>] = [],
        monthlyReservations: [LiveActivityCoinScript<CoinReleaseReservation, CoinLedgerRepositoryError>] = [],
        purchasedReservations: [LiveActivityCoinScript<CoinReleaseReservation, CoinLedgerRepositoryError>] = [],
        commands: [LiveActivityCoinScript<ReleaseCommand?, CoinLedgerRepositoryError>] = [],
        transitions: [LiveActivityCoinScript<ReleaseCommand, CoinLedgerRepositoryError>] = [],
        purchaseGrants: [LiveActivityCoinScript<PurchaseGrant, CoinLedgerRepositoryError>] = []
    ) {
        allowanceScripts = allowances
        monthlyReservationScripts = monthlyReservations
        purchasedReservationScripts = purchasedReservations
        commandScripts = commands
        transitionScripts = transitions
        purchaseGrantScripts = purchaseGrants
    }

    func createAllowanceIfNeeded(
        _ request: MonthlyAllowanceCreationRequest
    ) async throws -> MonthlyAllowance {
        operations.append(.createAllowance)
        return try pop(&allowanceScripts)
    }

    func reserveMonthlyFree(
        _ request: MonthlyFreeReservationRequest
    ) async throws -> CoinReleaseReservation {
        operations.append(.reserveMonthlyFree)
        return try pop(&monthlyReservationScripts)
    }

    func reservePurchasedCoin(
        _ request: PurchasedCoinReservationRequest
    ) async throws -> CoinReleaseReservation {
        operations.append(.reservePurchased)
        return try pop(&purchasedReservationScripts)
    }

    func fetchReleaseCommand(commandID: UUID) async throws -> ReleaseCommand? {
        operations.append(.fetchCommand(commandID))
        return try pop(&commandScripts)
    }

    func markReleaseApplied(commandID: UUID, at date: Date) async throws -> ReleaseCommand {
        operations.append(.markApplied(commandID))
        return try pop(&transitionScripts)
    }

    func commitRelease(commandID: UUID, at date: Date) async throws -> ReleaseCommand {
        operations.append(.commit(commandID))
        return try pop(&transitionScripts)
    }

    func compensateRelease(commandID: UUID, at date: Date) async throws -> ReleaseCommand {
        operations.append(.compensate(commandID))
        return try pop(&transitionScripts)
    }

    func grantPurchase(_ request: PurchaseGrantRequest) async throws -> PurchaseGrant {
        operations.append(.grantPurchase(request.transaction.id))
        return try pop(&purchaseGrantScripts)
    }

    private func pop<Value: Sendable>(
        _ scripts: inout [LiveActivityCoinScript<Value, CoinLedgerRepositoryError>]
    ) throws -> Value {
        guard !scripts.isEmpty else {
            throw CoinLedgerRepositoryError.database(.unexpectedRequest)
        }
        return try scripts.removeFirst().get()
    }
}

enum LiveActivityCoinFixtures {
    static let now = Date(timeIntervalSince1970: 1_788_192_000)
    static let epochID = UUID(uuidString: "00000000-0000-4000-8000-000000000601")!
    static let activityID = UUID(uuidString: "00000000-0000-4000-8000-000000000602")!
    static let commandID = UUID(uuidString: "00000000-0000-4000-8000-000000000603")!
    static let ruleID = UUID(uuidString: "00000000-0000-4000-8000-000000000604")!

    static func contentState() throws -> RestrictionLiveActivityAttributes.ContentState {
        try RestrictionLiveActivityAttributes.ContentState(
            occurrenceID: "occurrence-1",
            ruleDisplayName: "테스트 규칙",
            endsAt: now.addingTimeInterval(3_600),
            remainingDistance: .known(meters: 100),
            distanceObservedAt: now,
            hasAdditionalRestrictions: false
        )
    }

    static func liveActivitySnapshot() throws -> RestrictionLiveActivitySnapshot {
        RestrictionLiveActivitySnapshot(
            attributes: RestrictionLiveActivityAttributes(
                activityID: activityID,
                restrictionStartedAt: now
            ),
            contentState: try contentState()
        )
    }

    static func allowance() throws -> MonthlyAllowance {
        try MonthlyAllowance(
            monthID: "2026-09",
            quota: 2,
            used: 0,
            reserved: 0,
            creationDate: now,
            updatedAt: now
        )
    }
}

@Suite("Live Activity coin test fixtures")
struct LiveActivityCoinFixtureTests {
    @Test("Monotonic freshness is independent from wall clock and process restart")
    func deterministicClocks() throws {
        let monotonic = LiveActivityCoinMonotonicClock()
        let wall = LiveActivityCoinWallClock(now: LiveActivityCoinFixtures.now)
        let session = monotonic.successfulFetchSession(accountSessionID: "account-a")
        let snapshot = try CoinBalanceSnapshot(
            purchasedAvailable: 1,
            currentMonthID: "2026-09",
            freeAvailable: 2,
            syncState: .current,
            syncedAt: wall.now,
            ledgerEpochID: LiveActivityCoinFixtures.epochID,
            hadConfirmedLedger: true
        )
        let context = CoinLedgerCurrentContext(
            iCloudAccountAvailable: true,
            mirror: snapshot,
            ledgerEpochID: LiveActivityCoinFixtures.epochID,
            accountEpochID: LiveActivityCoinFixtures.epochID,
            projectionCompleted: true,
            hasPendingReconciliation: false
        )

        wall.advance(by: 31_536_000)
        monotonic.advance(by: .seconds(300))
        #expect(CoinLedgerCurrentGate.isCurrent(
            session: session,
            now: monotonic.now,
            context: context
        ))
        monotonic.advance(by: .seconds(1))
        #expect(!CoinLedgerCurrentGate.isCurrent(
            session: session,
            now: monotonic.now,
            context: context
        ))
        #expect(!CoinLedgerCurrentGate.isCurrent(
            session: monotonic.restartedSession(accountSessionID: "account-a"),
            now: monotonic.now,
            context: context
        ))
    }

    @Test("Shield deadline fixtures distinguish 4.9 seconds, 5 seconds, and late commit")
    func shieldTimingBoundaries() {
        #expect(ShieldReleaseTimingFixture.confirmedAtFourPointNineSeconds.isConfirmedBeforeDeadline)
        #expect(!ShieldReleaseTimingFixture.unconfirmedAtFiveSeconds.isConfirmedBeforeDeadline)
        #expect(!ShieldReleaseTimingFixture.committedAfterDeadline.isConfirmedBeforeDeadline)
        #expect(ShieldReleaseTimingFixture.committedAfterDeadline.eventuallyCommitsOnServer)
    }

    @Test("Framework and release fakes inject stable failures and retain calls")
    func failureInjection() async throws {
        let content = try LiveActivityCoinFixtures.contentState()
        let activity = LiveActivityManagerFake(failures: [
            .request: .requestFailed,
        ])
        do {
            try await activity.request(
                attributes: RestrictionLiveActivityAttributes(
                    activityID: LiveActivityCoinFixtures.activityID,
                    restrictionStartedAt: LiveActivityCoinFixtures.now
                ),
                contentState: content
            )
            Issue.record("ActivityKit failure was not injected")
        } catch {
            #expect(error as? RestrictionLiveActivityError == .requestFailed)
        }
        #expect(await activity.operations == [.request])

        let cloud = CoinLedgerCloudDatabaseFake(fetch: [
            .failure(.serverUnavailable),
        ])
        do {
            _ = try await cloud.fetch(CoinLedgerFetchRequest(recordNames: ["coin-account"]))
            Issue.record("CloudKit failure was not injected")
        } catch {
            #expect(error as? CoinLedgerDatabaseError == .serverUnavailable)
        }
        #expect(await cloud.fetchRequests.count == 1)

        let store = CoinStorefrontFake(purchases: [
            .failure(.purchaseFailed),
        ])
        do {
            _ = try await store.purchase(productID: "coin.1")
            Issue.record("StoreKit failure was not injected")
        } catch {
            #expect(error as? CoinStoreError == .purchaseFailed)
        }
        #expect(await store.purchaseRequests == ["coin.1"])

        let ledger = CoinLedgerRepositoryFake(monthlyReservations: [
            .failure(.reconciliationRequired(commandID: LiveActivityCoinFixtures.commandID)),
        ])
        do {
            _ = try await ledger.reserveMonthlyFree(MonthlyFreeReservationRequest(
                commandID: LiveActivityCoinFixtures.commandID,
                occurrenceID: "occurrence-1",
                ruleID: LiveActivityCoinFixtures.ruleID,
                ruleRevision: 1,
                monthID: "2026-09",
                ledgerEpochID: LiveActivityCoinFixtures.epochID,
                requestedFrom: .shield,
                requestedAt: LiveActivityCoinFixtures.now
            ))
            Issue.record("Release failure was not injected")
        } catch {
            #expect(error as? CoinLedgerRepositoryError == .reconciliationRequired(
                commandID: LiveActivityCoinFixtures.commandID
            ))
        }
        #expect(await ledger.operations == [.reserveMonthlyFree])
    }
}
