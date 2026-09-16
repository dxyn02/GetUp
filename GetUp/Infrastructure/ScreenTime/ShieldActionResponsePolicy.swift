import Foundation
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings

struct ShieldActionResponsePolicy {
    func response(for _: ShieldAction) -> ShieldActionResponse {
        .close
    }

    func responseAfterSavingRoute(
        operatingSystemVersion: OperatingSystemVersion
    ) -> ShieldActionResponse {
        guard operatingSystemVersion.isAtLeast(major: 26, minor: 5) else {
            return .close
        }
        if #available(iOS 26.5, *) {
            return .openParentalControlsApp
        }
        return .close
    }
}

/// The production Shield path only hands a stable request to the containing app.
/// It does not inspect a cached balance or perform CloudKit, reservation, or unlock work.
actor ShieldReleaseRouteHandler {
    typealias LoadRoute = @Sendable () async throws -> PendingAppRoute?
    typealias SaveRoute = @Sendable (PendingAppRoute) async throws -> Void

    private let loadRoute: LoadRoute
    private let saveRoute: SaveRoute
    private let makeRouteID: @Sendable () -> UUID
    private let makeCommandID: @Sendable () -> UUID
    private let now: @Sendable () -> Date
    private let responsePolicy: ShieldActionResponsePolicy
    private var isHandling = false

    init(
        loadRoute: @escaping LoadRoute,
        saveRoute: @escaping SaveRoute,
        makeRouteID: @escaping @Sendable () -> UUID = UUID.init,
        makeCommandID: @escaping @Sendable () -> UUID = UUID.init,
        now: @escaping @Sendable () -> Date = Date.init,
        responsePolicy: ShieldActionResponsePolicy = ShieldActionResponsePolicy()
    ) {
        self.loadRoute = loadRoute
        self.saveRoute = saveRoute
        self.makeRouteID = makeRouteID
        self.makeCommandID = makeCommandID
        self.now = now
        self.responsePolicy = responsePolicy
    }

    func handlePrimaryAction(
        occurrenceID: String,
        operatingSystemVersion: OperatingSystemVersion
    ) async -> ShieldActionResponse {
        guard !isHandling, !occurrenceID.isEmpty else { return .defer }
        isHandling = true
        defer { isHandling = false }

        do {
            if let existing = try await loadRoute(),
               existing.destination == .releaseProcessing {
                if existing.state != .pending {
                    guard existing.occurrenceID == occurrenceID else { return .defer }
                    return responsePolicy.responseAfterSavingRoute(
                        operatingSystemVersion: operatingSystemVersion
                    )
                }
                let age = now().timeIntervalSince(existing.createdAt)
                if existing.occurrenceID == occurrenceID,
                   age >= 0,
                   age < PendingAppRouteRepository.validityDuration {
                    return responsePolicy.responseAfterSavingRoute(
                        operatingSystemVersion: operatingSystemVersion
                    )
                }
            }
            let route = try PendingAppRoute.releaseProcessing(
                routeID: makeRouteID(),
                commandID: makeCommandID(),
                createdAt: now(),
                occurrenceID: occurrenceID
            )
            try await saveRoute(route)
            return responsePolicy.responseAfterSavingRoute(
                operatingSystemVersion: operatingSystemVersion
            )
        } catch {
            return .defer
        }
    }
}

struct ShieldCoinActionContext: Equatable, Sendable {
    let representative: RestrictionOccurrence
    let activeRestrictionCount: Int
    let balance: CoinBalanceSnapshot
    let hasPendingReconciliation: Bool
    let prefetchedLedger: CoinRuleReleasePrefetchedLedger?

    init(
        representative: RestrictionOccurrence,
        activeRestrictionCount: Int,
        balance: CoinBalanceSnapshot,
        hasPendingReconciliation: Bool,
        prefetchedLedger: CoinRuleReleasePrefetchedLedger? = nil
    ) {
        self.representative = representative
        self.activeRestrictionCount = activeRestrictionCount
        self.balance = balance
        self.hasPendingReconciliation = hasPendingReconciliation
        self.prefetchedLedger = prefetchedLedger
    }
}

enum ShieldFreshLedgerReleaseGate {
    /// A missing current-period allowance is not a confirmed zero balance. The
    /// authoritative reservation operation must be allowed to atomically create
    /// the allowance and reserve its first free release.
    static func shouldAttemptRelease(
        balance: CoinBalanceSnapshot,
        hasCurrentAllowance: Bool
    ) -> Bool {
        !hasCurrentAllowance
            || balance.freeAvailable > 0
            || balance.purchasedAvailable > 0
    }
}

enum ShieldReleaseAttemptResult: Equatable, Sendable {
    case released(fundingSource: ReleaseFundingSource)
    case insufficientBalance
    case iCloudRecoveryRequired
    case ledgerResetRequired
    case reconciliationRequired
    case rejected
}

struct ShieldCoinActionDecision: Equatable, Sendable {
    enum Reason: String, Equatable, Sendable {
        case released
        case releasedOtherRestrictionsRemain
        case alreadyHandling
        case pendingReconciliation
        case ledgerResetRequired
        case ledgerUnavailable
        case insufficientBalance
        case iCloudRecoveryRequired
        case releaseLedgerResetRequired
        case releaseReconciliationRequired
        case releaseRejected
        case routePersistenceFailed
    }

    let fundingSource: ReleaseFundingSource?
    let response: ShieldActionResponse
    let keepsShield: Bool
    let reason: Reason
}

actor ShieldCoinActionHandler {
    typealias ReleaseRepresentative = @Sendable (
        ShieldCoinActionContext
    ) async -> ShieldReleaseAttemptResult
    typealias SavePendingRoute = @Sendable (PendingAppRoute) async throws -> Void
    typealias DiscardPendingRoute = @Sendable () async throws -> Void

    private let releaseRepresentative: ReleaseRepresentative
    private let savePendingRoute: SavePendingRoute
    private let discardPendingRoute: DiscardPendingRoute
    private let makeRouteID: @Sendable () -> UUID
    private let now: @Sendable () -> Date
    private let responsePolicy: ShieldActionResponsePolicy
    private var isHandlingPrimaryAction = false

    init(
        releaseRepresentative: @escaping ReleaseRepresentative,
        savePendingRoute: @escaping SavePendingRoute,
        discardPendingRoute: @escaping DiscardPendingRoute = {},
        makeRouteID: @escaping @Sendable () -> UUID = UUID.init,
        now: @escaping @Sendable () -> Date = Date.init,
        responsePolicy: ShieldActionResponsePolicy = ShieldActionResponsePolicy()
    ) {
        self.releaseRepresentative = releaseRepresentative
        self.savePendingRoute = savePendingRoute
        self.discardPendingRoute = discardPendingRoute
        self.makeRouteID = makeRouteID
        self.now = now
        self.responsePolicy = responsePolicy
    }

    func handlePrimaryAction(
        context: ShieldCoinActionContext,
        operatingSystemVersion: OperatingSystemVersion
    ) async -> ShieldCoinActionDecision {
        guard !isHandlingPrimaryAction else {
            return failClosedDecision(reason: .alreadyHandling)
        }
        isHandlingPrimaryAction = true
        defer { isHandlingPrimaryAction = false }

        if context.hasPendingReconciliation {
            return await route(
                to: .reconciliation,
                reason: .pendingReconciliation,
                occurrenceID: context.representative.id,
                operatingSystemVersion: operatingSystemVersion
            )
        }

        switch context.balance.syncState {
        case .current:
            break
        case .deletionConfirmed, .resetRequired:
            return await route(
                to: .ledgerReset,
                reason: .ledgerResetRequired,
                occurrenceID: context.representative.id,
                operatingSystemVersion: operatingSystemVersion
            )
        case .setupRequired, .syncing, .stale, .unavailable:
            return await route(
                to: .iCloudRecovery,
                reason: .ledgerUnavailable,
                occurrenceID: context.representative.id,
                operatingSystemVersion: operatingSystemVersion
            )
        }

        switch await releaseRepresentative(context) {
        case .released(let fundingSource):
            try? await discardPendingRoute()
            let keepsShield = context.activeRestrictionCount > 1
            return ShieldCoinActionDecision(
                fundingSource: fundingSource,
                response: keepsShield ? .defer : .none,
                keepsShield: keepsShield,
                reason: keepsShield ? .releasedOtherRestrictionsRemain : .released
            )
        case .insufficientBalance:
            return await route(
                to: .coinStore,
                reason: .insufficientBalance,
                occurrenceID: context.representative.id,
                operatingSystemVersion: operatingSystemVersion
            )
        case .iCloudRecoveryRequired:
            return await route(
                to: .iCloudRecovery,
                reason: .iCloudRecoveryRequired,
                occurrenceID: context.representative.id,
                operatingSystemVersion: operatingSystemVersion
            )
        case .ledgerResetRequired:
            return await route(
                to: .ledgerReset,
                reason: .releaseLedgerResetRequired,
                occurrenceID: context.representative.id,
                operatingSystemVersion: operatingSystemVersion
            )
        case .reconciliationRequired:
            return await route(
                to: .reconciliation,
                reason: .releaseReconciliationRequired,
                occurrenceID: context.representative.id,
                operatingSystemVersion: operatingSystemVersion
            )
        case .rejected:
            return failClosedDecision(reason: .releaseRejected)
        }
    }

    private func route(
        to destination: PendingAppRouteDestination,
        reason: ShieldCoinActionDecision.Reason,
        occurrenceID: String,
        operatingSystemVersion: OperatingSystemVersion
    ) async -> ShieldCoinActionDecision {
        do {
            try await savePendingRoute(PendingAppRoute(
                routeID: makeRouteID(),
                destination: destination,
                createdAt: now(),
                occurrenceID: occurrenceID,
                consumedAt: nil
            ))
        } catch {
            return failClosedDecision(reason: .routePersistenceFailed)
        }

        return ShieldCoinActionDecision(
            fundingSource: nil,
            response: responsePolicy.responseAfterSavingRoute(
                operatingSystemVersion: operatingSystemVersion
            ),
            keepsShield: true,
            reason: reason
        )
    }

    private func failClosedDecision(
        reason: ShieldCoinActionDecision.Reason
    ) -> ShieldCoinActionDecision {
        ShieldCoinActionDecision(
            fundingSource: nil,
            response: .defer,
            keepsShield: true,
            reason: reason
        )
    }
}

enum ShieldCoinActionContextReaderError: Error, Equatable, Sendable {
    case snapshotUnavailable
    case noMatchingOccurrence
}

struct ShieldCoinActionContextReader: Sendable {
    let containerURL: URL
    let tokenRefresher: any ShieldTokenRefreshing
    let now: @Sendable () -> Date

    init(
        containerURL: URL,
        tokenRefresher: any ShieldTokenRefreshing = SystemShieldTokenRefresher(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.containerURL = containerURL
        self.tokenRefresher = tokenRefresher
        self.now = now
    }

    func context(for applicationToken: ApplicationToken) async throws
        -> ShieldCoinActionContext
    {
        try await context {
            shieldTokenMatches(
                applicationToken,
                storedTokens: $0.applicationTokens,
                refresh: tokenRefresher.applicationTokens
            )
        }
    }

    func releaseOccurrence(for applicationToken: ApplicationToken) throws -> RestrictionOccurrence {
        try releaseOccurrence {
            shieldTokenMatches(
                applicationToken,
                storedTokens: $0.applicationTokens,
                refresh: tokenRefresher.applicationTokens
            )
        }
    }

    func releaseOccurrence(for categoryToken: ActivityCategoryToken) throws -> RestrictionOccurrence {
        try releaseOccurrence {
            shieldTokenMatches(
                categoryToken,
                storedTokens: $0.categoryTokens,
                refresh: tokenRefresher.categoryTokens
            )
        }
    }

    func releaseOccurrence(for webDomainToken: WebDomainToken) throws -> RestrictionOccurrence {
        try releaseOccurrence {
            shieldTokenMatches(
                webDomainToken,
                storedTokens: $0.webDomainTokens,
                refresh: tokenRefresher.webDomainTokens
            )
        }
    }

    private func releaseOccurrence(
        matches: (FamilyActivitySelection) -> Bool
    ) throws -> RestrictionOccurrence {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rules = try decode(
            RestrictionRuleCollectionSnapshot.self,
            fileName: SharedIdentifiers.restrictionRulesFileName,
            decoder: decoder
        )
        let active = try decode(
            ActiveRestrictionSnapshot.self,
            fileName: SharedIdentifiers.activeRestrictionSnapshotFileName,
            decoder: decoder
        )
        guard rules.schemaVersion == RestrictionRuleCollectionSnapshot.currentSchemaVersion,
              active.schemaVersion == ActiveRestrictionSnapshot.currentSchemaVersion else {
            throw ShieldCoinActionContextReaderError.snapshotUnavailable
        }
        let rulesByID = Dictionary(uniqueKeysWithValues: rules.rules.map { ($0.id, $0) })
        guard let representative = RestrictionOccurrenceEvaluator.evaluate(
            snapshot: active,
            currentRuleRevisions: Dictionary(
                uniqueKeysWithValues: rules.rules.map { ($0.id, $0.revision) }
            ),
            now: now()
        ).orderedOccurrences.first(where: { occurrence in
            rulesByID[occurrence.ruleID].map { matches($0.activitySelection) } ?? false
        }) else {
            throw ShieldCoinActionContextReaderError.noMatchingOccurrence
        }
        return representative
    }

    func context(for categoryToken: ActivityCategoryToken) async throws
        -> ShieldCoinActionContext
    {
        try await context {
            shieldTokenMatches(
                categoryToken,
                storedTokens: $0.categoryTokens,
                refresh: tokenRefresher.categoryTokens
            )
        }
    }

    func context(for webDomainToken: WebDomainToken) async throws
        -> ShieldCoinActionContext
    {
        try await context {
            shieldTokenMatches(
                webDomainToken,
                storedTokens: $0.webDomainTokens,
                refresh: tokenRefresher.webDomainTokens
            )
        }
    }

    private func context(
        matches: (FamilyActivitySelection) -> Bool
    ) async throws -> ShieldCoinActionContext {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rules = try decode(
            RestrictionRuleCollectionSnapshot.self,
            fileName: SharedIdentifiers.restrictionRulesFileName,
            decoder: decoder
        )
        let active = try decode(
            ActiveRestrictionSnapshot.self,
            fileName: SharedIdentifiers.activeRestrictionSnapshotFileName,
            decoder: decoder
        )
        let balance = try decode(
            CoinBalanceSnapshot.self,
            fileName: SharedIdentifiers.coinBalanceSnapshotFileName,
            decoder: decoder
        )
        guard
            rules.schemaVersion == RestrictionRuleCollectionSnapshot.currentSchemaVersion,
            active.schemaVersion == ActiveRestrictionSnapshot.currentSchemaVersion,
            balance.schemaVersion == CoinBalanceSnapshot.currentSchemaVersion
        else {
            throw ShieldCoinActionContextReaderError.snapshotUnavailable
        }

        let rulesByID = Dictionary(uniqueKeysWithValues: rules.rules.map { ($0.id, $0) })
        let occurrences = RestrictionOccurrenceEvaluator.evaluate(
            snapshot: active,
            currentRuleRevisions: Dictionary(
                uniqueKeysWithValues: rules.rules.map { ($0.id, $0.revision) }
            ),
            now: now()
        ).orderedOccurrences.filter { occurrence in
            rulesByID[occurrence.ruleID].map { matches($0.activitySelection) } ?? false
        }
        guard let representative = occurrences.first else {
            throw ShieldCoinActionContextReaderError.noMatchingOccurrence
        }

        let pendingRoute = try? await PendingAppRouteRepository(
            containerURL: containerURL
        ).load()
        return ShieldCoinActionContext(
            representative: representative,
            activeRestrictionCount: occurrences.count,
            balance: balance,
            hasPendingReconciliation: pendingRoute?.destination == .reconciliation
        )
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        fileName: String,
        decoder: JSONDecoder
    ) throws -> Value {
        do {
            let data = try Data(contentsOf: containerURL.appendingPathComponent(fileName))
            return try decoder.decode(type, from: data)
        } catch {
            throw ShieldCoinActionContextReaderError.snapshotUnavailable
        }
    }
}

private extension OperatingSystemVersion {
    func isAtLeast(major: Int, minor: Int) -> Bool {
        if majorVersion != major {
            return majorVersion > major
        }
        return minorVersion >= minor
    }
}
