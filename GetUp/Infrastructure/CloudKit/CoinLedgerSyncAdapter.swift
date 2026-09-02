import Foundation

struct CoinLedgerSyncSession: Sendable {
    let initialFetchCompleted: Bool
    let lastSuccessfulFetchInstant: ContinuousClock.Instant?
    let accountSessionID: String

    init(
        initialFetchCompleted: Bool,
        lastSuccessfulFetchInstant: ContinuousClock.Instant?,
        accountSessionID: String
    ) {
        self.initialFetchCompleted = initialFetchCompleted
        self.lastSuccessfulFetchInstant = lastSuccessfulFetchInstant
        self.accountSessionID = accountSessionID
    }

    static func empty(accountSessionID: String) -> CoinLedgerSyncSession {
        CoinLedgerSyncSession(
            initialFetchCompleted: false,
            lastSuccessfulFetchInstant: nil,
            accountSessionID: accountSessionID
        )
    }
}

struct CoinLedgerCurrentContext: Sendable {
    let iCloudAccountAvailable: Bool
    let mirror: CoinBalanceSnapshot
    let ledgerEpochID: UUID
    let accountEpochID: UUID
    let projectionCompleted: Bool
    let hasPendingReconciliation: Bool
    let accountSessionID: String?

    init(
        iCloudAccountAvailable: Bool,
        mirror: CoinBalanceSnapshot,
        ledgerEpochID: UUID,
        accountEpochID: UUID,
        projectionCompleted: Bool,
        hasPendingReconciliation: Bool,
        accountSessionID: String? = nil
    ) {
        self.iCloudAccountAvailable = iCloudAccountAvailable
        self.mirror = mirror
        self.ledgerEpochID = ledgerEpochID
        self.accountEpochID = accountEpochID
        self.projectionCompleted = projectionCompleted
        self.hasPendingReconciliation = hasPendingReconciliation
        self.accountSessionID = accountSessionID
    }
}

enum CoinLedgerCurrentGate {
    static let freshnessLimit: Duration = .seconds(300)

    static func isCurrent(
        session: CoinLedgerSyncSession,
        now: ContinuousClock.Instant,
        context: CoinLedgerCurrentContext
    ) -> Bool {
        guard
            context.iCloudAccountAvailable,
            session.initialFetchCompleted,
            let fetchedAt = session.lastSuccessfulFetchInstant,
            context.mirror.syncState == .current,
            context.mirror.hadConfirmedLedger,
            context.mirror.ledgerEpochID == context.ledgerEpochID,
            context.ledgerEpochID == context.accountEpochID,
            context.projectionCompleted,
            !context.hasPendingReconciliation,
            context.accountSessionID.map({ $0 == session.accountSessionID }) ?? true
        else {
            return false
        }

        let elapsed = fetchedAt.duration(to: now)
        return elapsed >= .zero && elapsed <= freshnessLimit
    }
}

struct CoinLedgerRemoteProjection: Equatable, Sendable {
    let ledgerEpochID: UUID
    let accountEpochID: UUID
    let purchasedAvailable: Int
    let currentMonthID: String
    let freeAvailable: Int
    let projectionCompleted: Bool
    let hasPendingReconciliation: Bool

    init(
        ledgerEpochID: UUID,
        accountEpochID: UUID,
        purchasedAvailable: Int,
        currentMonthID: String,
        freeAvailable: Int,
        projectionCompleted: Bool,
        hasPendingReconciliation: Bool
    ) {
        self.ledgerEpochID = ledgerEpochID
        self.accountEpochID = accountEpochID
        self.purchasedAvailable = purchasedAvailable
        self.currentMonthID = currentMonthID
        self.freeAvailable = freeAvailable
        self.projectionCompleted = projectionCompleted
        self.hasPendingReconciliation = hasPendingReconciliation
    }
}

enum CoinLedgerRemoteFetchResult: Equatable, Sendable {
    case ledger(CoinLedgerRemoteProjection)
    case noLedger(deletionConfirmed: Bool)
    case unavailable
}

struct CoinLedgerSyncOutcome: Equatable, Sendable {
    let mirror: CoinBalanceSnapshot
    let recoveredFromRemote: Bool
}

enum CoinLedgerSyncAdapterError: Error, Equatable, Sendable {
    case invalidAccountSessionID
    case invalidRemoteProjection
}

actor CoinLedgerSyncAdapter {
    private(set) var session: CoinLedgerSyncSession
    private(set) var mirror: CoinBalanceSnapshot?
    private(set) var hasPendingLocalChanges = false

    init(accountSessionID: String) {
        session = .empty(accountSessionID: accountSessionID)
    }

    func switchAccount(to accountSessionID: String) throws {
        guard !accountSessionID.isEmpty else {
            throw CoinLedgerSyncAdapterError.invalidAccountSessionID
        }
        guard accountSessionID != session.accountSessionID else {
            return
        }

        session = .empty(accountSessionID: accountSessionID)
        mirror = nil
        hasPendingLocalChanges = false
    }

    func invalidateAccount() {
        session = .empty(accountSessionID: session.accountSessionID)
        mirror = nil
        hasPendingLocalChanges = false
    }

    func markPendingLocalChanges() {
        hasPendingLocalChanges = true
    }

    func applyInitialFetch(
        _ result: CoinLedgerRemoteFetchResult,
        accountSessionID: String,
        localMirror: CoinBalanceSnapshot?,
        currentMonthID: String,
        fetchedAt: ContinuousClock.Instant,
        syncedAt: Date
    ) throws -> CoinLedgerSyncOutcome {
        let accountChanged = accountSessionID != session.accountSessionID
        try switchAccount(to: accountSessionID)
        let isolatedLocalMirror = accountChanged ? nil : localMirror

        switch result {
        case let .ledger(projection):
            guard
                projection.purchasedAvailable >= 0,
                (0...2).contains(projection.freeAvailable),
                !projection.currentMonthID.isEmpty
            else {
                throw CoinLedgerSyncAdapterError.invalidRemoteProjection
            }

            let isConsistent = projection.projectionCompleted
                && !projection.hasPendingReconciliation
                && projection.ledgerEpochID == projection.accountEpochID
            let nextMirror = try CoinBalanceSnapshot(
                purchasedAvailable: projection.purchasedAvailable,
                currentMonthID: projection.currentMonthID,
                freeAvailable: projection.freeAvailable,
                syncState: isConsistent ? .current : .stale,
                syncedAt: syncedAt,
                ledgerEpochID: projection.ledgerEpochID,
                hadConfirmedLedger: true
            )
            session = CoinLedgerSyncSession(
                initialFetchCompleted: true,
                lastSuccessfulFetchInstant: fetchedAt,
                accountSessionID: accountSessionID
            )
            mirror = nextMirror
            hasPendingLocalChanges = projection.hasPendingReconciliation
            return CoinLedgerSyncOutcome(
                mirror: nextMirror,
                recoveredFromRemote: isolatedLocalMirror == nil && isConsistent
            )

        case let .noLedger(deletionConfirmed):
            let nextMirror = try CoinBalanceSnapshot(
                purchasedAvailable: 0,
                currentMonthID: currentMonthID,
                freeAvailable: 0,
                syncState: deletionConfirmed ? .deletionConfirmed : .setupRequired,
                syncedAt: syncedAt,
                ledgerEpochID: nil,
                hadConfirmedLedger: deletionConfirmed
                    || isolatedLocalMirror?.hadConfirmedLedger == true
            )
            session = CoinLedgerSyncSession(
                initialFetchCompleted: true,
                lastSuccessfulFetchInstant: fetchedAt,
                accountSessionID: accountSessionID
            )
            mirror = nextMirror
            hasPendingLocalChanges = false
            return CoinLedgerSyncOutcome(mirror: nextMirror, recoveredFromRemote: false)

        case .unavailable:
            session = .empty(accountSessionID: accountSessionID)
            let nextMirror = try unavailableMirror(
                from: isolatedLocalMirror,
                currentMonthID: currentMonthID,
                syncedAt: syncedAt
            )
            mirror = nextMirror
            return CoinLedgerSyncOutcome(mirror: nextMirror, recoveredFromRemote: false)
        }
    }

    func currentContext(
        iCloudAccountAvailable: Bool,
        projection: CoinLedgerRemoteProjection
    ) -> CoinLedgerCurrentContext? {
        guard let mirror else {
            return nil
        }
        return CoinLedgerCurrentContext(
            iCloudAccountAvailable: iCloudAccountAvailable,
            mirror: mirror,
            ledgerEpochID: projection.ledgerEpochID,
            accountEpochID: projection.accountEpochID,
            projectionCompleted: projection.projectionCompleted,
            hasPendingReconciliation: projection.hasPendingReconciliation
                || hasPendingLocalChanges,
            accountSessionID: session.accountSessionID
        )
    }

    private func unavailableMirror(
        from localMirror: CoinBalanceSnapshot?,
        currentMonthID: String,
        syncedAt: Date
    ) throws -> CoinBalanceSnapshot {
        try CoinBalanceSnapshot(
            purchasedAvailable: localMirror?.purchasedAvailable ?? 0,
            currentMonthID: localMirror?.currentMonthID ?? currentMonthID,
            freeAvailable: localMirror?.freeAvailable ?? 0,
            syncState: .unavailable,
            syncedAt: syncedAt,
            ledgerEpochID: localMirror?.ledgerEpochID,
            hadConfirmedLedger: localMirror?.hadConfirmedLedger ?? false
        )
    }
}
