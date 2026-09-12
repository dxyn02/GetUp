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

struct ShieldCoinActionContext: Equatable, Sendable {
    let representative: RestrictionOccurrence
    let activeRestrictionCount: Int
    let balance: CoinBalanceSnapshot
    let hasPendingReconciliation: Bool
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
    let fundingSource: ReleaseFundingSource?
    let response: ShieldActionResponse
    let keepsShield: Bool
}

actor ShieldCoinActionHandler {
    typealias ReleaseRepresentative = @Sendable (
        RestrictionOccurrence
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
            return failClosedDecision
        }
        isHandlingPrimaryAction = true
        defer { isHandlingPrimaryAction = false }

        if context.hasPendingReconciliation {
            return await route(
                to: .reconciliation,
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
                occurrenceID: context.representative.id,
                operatingSystemVersion: operatingSystemVersion
            )
        case .setupRequired, .syncing, .stale, .unavailable:
            return await route(
                to: .iCloudRecovery,
                occurrenceID: context.representative.id,
                operatingSystemVersion: operatingSystemVersion
            )
        }

        switch await releaseRepresentative(context.representative) {
        case .released(let fundingSource):
            try? await discardPendingRoute()
            let keepsShield = context.activeRestrictionCount > 1
            return ShieldCoinActionDecision(
                fundingSource: fundingSource,
                response: keepsShield ? .defer : .none,
                keepsShield: keepsShield
            )
        case .insufficientBalance:
            return await route(
                to: .coinStore,
                occurrenceID: context.representative.id,
                operatingSystemVersion: operatingSystemVersion
            )
        case .iCloudRecoveryRequired:
            return await route(
                to: .iCloudRecovery,
                occurrenceID: context.representative.id,
                operatingSystemVersion: operatingSystemVersion
            )
        case .ledgerResetRequired:
            return await route(
                to: .ledgerReset,
                occurrenceID: context.representative.id,
                operatingSystemVersion: operatingSystemVersion
            )
        case .reconciliationRequired:
            return await route(
                to: .reconciliation,
                occurrenceID: context.representative.id,
                operatingSystemVersion: operatingSystemVersion
            )
        case .rejected:
            return failClosedDecision
        }
    }

    private func route(
        to destination: PendingAppRouteDestination,
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
            return failClosedDecision
        }

        return ShieldCoinActionDecision(
            fundingSource: nil,
            response: responsePolicy.responseAfterSavingRoute(
                operatingSystemVersion: operatingSystemVersion
            ),
            keepsShield: true
        )
    }

    private var failClosedDecision: ShieldCoinActionDecision {
        ShieldCoinActionDecision(
            fundingSource: nil,
            response: .defer,
            keepsShield: true
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
