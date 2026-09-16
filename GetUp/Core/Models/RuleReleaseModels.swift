import Foundation

/// Remote ownership shared by every funding path for one epoch and occurrence.
/// Only an atomic compensation may release it; timestamps do not expire ownership.
struct ReleaseOccurrenceClaim: Equatable, Sendable {
    enum State: String, Equatable, Sendable {
        case held
        case released
    }

    enum ValidationError: Error, Equatable, Sendable {
        case invalidValue
    }

    static let currentSchemaVersion = 1

    let ledgerEpochID: UUID
    let occurrenceID: String
    let commandID: UUID
    let state: State
    let updatedAt: Date

    init(
        ledgerEpochID: UUID,
        occurrenceID: String,
        commandID: UUID,
        state: State,
        updatedAt: Date
    ) throws {
        guard !occurrenceID.isEmpty, updatedAt.timeIntervalSince1970.isFinite else {
            throw ValidationError.invalidValue
        }
        self.ledgerEpochID = ledgerEpochID
        self.occurrenceID = occurrenceID
        self.commandID = commandID
        self.state = state
        self.updatedAt = updatedAt
    }
}

/// Per-command evidence that a writer used the occurrence-claim reservation protocol.
struct ReservationCompatibilityStamp: Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let currentProtocolVersion = 1

    let ledgerEpochID: UUID
    let commandID: UUID
    let occurrenceID: String
    let protocolVersion: Int
    let createdAt: Date

    init(
        ledgerEpochID: UUID,
        commandID: UUID,
        occurrenceID: String,
        protocolVersion: Int = Self.currentProtocolVersion,
        createdAt: Date
    ) throws {
        guard !occurrenceID.isEmpty,
              protocolVersion == Self.currentProtocolVersion,
              createdAt.timeIntervalSince1970.isFinite else {
            throw ReleaseOccurrenceClaim.ValidationError.invalidValue
        }
        self.ledgerEpochID = ledgerEpochID
        self.commandID = commandID
        self.occurrenceID = occurrenceID
        self.protocolVersion = protocolVersion
        self.createdAt = createdAt
    }
}

/// Epoch-bound remote migration state. `preparing` never authorizes reservations.
struct ReservationMigrationMarker: Equatable, Sendable {
    enum State: String, Equatable, Sendable {
        case preparing
        case ready
    }

    static let currentSchemaVersion = 1

    let ledgerEpochID: UUID
    let protocolVersion: Int
    let state: State
    let legacyWritersRetiredAt: Date
    let evidenceVersion: Int
    let updatedAt: Date

    init(
        ledgerEpochID: UUID,
        protocolVersion: Int = ReservationCompatibilityStamp.currentProtocolVersion,
        state: State,
        legacyWritersRetiredAt: Date,
        evidenceVersion: Int,
        updatedAt: Date
    ) throws {
        guard protocolVersion == ReservationCompatibilityStamp.currentProtocolVersion,
              evidenceVersion > 0,
              legacyWritersRetiredAt.timeIntervalSince1970.isFinite,
              updatedAt.timeIntervalSince1970.isFinite,
              updatedAt >= legacyWritersRetiredAt else {
            throw ReleaseOccurrenceClaim.ValidationError.invalidValue
        }
        self.ledgerEpochID = ledgerEpochID
        self.protocolVersion = protocolVersion
        self.state = state
        self.legacyWritersRetiredAt = legacyWritersRetiredAt
        self.evidenceVersion = evidenceVersion
        self.updatedAt = updatedAt
    }
}

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
    case releaseProcessing
    case coinStore
    case iCloudRecovery
    case ledgerReset
    case reconciliation
}

enum PendingAppRouteState: String, Codable, Equatable, Hashable, Sendable {
    case pending
    case processing
    case terminal
}

enum PendingAppRouteTerminalOutcome: String, Codable, Equatable, Hashable, Sendable {
    case completed
    case retryable
    case insufficient
    case recoveryRequired
}

struct PendingAppRoute: Codable, Equatable, Hashable, Sendable {
    let routeID: UUID
    let destination: PendingAppRouteDestination
    let commandID: UUID?
    let createdAt: Date
    let occurrenceID: String?
    let state: PendingAppRouteState
    let claimedAt: Date?
    let terminalOutcome: PendingAppRouteTerminalOutcome?
    let retryAfter: Date?
    let presentedAt: Date?
    let acknowledgedAt: Date?
    /// Retained only to decode and safely retire the pre-handoff route format.
    let consumedAt: Date?

    init(
        routeID: UUID,
        destination: PendingAppRouteDestination,
        createdAt: Date,
        occurrenceID: String?,
        consumedAt: Date?
    ) throws {
        guard destination != .releaseProcessing else {
            throw LiveActivityCoinModelError.invalidPendingAppRoute
        }
        try self.init(
            routeID: routeID,
            destination: destination,
            commandID: nil,
            createdAt: createdAt,
            occurrenceID: occurrenceID,
            state: .pending,
            claimedAt: nil,
            terminalOutcome: nil,
            retryAfter: nil,
            presentedAt: nil,
            acknowledgedAt: nil,
            consumedAt: consumedAt
        )
    }

    static func releaseProcessing(
        routeID: UUID,
        commandID: UUID,
        createdAt: Date,
        occurrenceID: String
    ) throws -> PendingAppRoute {
        try PendingAppRoute(
            routeID: routeID,
            destination: .releaseProcessing,
            commandID: commandID,
            createdAt: createdAt,
            occurrenceID: occurrenceID,
            state: .pending,
            claimedAt: nil,
            terminalOutcome: nil,
            retryAfter: nil,
            presentedAt: nil,
            acknowledgedAt: nil,
            consumedAt: nil
        )
    }

    func claiming(at date: Date) throws -> PendingAppRoute {
        guard destination == .releaseProcessing,
              state == .pending,
              consumedAt == nil,
              date >= createdAt else {
            throw LiveActivityCoinModelError.invalidPendingAppRoute
        }
        return try replacing(
            state: .processing,
            claimedAt: date,
            terminalOutcome: nil,
            retryAfter: nil,
            presentedAt: nil,
            acknowledgedAt: nil
        )
    }

    func recordingTerminal(
        outcome: PendingAppRouteTerminalOutcome,
        retryAfter: Date?,
        at date: Date
    ) throws -> PendingAppRoute {
        guard destination == .releaseProcessing,
              state == .processing,
              let claimedAt,
              date >= claimedAt,
              outcome == .retryable || retryAfter == nil,
              retryAfter.map({ $0 >= date }) ?? true else {
            throw LiveActivityCoinModelError.invalidPendingAppRoute
        }
        return try replacing(
            state: .terminal,
            claimedAt: claimedAt,
            terminalOutcome: outcome,
            retryAfter: retryAfter,
            presentedAt: nil,
            acknowledgedAt: nil
        )
    }

    func markingPresented(at date: Date) throws -> PendingAppRoute {
        guard state == .terminal,
              let claimedAt,
              date >= claimedAt,
              presentedAt == nil else {
            throw LiveActivityCoinModelError.invalidPendingAppRoute
        }
        return try replacing(
            state: state,
            claimedAt: claimedAt,
            terminalOutcome: terminalOutcome,
            retryAfter: retryAfter,
            presentedAt: date,
            acknowledgedAt: nil
        )
    }

    func acknowledging(at date: Date) throws -> PendingAppRoute {
        guard state == .terminal,
              let claimedAt,
              date >= (presentedAt ?? claimedAt),
              acknowledgedAt == nil else {
            throw LiveActivityCoinModelError.invalidPendingAppRoute
        }
        return try replacing(
            state: state,
            claimedAt: claimedAt,
            terminalOutcome: terminalOutcome,
            retryAfter: retryAfter,
            presentedAt: presentedAt,
            acknowledgedAt: date
        )
    }

    func retrying(at date: Date) throws -> PendingAppRoute {
        guard destination == .releaseProcessing,
              state == .terminal,
              terminalOutcome == .retryable,
              date >= (retryAfter ?? claimedAt ?? createdAt) else {
            throw LiveActivityCoinModelError.invalidPendingAppRoute
        }
        return try replacing(
            state: .processing,
            claimedAt: date,
            terminalOutcome: nil,
            retryAfter: nil,
            presentedAt: nil,
            acknowledgedAt: nil
        )
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let destination = try container.decode(
            PendingAppRouteDestination.self,
            forKey: .destination
        )
        let commandID = try container.decodeIfPresent(UUID.self, forKey: .commandID)
        let consumedAt = try container.decodeIfPresent(Date.self, forKey: .consumedAt)
        let decodedState = try container.decodeIfPresent(
            PendingAppRouteState.self,
            forKey: .state
        )
        let state: PendingAppRouteState
        let claimedAt: Date?
        if let decodedState {
            state = decodedState
            claimedAt = try container.decodeIfPresent(Date.self, forKey: .claimedAt)
        } else if consumedAt != nil,
                  destination == .releaseProcessing,
                  commandID != nil {
            state = .processing
            claimedAt = consumedAt
        } else {
            state = .pending
            claimedAt = nil
        }

        try self.init(
            routeID: container.decode(UUID.self, forKey: .routeID),
            destination: destination,
            commandID: commandID,
            createdAt: container.decode(Date.self, forKey: .createdAt),
            occurrenceID: container.decodeIfPresent(String.self, forKey: .occurrenceID),
            state: state,
            claimedAt: claimedAt,
            terminalOutcome: container.decodeIfPresent(
                PendingAppRouteTerminalOutcome.self,
                forKey: .terminalOutcome
            ),
            retryAfter: container.decodeIfPresent(Date.self, forKey: .retryAfter),
            presentedAt: container.decodeIfPresent(Date.self, forKey: .presentedAt),
            acknowledgedAt: container.decodeIfPresent(Date.self, forKey: .acknowledgedAt),
            consumedAt: consumedAt
        )
    }

    private init(
        routeID: UUID,
        destination: PendingAppRouteDestination,
        commandID: UUID?,
        createdAt: Date,
        occurrenceID: String?,
        state: PendingAppRouteState,
        claimedAt: Date?,
        terminalOutcome: PendingAppRouteTerminalOutcome?,
        retryAfter: Date?,
        presentedAt: Date?,
        acknowledgedAt: Date?,
        consumedAt: Date?
    ) throws {
        guard createdAt.timeIntervalSince1970.isFinite,
              occurrenceID?.isEmpty != true,
              consumedAt.map({ $0.timeIntervalSince1970.isFinite && $0 >= createdAt }) ?? true,
              claimedAt.map({ $0.timeIntervalSince1970.isFinite && $0 >= createdAt }) ?? true,
              retryAfter?.timeIntervalSince1970.isFinite != false,
              presentedAt?.timeIntervalSince1970.isFinite != false,
              acknowledgedAt?.timeIntervalSince1970.isFinite != false else {
            throw LiveActivityCoinModelError.invalidPendingAppRoute
        }
        if destination == .releaseProcessing {
            guard commandID != nil, occurrenceID != nil else {
                throw LiveActivityCoinModelError.invalidPendingAppRoute
            }
        }

        switch state {
        case .pending:
            guard claimedAt == nil,
                  terminalOutcome == nil,
                  retryAfter == nil,
                  presentedAt == nil,
                  acknowledgedAt == nil else {
                throw LiveActivityCoinModelError.invalidPendingAppRoute
            }
        case .processing:
            guard destination == .releaseProcessing,
                  commandID != nil,
                  claimedAt != nil,
                  terminalOutcome == nil,
                  retryAfter == nil,
                  presentedAt == nil,
                  acknowledgedAt == nil else {
                throw LiveActivityCoinModelError.invalidPendingAppRoute
            }
        case .terminal:
            guard destination == .releaseProcessing,
                  commandID != nil,
                  let claimedAt,
                  terminalOutcome != nil,
                  terminalOutcome == .retryable || retryAfter == nil,
                  retryAfter.map({ $0 >= claimedAt }) ?? true,
                  presentedAt.map({ $0 >= claimedAt }) ?? true,
                  acknowledgedAt.map({ $0 >= (presentedAt ?? claimedAt) }) ?? true else {
                throw LiveActivityCoinModelError.invalidPendingAppRoute
            }
        }

        self.routeID = routeID
        self.destination = destination
        self.commandID = commandID
        self.createdAt = createdAt
        self.occurrenceID = occurrenceID
        self.state = state
        self.claimedAt = claimedAt
        self.terminalOutcome = terminalOutcome
        self.retryAfter = retryAfter
        self.presentedAt = presentedAt
        self.acknowledgedAt = acknowledgedAt
        self.consumedAt = consumedAt
    }

    private func replacing(
        state: PendingAppRouteState,
        claimedAt: Date?,
        terminalOutcome: PendingAppRouteTerminalOutcome?,
        retryAfter: Date?,
        presentedAt: Date?,
        acknowledgedAt: Date?
    ) throws -> PendingAppRoute {
        try PendingAppRoute(
            routeID: routeID,
            destination: destination,
            commandID: commandID,
            createdAt: createdAt,
            occurrenceID: occurrenceID,
            state: state,
            claimedAt: claimedAt,
            terminalOutcome: terminalOutcome,
            retryAfter: retryAfter,
            presentedAt: presentedAt,
            acknowledgedAt: acknowledgedAt,
            consumedAt: consumedAt
        )
    }
}
