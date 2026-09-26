import Foundation

struct ReservationMigrationAuthorization: Equatable, Sendable {
    let epochID: UUID
    let legacyWritersRetiredAt: Date
    let evidenceVersion: Int

    init(epochID: UUID, legacyWritersRetiredAt: Date, evidenceVersion: Int) {
        self.epochID = epochID
        self.legacyWritersRetiredAt = legacyWritersRetiredAt
        self.evidenceVersion = evidenceVersion
    }
}

enum ReservationCompatibilityMigrationResult: Equatable, Sendable {
    case completed(epochID: UUID)
}

enum ReservationCompatibilityMigrationError: Error, Equatable, Sendable {
    case authorizationRequired
    case invalidRemoteRecords
    case epochMismatch
    case unresolvedCommand(commandID: UUID)
    case database(CoinLedgerDatabaseError)
}

/// Migrates one existing epoch to the occurrence-claim protocol without deleting or resetting it.
/// The caller must supply freshly synchronized whole-zone records on every invocation.
actor ReservationCompatibilityMigrationProvider {
    typealias RemoteRecordFetcher = @Sendable () async throws -> [CloudKitRecordSnapshot]
    typealias WallClockNow = @Sendable () -> Date

    private let database: any CoinLedgerCloudDatabase
    private let fetchRemoteRecords: RemoteRecordFetcher
    private let now: WallClockNow
    private let mapper = CoinLedgerRecordMapper()

    init(
        database: any CoinLedgerCloudDatabase,
        fetchRemoteRecords: @escaping RemoteRecordFetcher,
        now: @escaping WallClockNow = Date.init
    ) {
        self.database = database
        self.fetchRemoteRecords = fetchRemoteRecords
        self.now = now
    }

    func verifyReservationCompatibility(epochID: UUID) async throws -> Bool {
        let records: [CloudKitRecordSnapshot]
        do {
            records = try await fetchRemoteRecords()
        } catch let error as CoinLedgerDatabaseError {
            throw ReservationCompatibilityMigrationError.database(error)
        } catch {
            throw ReservationCompatibilityMigrationError.database(.serverUnavailable)
        }

        guard let context = try? context(from: records, epochID: epochID),
              context.marker?.state == .ready else {
            return false
        }
        return commandsAreCompatible(context)
    }

    func migrate(
        epochID: UUID,
        authorization: ReservationMigrationAuthorization?
    ) async throws -> ReservationCompatibilityMigrationResult {
        guard let authorization,
              authorization.epochID == epochID,
              authorization.evidenceVersion > 0,
              authorization.legacyWritersRetiredAt.timeIntervalSince1970.isFinite,
              now() >= authorization.legacyWritersRetiredAt else {
            throw ReservationCompatibilityMigrationError.authorizationRequired
        }

        var migrationContext = try await freshContext(epochID: epochID)
        if migrationContext.marker?.state == .ready,
           commandsAreCompatible(migrationContext) {
            return .completed(epochID: epochID)
        }

        try validateMigratableCommands(migrationContext)
        try await writeMarker(
            state: .preparing,
            authorization: authorization,
            epochID: epochID
        )

        migrationContext = try await freshContext(epochID: epochID)
        for command in migrationContext.commands.sorted(by: commandOrder) {
            guard migrationContext.stamps[command.commandID] == nil else { continue }
            try await migrate(
                command: command,
                epochID: epochID,
                context: migrationContext
            )
            migrationContext = try await freshContext(epochID: epochID)
            try validateMigratableCommands(migrationContext)
        }

        guard commandsAreCompatible(migrationContext) else {
            throw ReservationCompatibilityMigrationError.invalidRemoteRecords
        }
        try await writeMarker(
            state: .ready,
            authorization: authorization,
            epochID: epochID
        )
        guard try await verifyReservationCompatibility(epochID: epochID) else {
            throw ReservationCompatibilityMigrationError.invalidRemoteRecords
        }
        return .completed(epochID: epochID)
    }
}

private extension ReservationCompatibilityMigrationProvider {
    struct Context {
        let epoch: LedgerEpoch
        let commands: [ReleaseCommand]
        let commandRecords: [UUID: CloudKitRecordSnapshot]
        let claims: [String: ReleaseOccurrenceClaim]
        let stamps: [UUID: ReservationCompatibilityStamp]
        let marker: ReservationMigrationMarker?
    }

    func freshContext(epochID: UUID) async throws -> Context {
        let records: [CloudKitRecordSnapshot]
        do {
            records = try await fetchRemoteRecords()
        } catch let error as CoinLedgerDatabaseError {
            throw ReservationCompatibilityMigrationError.database(error)
        } catch {
            throw ReservationCompatibilityMigrationError.database(.serverUnavailable)
        }
        do {
            return try context(from: records, epochID: epochID)
        } catch let error as ReservationCompatibilityMigrationError {
            throw error
        } catch {
            throw ReservationCompatibilityMigrationError.invalidRemoteRecords
        }
    }

    func context(
        from records: [CloudKitRecordSnapshot],
        epochID: UUID
    ) throws -> Context {
        guard Set(records.map(\.recordName)).count == records.count,
              let epochRecord = records.first(where: {
                  $0.recordName == CoinLedgerRecordID.ledgerEpoch
              }),
              case .ledgerEpoch(let epoch) = try mapper.entity(from: epochRecord),
              epoch.epochID == epochID else {
            throw ReservationCompatibilityMigrationError.epochMismatch
        }

        var commands: [ReleaseCommand] = []
        var commandRecords: [UUID: CloudKitRecordSnapshot] = [:]
        var claims: [String: ReleaseOccurrenceClaim] = [:]
        var stamps: [UUID: ReservationCompatibilityStamp] = [:]
        var marker: ReservationMigrationMarker?

        do {
            for record in records {
                switch try mapper.entity(from: record) {
                case .releaseCommand(let command):
                    guard commandRecords[command.commandID] == nil else {
                        throw ReservationCompatibilityMigrationError.invalidRemoteRecords
                    }
                    commands.append(command)
                    commandRecords[command.commandID] = record
                case .releaseOccurrenceClaim(let claim):
                    guard claim.ledgerEpochID == epochID,
                          claims[claim.occurrenceID] == nil else {
                        throw ReservationCompatibilityMigrationError.invalidRemoteRecords
                    }
                    claims[claim.occurrenceID] = claim
                case .reservationCompatibilityStamp(let stamp):
                    guard stamp.ledgerEpochID == epochID,
                          stamps[stamp.commandID] == nil else {
                        throw ReservationCompatibilityMigrationError.invalidRemoteRecords
                    }
                    stamps[stamp.commandID] = stamp
                case .reservationMigrationMarker(let candidate):
                    guard candidate.ledgerEpochID == epochID, marker == nil else {
                        throw ReservationCompatibilityMigrationError.invalidRemoteRecords
                    }
                    marker = candidate
                case .ledgerEpoch, .coinAccount, .monthlyAllowance, .purchaseGrant, .event:
                    break
                }
            }
        } catch let error as ReservationCompatibilityMigrationError {
            throw error
        } catch {
            throw ReservationCompatibilityMigrationError.invalidRemoteRecords
        }

        return Context(
            epoch: epoch,
            commands: commands,
            commandRecords: commandRecords,
            claims: claims,
            stamps: stamps,
            marker: marker
        )
    }

    func validateMigratableCommands(_ context: Context) throws {
        let committedGroups = Dictionary(grouping: context.commands.filter {
            $0.state == .committed
        }, by: \.occurrenceID)
        if let conflict = committedGroups.values.first(where: { $0.count > 1 })?.first {
            throw ReservationCompatibilityMigrationError.unresolvedCommand(
                commandID: conflict.commandID
            )
        }

        for command in context.commands where context.stamps[command.commandID] == nil {
            let claim = context.claims[command.occurrenceID]
            switch command.state {
            case .rejected, .compensated:
                continue
            case .committed:
                if let claim,
                   claim.commandID != command.commandID || claim.state != .held {
                    throw ReservationCompatibilityMigrationError.unresolvedCommand(
                        commandID: command.commandID
                    )
                }
            case .reserved, .applied, .compensating, .reconciliationRequired:
                guard claim?.commandID == command.commandID, claim?.state == .held else {
                    throw ReservationCompatibilityMigrationError.unresolvedCommand(
                        commandID: command.commandID
                    )
                }
            case .requested:
                throw ReservationCompatibilityMigrationError.unresolvedCommand(
                    commandID: command.commandID
                )
            }
        }
    }

    func commandsAreCompatible(_ context: Context) -> Bool {
        for command in context.commands {
            guard let stamp = context.stamps[command.commandID],
                  stamp.ledgerEpochID == context.epoch.epochID,
                  stamp.occurrenceID == command.occurrenceID,
                  stamp.protocolVersion == ReservationCompatibilityStamp.currentProtocolVersion
            else { return false }

            switch command.state {
            case .reserved, .applied, .committed, .compensating, .reconciliationRequired:
                guard let claim = context.claims[command.occurrenceID],
                      claim.commandID == command.commandID,
                      claim.state == .held else { return false }
            case .requested:
                return false
            case .rejected, .compensated:
                break
            }
        }
        return true
    }

    func migrate(
        command: ReleaseCommand,
        epochID: UUID,
        context: Context
    ) async throws {
        guard let commandRecord = context.commandRecords[command.commandID] else {
            throw ReservationCompatibilityMigrationError.invalidRemoteRecords
        }
        let stampName = CoinLedgerRecordID.reservationCompatibilityStamp(
            commandID: command.commandID
        )
        let claimName = CoinLedgerRecordID.releaseOccurrenceClaim(
            ledgerEpochID: epochID,
            occurrenceID: command.occurrenceID
        )
        let names = [CoinLedgerRecordID.ledgerEpoch, commandRecord.recordName, stampName, claimName]
        let current = try await fetch(names)
        guard let epochRecord = current[CoinLedgerRecordID.ledgerEpoch],
              let currentCommandRecord = current[commandRecord.recordName],
              case .ledgerEpoch(let epoch) = try mapper.entity(from: epochRecord),
              epoch.epochID == epochID,
              case .releaseCommand(let currentCommand) = try mapper.entity(from: currentCommandRecord),
              currentCommand == command else {
            throw ReservationCompatibilityMigrationError.epochMismatch
        }
        if let existingStamp = current[stampName] {
            guard case .reservationCompatibilityStamp(let stamp) = try mapper.entity(
                from: existingStamp
            ), stamp.ledgerEpochID == epochID,
                stamp.commandID == command.commandID,
                stamp.occurrenceID == command.occurrenceID else {
                throw ReservationCompatibilityMigrationError.invalidRemoteRecords
            }
            return
        }

        let stamp = try ReservationCompatibilityStamp(
            ledgerEpochID: epochID,
            commandID: command.commandID,
            occurrenceID: command.occurrenceID,
            createdAt: now()
        )
        var saves = [
            epochRecord,
            currentCommandRecord,
            try mapper.record(for: .reservationCompatibilityStamp(stamp)),
        ]
        let currentClaimRecord = current[claimName]
        let currentClaim: ReleaseOccurrenceClaim? = try currentClaimRecord.map { record in
            guard case .releaseOccurrenceClaim(let claim) = try mapper.entity(from: record) else {
                throw ReservationCompatibilityMigrationError.invalidRemoteRecords
            }
            return claim
        }
        switch command.state {
        case .committed where currentClaim == nil:
            let claim = try ReleaseOccurrenceClaim(
                ledgerEpochID: epochID,
                occurrenceID: command.occurrenceID,
                commandID: command.commandID,
                state: .held,
                updatedAt: now()
            )
            saves.append(try mapper.record(for: .releaseOccurrenceClaim(claim)))
        case .reserved, .applied, .committed, .compensating, .reconciliationRequired:
            guard let currentClaim, let currentClaimRecord,
                  currentClaim.ledgerEpochID == epochID,
                  currentClaim.occurrenceID == command.occurrenceID,
                  currentClaim.commandID == command.commandID,
                  currentClaim.state == .held else {
                throw ReservationCompatibilityMigrationError.unresolvedCommand(
                    commandID: command.commandID
                )
            }
            saves.append(currentClaimRecord)
        case .requested:
            throw ReservationCompatibilityMigrationError.unresolvedCommand(
                commandID: command.commandID
            )
        case .rejected, .compensated:
            break
        }
        try await modify(saves)
    }

    func writeMarker(
        state: ReservationMigrationMarker.State,
        authorization: ReservationMigrationAuthorization,
        epochID: UUID
    ) async throws {
        let markerName = CoinLedgerRecordID.reservationMigrationMarker(epochID: epochID)
        let current = try await fetch([CoinLedgerRecordID.ledgerEpoch, markerName])
        guard let epochRecord = current[CoinLedgerRecordID.ledgerEpoch],
              case .ledgerEpoch(let epoch) = try mapper.entity(from: epochRecord),
              epoch.epochID == epochID else {
            throw ReservationCompatibilityMigrationError.epochMismatch
        }
        let marker = try ReservationMigrationMarker(
            ledgerEpochID: epochID,
            state: state,
            legacyWritersRetiredAt: authorization.legacyWritersRetiredAt,
            evidenceVersion: authorization.evidenceVersion,
            updatedAt: now()
        )
        var markerRecord = try mapper.record(for: .reservationMigrationMarker(marker))
        markerRecord = CloudKitRecordSnapshot(
            recordType: markerRecord.recordType,
            recordName: markerRecord.recordName,
            changeTag: current[markerName]?.changeTag,
            fields: markerRecord.fields
        )
        try await modify([epochRecord, markerRecord])
    }

    func fetch(_ recordNames: [String]) async throws -> [String: CloudKitRecordSnapshot] {
        do {
            let records = try await database.fetch(CoinLedgerFetchRequest(recordNames: recordNames))
            guard Set(records.map(\.recordName)).count == records.count else {
                throw ReservationCompatibilityMigrationError.invalidRemoteRecords
            }
            return Dictionary(uniqueKeysWithValues: records.map { ($0.recordName, $0) })
        } catch let error as ReservationCompatibilityMigrationError {
            throw error
        } catch let error as CoinLedgerDatabaseError {
            throw ReservationCompatibilityMigrationError.database(error)
        } catch {
            throw ReservationCompatibilityMigrationError.database(.serverUnavailable)
        }
    }

    func modify(_ records: [CloudKitRecordSnapshot]) async throws {
        do {
            _ = try await database.modify(CoinLedgerModifyRequest(recordsToSave: records))
        } catch let error as CoinLedgerDatabaseError {
            throw ReservationCompatibilityMigrationError.database(error)
        } catch {
            throw ReservationCompatibilityMigrationError.database(.serverUnavailable)
        }
    }

    func commandOrder(_ lhs: ReleaseCommand, _ rhs: ReleaseCommand) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.commandID.uuidString < rhs.commandID.uuidString
    }
}
