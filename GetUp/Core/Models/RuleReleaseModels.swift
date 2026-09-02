import Foundation

enum ReleaseRequestSource: String, Codable, Equatable, Hashable, Sendable {
    case shield
    case app
}

enum ReleaseFundingSource: String, Codable, Equatable, Hashable, Sendable {
    case monthlyFree
    case purchased
}

enum ReleaseCommandState: String, Codable, Equatable, Hashable, Sendable {
    case requested
    case rejected
    case reserved
    case applied
    case committed
    case compensating
    case compensated
    case reconciliationRequired
}

struct ReleaseCommand: Codable, Equatable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let commandID: UUID
    let occurrenceID: String
    let ruleID: UUID
    let requestedFrom: ReleaseRequestSource
    let fundingSource: ReleaseFundingSource?
    let state: ReleaseCommandState
    let createdAt: Date
    let updatedAt: Date
    let failureCode: String?

    static func requested(
        commandID: UUID,
        occurrenceID: String,
        ruleID: UUID,
        requestedFrom: ReleaseRequestSource,
        at date: Date
    ) throws -> ReleaseCommand {
        guard !occurrenceID.isEmpty else {
            throw LiveActivityCoinModelError.invalidReleaseCommandTransition
        }

        return ReleaseCommand(
            schemaVersion: currentSchemaVersion,
            commandID: commandID,
            occurrenceID: occurrenceID,
            ruleID: ruleID,
            requestedFrom: requestedFrom,
            fundingSource: nil,
            state: .requested,
            createdAt: date,
            updatedAt: date,
            failureCode: nil
        )
    }

    func transitioning(
        to nextState: ReleaseCommandState,
        fundingSource proposedFundingSource: ReleaseFundingSource? = nil,
        failureCode: String? = nil,
        at date: Date
    ) throws -> ReleaseCommand {
        guard
            Self.allowedTransitions[state, default: []].contains(nextState),
            date >= updatedAt,
            failureCode?.isEmpty != true
        else {
            throw LiveActivityCoinModelError.invalidReleaseCommandTransition
        }

        let nextFundingSource: ReleaseFundingSource?
        if let fundingSource {
            guard proposedFundingSource == nil || proposedFundingSource == fundingSource else {
                throw LiveActivityCoinModelError.invalidReleaseCommandTransition
            }
            nextFundingSource = fundingSource
        } else {
            nextFundingSource = proposedFundingSource
        }

        guard Self.hasValidFundingSource(nextFundingSource, for: nextState) else {
            throw LiveActivityCoinModelError.invalidReleaseCommandTransition
        }

        return ReleaseCommand(
            schemaVersion: schemaVersion,
            commandID: commandID,
            occurrenceID: occurrenceID,
            ruleID: ruleID,
            requestedFrom: requestedFrom,
            fundingSource: nextFundingSource,
            state: nextState,
            createdAt: createdAt,
            updatedAt: date,
            failureCode: failureCode ?? self.failureCode
        )
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = ReleaseCommand(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            commandID: try container.decode(UUID.self, forKey: .commandID),
            occurrenceID: try container.decode(String.self, forKey: .occurrenceID),
            ruleID: try container.decode(UUID.self, forKey: .ruleID),
            requestedFrom: try container.decode(
                ReleaseRequestSource.self,
                forKey: .requestedFrom
            ),
            fundingSource: try container.decodeIfPresent(
                ReleaseFundingSource.self,
                forKey: .fundingSource
            ),
            state: try container.decode(ReleaseCommandState.self, forKey: .state),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            failureCode: try container.decodeIfPresent(String.self, forKey: .failureCode)
        )

        guard decoded.isValidPersistedState else {
            throw LiveActivityCoinModelError.invalidReleaseCommandTransition
        }
        self = decoded
    }

    private init(
        schemaVersion: Int,
        commandID: UUID,
        occurrenceID: String,
        ruleID: UUID,
        requestedFrom: ReleaseRequestSource,
        fundingSource: ReleaseFundingSource?,
        state: ReleaseCommandState,
        createdAt: Date,
        updatedAt: Date,
        failureCode: String?
    ) {
        self.schemaVersion = schemaVersion
        self.commandID = commandID
        self.occurrenceID = occurrenceID
        self.ruleID = ruleID
        self.requestedFrom = requestedFrom
        self.fundingSource = fundingSource
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.failureCode = failureCode
    }

    private var isValidPersistedState: Bool {
        schemaVersion == Self.currentSchemaVersion
            && !occurrenceID.isEmpty
            && createdAt <= updatedAt
            && failureCode?.isEmpty != true
            && Self.hasValidFundingSource(fundingSource, for: state)
    }

    private static func hasValidFundingSource(
        _ fundingSource: ReleaseFundingSource?,
        for state: ReleaseCommandState
    ) -> Bool {
        switch state {
        case .requested, .rejected:
            fundingSource == nil
        case .reserved, .applied, .committed, .compensating, .compensated:
            fundingSource != nil
        case .reconciliationRequired:
            true
        }
    }

    private static let allowedTransitions: [ReleaseCommandState: Set<ReleaseCommandState>] = [
        .requested: [.rejected, .reserved, .reconciliationRequired],
        .reserved: [.applied, .compensating, .reconciliationRequired],
        .applied: [.committed, .compensating, .reconciliationRequired],
        .compensating: [.compensated, .reconciliationRequired],
        .reconciliationRequired: [.committed, .compensated],
    ]
}

struct ReleaseException: Codable, Equatable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let commandID: UUID
    let occurrenceID: String
    let ruleID: UUID
    let ruleRevision: Int
    let effectiveAt: Date
    let expiresAt: Date

    init(
        schemaVersion: Int = ReleaseException.currentSchemaVersion,
        commandID: UUID,
        occurrenceID: String,
        ruleID: UUID,
        ruleRevision: Int,
        effectiveAt: Date,
        expiresAt: Date
    ) throws {
        guard
            schemaVersion == Self.currentSchemaVersion,
            !occurrenceID.isEmpty,
            ruleRevision >= 0,
            effectiveAt < expiresAt
        else {
            throw LiveActivityCoinModelError.invalidReleaseExceptionInterval
        }

        self.schemaVersion = schemaVersion
        self.commandID = commandID
        self.occurrenceID = occurrenceID
        self.ruleID = ruleID
        self.ruleRevision = ruleRevision
        self.effectiveAt = effectiveAt
        self.expiresAt = expiresAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            commandID: container.decode(UUID.self, forKey: .commandID),
            occurrenceID: container.decode(String.self, forKey: .occurrenceID),
            ruleID: container.decode(UUID.self, forKey: .ruleID),
            ruleRevision: container.decode(Int.self, forKey: .ruleRevision),
            effectiveAt: container.decode(Date.self, forKey: .effectiveAt),
            expiresAt: container.decode(Date.self, forKey: .expiresAt)
        )
    }
}

struct ReleaseExceptionCollectionSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let exceptions: [ReleaseException]

    init(
        schemaVersion: Int = ReleaseExceptionCollectionSnapshot.currentSchemaVersion,
        exceptions: [ReleaseException]
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LiveActivityCoinModelError.unsupportedReleaseExceptionCollectionSchema(
                schemaVersion
            )
        }
        guard
            Set(exceptions.map(\.commandID)).count == exceptions.count,
            Set(exceptions.map(\.occurrenceID)).count == exceptions.count
        else {
            throw LiveActivityCoinModelError.invalidReleaseExceptionCollection
        }

        self.schemaVersion = schemaVersion
        self.exceptions = exceptions
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            exceptions: container.decode([ReleaseException].self, forKey: .exceptions)
        )
    }
}

enum PendingAppRouteDestination: String, Codable, Equatable, Hashable, Sendable {
    case coinStore
    case iCloudRecovery
    case ledgerReset
    case reconciliation
}

struct PendingAppRoute: Codable, Equatable, Hashable, Sendable {
    let routeID: UUID
    let destination: PendingAppRouteDestination
    let createdAt: Date
    let occurrenceID: String?
    let consumedAt: Date?

    init(
        routeID: UUID,
        destination: PendingAppRouteDestination,
        createdAt: Date,
        occurrenceID: String?,
        consumedAt: Date?
    ) throws {
        if occurrenceID?.isEmpty == true {
            throw LiveActivityCoinModelError.invalidPendingAppRoute
        }
        if let consumedAt, consumedAt < createdAt {
            throw LiveActivityCoinModelError.invalidPendingAppRoute
        }

        self.routeID = routeID
        self.destination = destination
        self.createdAt = createdAt
        self.occurrenceID = occurrenceID
        self.consumedAt = consumedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            routeID: container.decode(UUID.self, forKey: .routeID),
            destination: container.decode(
                PendingAppRouteDestination.self,
                forKey: .destination
            ),
            createdAt: container.decode(Date.self, forKey: .createdAt),
            occurrenceID: container.decodeIfPresent(String.self, forKey: .occurrenceID),
            consumedAt: container.decodeIfPresent(Date.self, forKey: .consumedAt)
        )
    }
}
