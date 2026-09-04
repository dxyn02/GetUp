import Foundation

struct CloudKitCoinLedgerRepository: CoinLedgerRepository, Sendable {
    private let database: any CoinLedgerCloudDatabase
    private let mapper: CoinLedgerRecordMapper
    private let conflictRetryLimit: Int
    // Permission to use the claim protocol for this epoch, not the ledger freshness gate.
    // Only a verified migration/new-ledger boundary may supply true; production defaults closed.
    private let verifyReservationCompatibility: @Sendable (UUID) async throws -> Bool

    init(
        database: any CoinLedgerCloudDatabase,
        mapper: CoinLedgerRecordMapper = CoinLedgerRecordMapper(),
        conflictRetryLimit: Int = 2,
        verifyReservationCompatibility: @escaping @Sendable (UUID) async throws -> Bool = { _ in false }
    ) {
        self.database = database
        self.mapper = mapper
        self.conflictRetryLimit = max(0, conflictRetryLimit)
        self.verifyReservationCompatibility = verifyReservationCompatibility
    }

    func createAllowanceIfNeeded(
        _ request: MonthlyAllowanceCreationRequest
    ) async throws -> MonthlyAllowance {
        let allowanceName = CoinLedgerRecordID.allowance(monthID: request.monthID)
        let grantName = CoinLedgerDeterministicID.freeGrant(monthID: request.monthID)

        for attempt in 0...conflictRetryLimit {
            let records = try await fetch(recordNames: [allowanceName, grantName])
            let indexed = try index(records)
            if let existing = indexed[allowanceName] {
                return try monthlyAllowance(from: existing)
            }
            guard indexed[grantName] == nil else {
                throw CoinLedgerRepositoryError.database(.invalidRecord)
            }

            let createdAt = Date()
            let allowance = try MonthlyAllowance(
                monthID: request.monthID,
                quota: 2,
                used: 0,
                reserved: 0,
                creationDate: createdAt,
                updatedAt: createdAt
            )
            let freeGrant = try freeGrantEvent(
                monthID: request.monthID,
                createdAt: allowance.creationDate
            )
            let modify = try modifyRequest(for: [
                (.monthlyAllowance(allowance), nil),
                (.event(freeGrant), nil),
            ])

            do {
                _ = try await database.modify(modify)
                return allowance
            } catch CoinLedgerDatabaseError.serverRecordChanged
                where attempt < conflictRetryLimit {
                continue
            } catch CoinLedgerDatabaseError.resultUnknown {
                let resolved = try await fetch(recordNames: [allowanceName])
                guard let record = try index(resolved)[allowanceName] else {
                    throw CoinLedgerRepositoryError.database(.resultUnknown)
                }
                return try monthlyAllowance(from: record)
            } catch {
                throw map(error)
            }
        }

        throw CoinLedgerRepositoryError.database(.serverRecordChanged)
    }

    func reserveMonthlyFree(
        _ request: MonthlyFreeReservationRequest
    ) async throws -> CoinReleaseReservation {
        try await reserve(request, allowsPurchasedFallback: false)
    }

    func reservePurchasedCoin(
        _ request: PurchasedCoinReservationRequest
    ) async throws -> CoinReleaseReservation {
        // Reevaluate free funds even when the caller previously saw them exhausted.
        try await reserve(MonthlyFreeReservationRequest(
            commandID: request.commandID, occurrenceID: request.occurrenceID,
            ruleID: request.ruleID, ruleRevision: request.ruleRevision,
            monthID: MonthlyAllowancePolicy.monthID(containing: request.requestedAt),
            ledgerEpochID: request.ledgerEpochID, requestedFrom: request.requestedFrom,
            requestedAt: request.requestedAt
        ), allowsPurchasedFallback: true)
    }

    private func reserve(
        _ request: MonthlyFreeReservationRequest,
        allowsPurchasedFallback: Bool
    ) async throws -> CoinReleaseReservation {
        guard request.requestedAt.timeIntervalSince1970.isFinite,
              request.monthID == MonthlyAllowancePolicy.monthID(containing: request.requestedAt),
              !request.occurrenceID.isEmpty else {
            throw CoinLedgerRepositoryError.database(.invalidRecord)
        }
        let allowanceName = CoinLedgerRecordID.allowance(monthID: request.monthID)
        let grantName = CoinLedgerDeterministicID.freeGrant(monthID: request.monthID)
        let commandName = CoinLedgerRecordID.releaseCommand(commandID: request.commandID)
        let reservationName = CoinLedgerDeterministicID.reservation(commandID: request.commandID)
        let claimName = CoinLedgerRecordID.releaseOccurrenceClaim(
            ledgerEpochID: request.ledgerEpochID, occurrenceID: request.occurrenceID
        )
        let names = [CoinLedgerRecordID.ledgerEpoch, CoinLedgerRecordID.coinAccount,
                     allowanceName, grantName, commandName, reservationName, claimName]

        for attempt in 0...conflictRetryLimit {
            // Default deny: production must not infer migration safety from a missing claim.
            guard try await verifyReservationCompatibility(request.ledgerEpochID) else {
                throw CoinLedgerRepositoryError.ledgerNotCurrent
            }
            let indexed = try index(try await fetch(recordNames: names))
            let epochRecord = try validatedEpoch(indexed, requestedEpochID: request.ledgerEpochID)
            guard case .ledgerEpoch(let epoch) = try decode(epochRecord) else {
                throw CoinLedgerRepositoryError.database(.invalidRecord)
            }
            if let replay = try reservationReplay(request, indexed: indexed) { return replay }
            if let record = indexed[claimName] {
                let claim = try occurrenceClaim(from: record)
                guard claim.state == .released else {
                    throw CoinLedgerRepositoryError.reconciliationRequired(commandID: claim.commandID)
                }
            }
            guard indexed[reservationName] == nil else {
                throw CoinLedgerRepositoryError.reconciliationRequired(commandID: request.commandID)
            }
            let existing = try indexed[allowanceName].map(monthlyAllowance(from:))
            let allowance = try existing ?? MonthlyAllowancePolicy.makeAllowance(
                monthID: request.monthID, ledgerEpoch: epoch,
                serverCreationDate: request.requestedAt
            )
            let funding: ReleaseFundingSource = allowance.available > 0 ? .monthlyFree : .purchased
            if funding == .purchased, !allowsPurchasedFallback {
                throw CoinLedgerRepositoryError.insufficientMonthlyAllowance
            }
            let claim = try ReleaseOccurrenceClaim(
                ledgerEpochID: request.ledgerEpochID, occurrenceID: request.occurrenceID,
                commandID: request.commandID, state: .held, updatedAt: request.requestedAt
            )
            let command = try ReleaseCommand.requested(
                commandID: request.commandID, occurrenceID: request.occurrenceID,
                ruleID: request.ruleID, requestedFrom: request.requestedFrom, at: request.requestedAt
            ).transitioning(to: .reserved, fundingSource: funding, at: request.requestedAt)
            let event = try reservationEvent(
                request: request, source: funding == .monthlyFree ? .monthlyFree : .purchased
            )
            var entities: [(CoinLedgerRecordEntity, String?)] = [
                (.ledgerEpoch(epoch), epochRecord.changeTag),
                (.releaseOccurrenceClaim(claim), indexed[claimName]?.changeTag),
                (.releaseCommand(command), nil), (.event(event), nil),
            ]
            let updatedAllowance: MonthlyAllowance
            var updatedAccount: CoinAccount?
            if funding == .monthlyFree {
                updatedAllowance = try reserveFreeAllowance(
                    allowance, monthID: request.monthID, at: request.requestedAt
                )
            } else {
                guard let record = indexed[CoinLedgerRecordID.coinAccount] else {
                    throw CoinLedgerRepositoryError.ledgerNotCurrent
                }
                let account = try coinAccount(from: record)
                guard account.purchasedUsable > 0 else {
                    throw CoinLedgerRepositoryError.insufficientPurchasedBalance
                }
                let updated = try CoinAccount(
                    purchasedAvailable: account.purchasedAvailable,
                    purchasedReserved: adding(account.purchasedReserved, 1),
                    revision: adding(account.revision, 1), updatedAt: request.requestedAt
                )
                updatedAccount = updated
                entities.append((.coinAccount(updated), record.changeTag))
                // CAS the exhausted bucket too: a concurrent compensation may restore free funds.
                updatedAllowance = allowance
            }
            entities.append((.monthlyAllowance(updatedAllowance), indexed[allowanceName]?.changeTag))
            if existing == nil {
                guard indexed[grantName] == nil else {
                    throw CoinLedgerRepositoryError.database(.invalidRecord)
                }
                if allowance.quota > 0 {
                    entities.append((.event(try freeGrantEvent(
                        monthID: request.monthID, createdAt: request.requestedAt
                    )), nil))
                }
            }
            do {
                _ = try await database.modify(try modifyRequest(for: entities))
                return CoinReleaseReservation(command: command,
                    allowance: updatedAllowance, account: updatedAccount)
            } catch CoinLedgerDatabaseError.serverRecordChanged where attempt < conflictRetryLimit {
                continue
            } catch CoinLedgerDatabaseError.resultUnknown {
                // Read confirmed balances, never return a proposed balance after an unknown write.
                do {
                    let confirmed = try index(try await fetch(recordNames: names))
                    _ = try validatedEpoch(confirmed, requestedEpochID: request.ledgerEpochID)
                    guard let replay = try reservationReplay(request, indexed: confirmed) else {
                        throw CoinLedgerRepositoryError.reconciliationRequired(commandID: request.commandID)
                    }
                    return replay
                } catch {
                    throw CoinLedgerRepositoryError.reconciliationRequired(commandID: request.commandID)
                }
            } catch {
                throw map(error)
            }
        }
        throw CoinLedgerRepositoryError.database(.serverRecordChanged)
    }

    func fetchReleaseCommand(commandID: UUID) async throws -> ReleaseCommand? {
        let name = CoinLedgerRecordID.releaseCommand(commandID: commandID)
        let records = try await fetch(recordNames: [name])
        guard let record = try index(records)[name] else {
            return nil
        }
        return try releaseCommand(from: record)
    }

    func markReleaseApplied(
        commandID: UUID,
        at date: Date
    ) async throws -> ReleaseCommand {
        try await updateCommand(
            commandID: commandID,
            targetState: .applied,
            at: date
        )
    }

    func commitRelease(
        commandID: UUID,
        at date: Date
    ) async throws -> ReleaseCommand {
        try await finalizeReservation(commandID: commandID, at: date, commit: true)
    }

    func compensateRelease(
        commandID: UUID,
        at date: Date
    ) async throws -> ReleaseCommand {
        try await finalizeReservation(commandID: commandID, at: date, commit: false)
    }

    func grantPurchase(_ request: PurchaseGrantRequest) async throws -> PurchaseGrant {
        guard request.transaction.revocationDate == nil, request.quantity > 0 else {
            throw CoinLedgerRepositoryError.database(.invalidRecord)
        }

        let grantName = CoinLedgerRecordID.purchaseGrant(
            environment: request.transaction.environment,
            transactionID: request.transaction.id
        )
        let eventName = CoinLedgerDeterministicID.purchase(
            environment: request.transaction.environment,
            transactionID: request.transaction.id
        )
        let accountName = CoinLedgerRecordID.coinAccount

        for attempt in 0...conflictRetryLimit {
            let records = try await fetch(recordNames: [grantName, eventName, accountName])
            let indexed = try index(records)
            if let existing = indexed[grantName] {
                let grant = try purchaseGrant(from: existing)
                guard
                    grant.transactionID == request.transaction.id,
                    grant.environment == request.transaction.environment,
                    grant.productID == request.transaction.productID,
                    grant.quantity == request.quantity
                else {
                    throw CoinLedgerRepositoryError.database(.invalidRecord)
                }
                return grant
            }
            guard indexed[eventName] == nil else {
                throw CoinLedgerRepositoryError.database(.invalidRecord)
            }
            guard let accountRecord = indexed[accountName] else {
                throw CoinLedgerRepositoryError.ledgerNotCurrent
            }

            let account = try coinAccount(from: accountRecord)
            let grant = try PurchaseGrant(
                transactionID: request.transaction.id,
                environment: request.transaction.environment,
                productID: request.transaction.productID,
                quantity: request.quantity,
                purchaseDate: request.transaction.purchaseDate,
                adjustedQuantity: 0
            )
            let updatedAccount = try CoinAccount(
                purchasedAvailable: try adding(
                    account.purchasedAvailable,
                    request.quantity
                ),
                purchasedReserved: account.purchasedReserved,
                revision: try adding(account.revision, 1),
                updatedAt: request.transaction.purchaseDate
            )
            let event = try CoinLedgerEvent(
                eventID: eventName,
                kind: .purchaseGrant,
                source: .purchased,
                quantity: request.quantity,
                relatedTransactionID: request.transaction.id,
                relatedCommandID: nil,
                occurrenceID: nil,
                createdAt: request.transaction.purchaseDate
            )

            do {
                _ = try await database.modify(try modifyRequest(for: [
                    (.coinAccount(updatedAccount), accountRecord.changeTag),
                    (.purchaseGrant(grant), nil),
                    (.event(event), nil),
                ]))
                return grant
            } catch CoinLedgerDatabaseError.serverRecordChanged
                where attempt < conflictRetryLimit {
                continue
            } catch CoinLedgerDatabaseError.resultUnknown {
                let resolved = try await fetch(recordNames: [grantName])
                guard let record = try index(resolved)[grantName] else {
                    throw CoinLedgerRepositoryError.database(.resultUnknown)
                }
                return try purchaseGrant(from: record)
            } catch {
                throw map(error)
            }
        }

        throw CoinLedgerRepositoryError.database(.serverRecordChanged)
    }
}

private extension CloudKitCoinLedgerRepository {
    func validatedEpoch(
        _ records: [String: CloudKitRecordSnapshot], requestedEpochID: UUID
    ) throws -> CloudKitRecordSnapshot {
        guard let record = records[CoinLedgerRecordID.ledgerEpoch], record.changeTag != nil,
              case .ledgerEpoch(let epoch) = try decode(record) else {
            throw CoinLedgerRepositoryError.ledgerNotCurrent
        }
        guard epoch.epochID == requestedEpochID else {
            throw CoinLedgerRepositoryError.ledgerEpochMismatch
        }
        return record
    }

    func occurrenceClaim(from record: CloudKitRecordSnapshot) throws -> ReleaseOccurrenceClaim {
        guard record.changeTag != nil, case .releaseOccurrenceClaim(let claim) = try decode(record) else {
            throw CoinLedgerRepositoryError.database(.invalidRecord)
        }
        return claim
    }

    func reservationReplay(
        _ request: MonthlyFreeReservationRequest, indexed: [String: CloudKitRecordSnapshot]
    ) throws -> CoinReleaseReservation? {
        guard let record = indexed[CoinLedgerRecordID.releaseCommand(commandID: request.commandID)]
        else { return nil }
        let command = try releaseCommand(from: record)
        try validate(command, against: request)
        let claimName = CoinLedgerRecordID.releaseOccurrenceClaim(
            ledgerEpochID: request.ledgerEpochID, occurrenceID: request.occurrenceID
        )
        guard let claimRecord = indexed[claimName] else {
            throw CoinLedgerRepositoryError.reconciliationRequired(commandID: command.commandID)
        }
        let claim = try occurrenceClaim(from: claimRecord)
        guard claim.state == .held, claim.commandID == command.commandID,
              let eventRecord = indexed[CoinLedgerDeterministicID.reservation(commandID: command.commandID)]
        else { throw CoinLedgerRepositoryError.reconciliationRequired(commandID: command.commandID) }
        let event = try ledgerEvent(from: eventRecord)
        guard event.kind == .reservation, event.quantity == 1,
              event.relatedCommandID == command.commandID, event.occurrenceID == command.occurrenceID,
              event.source.rawValue == command.fundingSource?.rawValue else {
            throw CoinLedgerRepositoryError.database(.invalidRecord)
        }
        let balanceName = event.source == .monthlyFree
            ? CoinLedgerRecordID.allowance(monthID: monthID(for: event.createdAt))
            : CoinLedgerRecordID.coinAccount
        guard indexed[balanceName] != nil else {
            throw CoinLedgerRepositoryError.reconciliationRequired(commandID: command.commandID)
        }
        return try existingReservation(command: command,
            allowanceRecord: indexed[CoinLedgerRecordID.allowance(monthID: request.monthID)],
            accountRecord: indexed[CoinLedgerRecordID.coinAccount])
    }

    /// Used for application/finalization as well as reservation so a stale owner cannot mutate a new claim.
    func ownershipFence(for command: ReleaseCommand) async throws
        -> (epoch: CloudKitRecordSnapshot, claimRecord: CloudKitRecordSnapshot, claim: ReleaseOccurrenceClaim) {
        let records = try index(try await fetch(recordNames: [CoinLedgerRecordID.ledgerEpoch]))
        guard let record = records[CoinLedgerRecordID.ledgerEpoch],
              case .ledgerEpoch(let epoch) = try decode(record) else {
            throw CoinLedgerRepositoryError.ledgerNotCurrent
        }
        _ = try validatedEpoch(records, requestedEpochID: epoch.epochID)
        let name = CoinLedgerRecordID.releaseOccurrenceClaim(
            ledgerEpochID: epoch.epochID, occurrenceID: command.occurrenceID
        )
        let claims = try index(try await fetch(recordNames: [name]))
        guard let claimRecord = claims[name] else {
            throw CoinLedgerRepositoryError.reconciliationRequired(commandID: command.commandID)
        }
        let claim = try occurrenceClaim(from: claimRecord)
        guard claim.state == .held, claim.commandID == command.commandID else {
            throw CoinLedgerRepositoryError.reconciliationRequired(commandID: claim.commandID)
        }
        return (record, claimRecord, claim)
    }

    func fetch(recordNames: [String]) async throws -> [CloudKitRecordSnapshot] {
        do {
            return try await database.fetch(CoinLedgerFetchRequest(recordNames: recordNames))
        } catch {
            throw map(error)
        }
    }

    func index(
        _ records: [CloudKitRecordSnapshot]
    ) throws -> [String: CloudKitRecordSnapshot] {
        var result: [String: CloudKitRecordSnapshot] = [:]
        for record in records {
            guard result.updateValue(record, forKey: record.recordName) == nil else {
                throw CoinLedgerRepositoryError.database(.invalidRecord)
            }
        }
        return result
    }

    func modifyRequest(
        for entities: [(CoinLedgerRecordEntity, String?)]
    ) throws -> CoinLedgerModifyRequest {
        CoinLedgerModifyRequest(
            recordsToSave: try entities.map { entity, changeTag in
                let mapped = try mapper.record(for: entity)
                return CloudKitRecordSnapshot(
                    recordType: mapped.recordType,
                    recordName: mapped.recordName,
                    changeTag: changeTag,
                    fields: mapped.fields
                )
            },
            isAtomic: true,
            savePolicy: .ifServerRecordUnchanged
        )
    }

    func monthlyAllowance(
        from record: CloudKitRecordSnapshot
    ) throws -> MonthlyAllowance {
        guard case let .monthlyAllowance(value) = try decode(record) else {
            throw CoinLedgerRepositoryError.database(.invalidRecord)
        }
        return value
    }

    func coinAccount(from record: CloudKitRecordSnapshot) throws -> CoinAccount {
        guard case let .coinAccount(value) = try decode(record) else {
            throw CoinLedgerRepositoryError.database(.invalidRecord)
        }
        return value
    }

    func purchaseGrant(from record: CloudKitRecordSnapshot) throws -> PurchaseGrant {
        guard case let .purchaseGrant(value) = try decode(record) else {
            throw CoinLedgerRepositoryError.database(.invalidRecord)
        }
        return value
    }

    func ledgerEvent(from record: CloudKitRecordSnapshot) throws -> CoinLedgerEvent {
        guard case let .event(value) = try decode(record) else {
            throw CoinLedgerRepositoryError.database(.invalidRecord)
        }
        return value
    }

    func releaseCommand(from record: CloudKitRecordSnapshot) throws -> ReleaseCommand {
        guard case let .releaseCommand(value) = try decode(record) else {
            throw CoinLedgerRepositoryError.database(.invalidRecord)
        }
        return value
    }

    func decode(_ record: CloudKitRecordSnapshot) throws -> CoinLedgerRecordEntity {
        do {
            return try mapper.entity(from: record)
        } catch let error as CoinLedgerRecordMapperError {
            switch error {
            case .unsupportedSchema:
                throw CoinLedgerRepositoryError.database(.unsupportedSchema)
            default:
                throw CoinLedgerRepositoryError.database(.invalidRecord)
            }
        } catch {
            throw CoinLedgerRepositoryError.database(.invalidRecord)
        }
    }

    func reserveFreeAllowance(
        _ existing: MonthlyAllowance?,
        monthID: String,
        at date: Date
    ) throws -> MonthlyAllowance {
        if let existing {
            guard existing.available > 0 else {
                throw CoinLedgerRepositoryError.insufficientMonthlyAllowance
            }
            return try MonthlyAllowance(
                monthID: existing.monthID,
                quota: existing.quota,
                used: existing.used,
                reserved: try adding(existing.reserved, 1),
                creationDate: existing.creationDate,
                updatedAt: date
            )
        }

        return try MonthlyAllowance(
            monthID: monthID,
            quota: 2,
            used: 0,
            reserved: 1,
            creationDate: date,
            updatedAt: date
        )
    }

    func freeGrantEvent(monthID: String, createdAt: Date) throws -> CoinLedgerEvent {
        try CoinLedgerEvent(
            eventID: CoinLedgerDeterministicID.freeGrant(monthID: monthID),
            kind: .freeGrant,
            source: .monthlyFree,
            quantity: 2,
            relatedTransactionID: nil,
            relatedCommandID: nil,
            occurrenceID: nil,
            createdAt: createdAt
        )
    }

    func reservationEvent(
        request: MonthlyFreeReservationRequest,
        source: CoinLedgerEventSource
    ) throws -> CoinLedgerEvent {
        try reservationEvent(
            commandID: request.commandID,
            occurrenceID: request.occurrenceID,
            source: source,
            createdAt: request.requestedAt
        )
    }

    func reservationEvent(
        commandID: UUID,
        occurrenceID: String,
        source: CoinLedgerEventSource,
        createdAt: Date
    ) throws -> CoinLedgerEvent {
        try CoinLedgerEvent(
            eventID: CoinLedgerDeterministicID.reservation(commandID: commandID),
            kind: .reservation,
            source: source,
            quantity: 1,
            relatedTransactionID: nil,
            relatedCommandID: commandID,
            occurrenceID: occurrenceID,
            createdAt: createdAt
        )
    }

    func validate(
        _ command: ReleaseCommand,
        against request: MonthlyFreeReservationRequest
    ) throws {
        guard
            command.commandID == request.commandID,
            command.occurrenceID == request.occurrenceID,
            command.ruleID == request.ruleID
        else {
            throw CoinLedgerRepositoryError.database(.invalidRecord)
        }
    }

    func existingReservation(
        command: ReleaseCommand,
        allowanceRecord: CloudKitRecordSnapshot?,
        accountRecord: CloudKitRecordSnapshot?
    ) throws -> CoinReleaseReservation {
        switch command.state {
        case .reserved, .applied, .committed:
            return CoinReleaseReservation(
                command: command,
                allowance: try allowanceRecord.map(monthlyAllowance(from:)),
                account: try accountRecord.map(coinAccount(from:))
            )
        case .reconciliationRequired:
            throw CoinLedgerRepositoryError.reconciliationRequired(
                commandID: command.commandID
            )
        default:
            throw CoinLedgerRepositoryError.database(.invalidRecord)
        }
    }

    func updateCommand(
        commandID: UUID,
        targetState: ReleaseCommandState,
        at date: Date
    ) async throws -> ReleaseCommand {
        let name = CoinLedgerRecordID.releaseCommand(commandID: commandID)
        for attempt in 0...conflictRetryLimit {
            let records = try await fetch(recordNames: [name])
            guard let record = try index(records)[name] else {
                throw CoinLedgerRepositoryError.ledgerNotCurrent
            }
            let command = try releaseCommand(from: record)
            if command.state == targetState || command.state == .committed {
                return command
            }
            let updated: ReleaseCommand
            do {
                updated = try command.transitioning(to: targetState, at: date)
            } catch {
                throw CoinLedgerRepositoryError.database(.invalidRecord)
            }

            let fence = try await ownershipFence(for: command)
            var modification = try modifyRequest(for: [
                (.releaseCommand(updated), record.changeTag),
            ]).recordsToSave
            modification.append(contentsOf: [fence.epoch, fence.claimRecord])
            do {
                _ = try await database.modify(CoinLedgerModifyRequest(recordsToSave: modification))
                return updated
            } catch CoinLedgerDatabaseError.serverRecordChanged
                where attempt < conflictRetryLimit {
                continue
            } catch CoinLedgerDatabaseError.resultUnknown {
                guard let resolved = try await fetchReleaseCommand(commandID: commandID) else {
                    throw CoinLedgerRepositoryError.reconciliationRequired(
                        commandID: commandID
                    )
                }
                guard resolved.state == targetState || resolved.state == .committed else {
                    throw CoinLedgerRepositoryError.reconciliationRequired(
                        commandID: commandID
                    )
                }
                return resolved
            } catch {
                throw map(error)
            }
        }
        throw CoinLedgerRepositoryError.database(.serverRecordChanged)
    }

    func finalizeReservation(
        commandID: UUID,
        at date: Date,
        commit: Bool
    ) async throws -> ReleaseCommand {
        let commandName = CoinLedgerRecordID.releaseCommand(commandID: commandID)
        let reservationName = CoinLedgerDeterministicID.reservation(commandID: commandID)

        for attempt in 0...conflictRetryLimit {
            let contextRecords = try await fetch(recordNames: [commandName, reservationName])
            let context = try index(contextRecords)
            guard
                let commandRecord = context[commandName],
                let reservationRecord = context[reservationName]
            else {
                throw CoinLedgerRepositoryError.ledgerNotCurrent
            }
            let command = try releaseCommand(from: commandRecord)
            if commit, command.state == .committed { return command }
            if !commit, command.state == .compensated { return command }

            let fence = try await ownershipFence(for: command)

            let reservation = try ledgerEvent(from: reservationRecord)
            guard
                reservation.kind == .reservation,
                reservation.relatedCommandID == commandID,
                reservation.occurrenceID == command.occurrenceID,
                reservation.source.rawValue == command.fundingSource?.rawValue,
                reservation.quantity == 1
            else {
                throw CoinLedgerRepositoryError.database(.invalidRecord)
            }

            let balanceName: String
            switch reservation.source {
            case .monthlyFree:
                balanceName = CoinLedgerRecordID.allowance(
                    monthID: monthID(for: reservation.createdAt)
                )
            case .purchased:
                balanceName = CoinLedgerRecordID.coinAccount
            case .none:
                throw CoinLedgerRepositoryError.database(.invalidRecord)
            }
            let balanceRecords = try await fetch(recordNames: [balanceName])
            guard let balanceRecord = try index(balanceRecords)[balanceName] else {
                throw CoinLedgerRepositoryError.ledgerNotCurrent
            }

            let updatedCommand = try finalizedCommand(command, commit: commit, at: date)
            var entities: [(CoinLedgerRecordEntity, String?)] = [
                (.releaseCommand(updatedCommand), commandRecord.changeTag),
                (.releaseOccurrenceClaim(try ReleaseOccurrenceClaim(
                    ledgerEpochID: fence.claim.ledgerEpochID, occurrenceID: fence.claim.occurrenceID,
                    commandID: commandID, state: commit ? .held : .released, updatedAt: date
                )), fence.claimRecord.changeTag),
            ]
            if reservation.source == .monthlyFree {
                let allowance = try monthlyAllowance(from: balanceRecord)
                guard allowance.reserved > 0 else {
                    throw CoinLedgerRepositoryError.database(.invalidRecord)
                }
                let updated = try MonthlyAllowance(
                    monthID: allowance.monthID,
                    quota: allowance.quota,
                    used: commit ? try adding(allowance.used, 1) : allowance.used,
                    reserved: allowance.reserved - 1,
                    creationDate: allowance.creationDate,
                    updatedAt: date
                )
                entities.append((.monthlyAllowance(updated), balanceRecord.changeTag))
            } else {
                let account = try coinAccount(from: balanceRecord)
                guard account.purchasedReserved > 0 else {
                    throw CoinLedgerRepositoryError.database(.invalidRecord)
                }
                let updated = try CoinAccount(
                    purchasedAvailable: commit ? account.purchasedAvailable - 1
                        : account.purchasedAvailable,
                    purchasedReserved: account.purchasedReserved - 1,
                    revision: try adding(account.revision, 1),
                    updatedAt: date
                )
                entities.append((.coinAccount(updated), balanceRecord.changeTag))
            }
            let event = try CoinLedgerEvent(
                eventID: commit
                    ? CoinLedgerDeterministicID.spend(commandID: commandID)
                    : CoinLedgerDeterministicID.release(commandID: commandID, attempt: 1),
                kind: commit ? .spend : .release,
                source: reservation.source,
                quantity: 1,
                relatedTransactionID: nil,
                relatedCommandID: commandID,
                occurrenceID: reservation.occurrenceID,
                createdAt: date
            )
            entities.append((.event(event), nil))

            do {
                var recordsToSave = try modifyRequest(for: entities).recordsToSave
                recordsToSave.append(fence.epoch)
                _ = try await database.modify(CoinLedgerModifyRequest(recordsToSave: recordsToSave))
                return updatedCommand
            } catch CoinLedgerDatabaseError.serverRecordChanged
                where attempt < conflictRetryLimit {
                continue
            } catch CoinLedgerDatabaseError.resultUnknown {
                guard let resolved = try await fetchReleaseCommand(commandID: commandID) else {
                    throw CoinLedgerRepositoryError.reconciliationRequired(
                        commandID: commandID
                    )
                }
                if commit, resolved.state == .committed { return resolved }
                if !commit, resolved.state == .compensated { return resolved }
                throw CoinLedgerRepositoryError.reconciliationRequired(commandID: commandID)
            } catch {
                throw map(error)
            }
        }
        throw CoinLedgerRepositoryError.database(.serverRecordChanged)
    }

    func finalizedCommand(
        _ command: ReleaseCommand,
        commit: Bool,
        at date: Date
    ) throws -> ReleaseCommand {
        do {
            if commit {
                return try command.transitioning(to: .committed, at: date)
            }
            if command.state == .reconciliationRequired {
                return try command.transitioning(to: .compensated, at: date)
            }
            let compensating = command.state == .compensating
                ? command
                : try command.transitioning(to: .compensating, at: date)
            return try compensating.transitioning(to: .compensated, at: date)
        } catch {
            throw CoinLedgerRepositoryError.database(.invalidRecord)
        }
    }

    func monthID(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    func adding(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else {
            throw CoinLedgerRepositoryError.database(.invalidRecord)
        }
        return value
    }

    func map(_ error: Error) -> CoinLedgerRepositoryError {
        if let error = error as? CoinLedgerRepositoryError {
            return error
        }
        if let error = error as? CoinLedgerDatabaseError {
            return .database(error)
        }
        if let error = error as? CoinLedgerRecordMapperError {
            switch error {
            case .unsupportedSchema:
                return .database(.unsupportedSchema)
            default:
                return .database(.invalidRecord)
            }
        }
        return .database(.unexpectedRequest)
    }
}
