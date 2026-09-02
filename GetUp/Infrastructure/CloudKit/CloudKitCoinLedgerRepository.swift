import Foundation

struct CloudKitCoinLedgerRepository: CoinLedgerRepository, Sendable {
    private let database: any CoinLedgerCloudDatabase
    private let mapper: CoinLedgerRecordMapper
    private let conflictRetryLimit: Int

    init(
        database: any CoinLedgerCloudDatabase,
        mapper: CoinLedgerRecordMapper = CoinLedgerRecordMapper(),
        conflictRetryLimit: Int = 2
    ) {
        self.database = database
        self.mapper = mapper
        self.conflictRetryLimit = max(0, conflictRetryLimit)
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
        let allowanceName = CoinLedgerRecordID.allowance(monthID: request.monthID)
        let freeGrantName = CoinLedgerDeterministicID.freeGrant(monthID: request.monthID)
        let reservationName = CoinLedgerDeterministicID.reservation(
            commandID: request.commandID
        )
        let commandName = CoinLedgerRecordID.releaseCommand(commandID: request.commandID)
        let names = [allowanceName, freeGrantName, reservationName, commandName]

        for attempt in 0...conflictRetryLimit {
            let records = try await fetch(recordNames: names)
            let indexed = try index(records)

            if let commandRecord = indexed[commandName] {
                let command = try releaseCommand(from: commandRecord)
                try validate(command, against: request)
                return try existingReservation(
                    command: command,
                    allowanceRecord: indexed[allowanceName],
                    accountRecord: nil
                )
            }
            guard indexed[reservationName] == nil else {
                throw CoinLedgerRepositoryError.reconciliationRequired(
                    commandID: request.commandID
                )
            }

            let existingAllowance = try indexed[allowanceName].map(monthlyAllowance(from:))
            let allowance = try reserveFreeAllowance(
                existingAllowance,
                monthID: request.monthID,
                at: request.requestedAt
            )
            let command = try ReleaseCommand.requested(
                commandID: request.commandID,
                occurrenceID: request.occurrenceID,
                ruleID: request.ruleID,
                requestedFrom: request.requestedFrom,
                at: request.requestedAt
            ).transitioning(
                to: .reserved,
                fundingSource: .monthlyFree,
                at: request.requestedAt
            )
            let reservation = try reservationEvent(
                request: request,
                source: .monthlyFree
            )

            var entities: [(CoinLedgerRecordEntity, String?)] = [
                (.monthlyAllowance(allowance), indexed[allowanceName]?.changeTag),
                (.event(reservation), nil),
                (.releaseCommand(command), nil),
            ]
            if existingAllowance == nil {
                guard indexed[freeGrantName] == nil else {
                    throw CoinLedgerRepositoryError.database(.invalidRecord)
                }
                entities.append((
                    .event(try freeGrantEvent(
                        monthID: request.monthID,
                        createdAt: request.requestedAt
                    )),
                    nil
                ))
            }

            do {
                _ = try await database.modify(try modifyRequest(for: entities))
                return CoinReleaseReservation(
                    command: command,
                    allowance: allowance,
                    account: nil
                )
            } catch CoinLedgerDatabaseError.serverRecordChanged
                where attempt < conflictRetryLimit {
                continue
            } catch CoinLedgerDatabaseError.resultUnknown {
                return try await resolveUnknownReservation(
                    commandID: request.commandID,
                    proposedAllowance: allowance,
                    proposedAccount: nil
                )
            } catch {
                throw map(error)
            }
        }

        throw CoinLedgerRepositoryError.database(.serverRecordChanged)
    }

    func reservePurchasedCoin(
        _ request: PurchasedCoinReservationRequest
    ) async throws -> CoinReleaseReservation {
        let accountName = CoinLedgerRecordID.coinAccount
        let reservationName = CoinLedgerDeterministicID.reservation(
            commandID: request.commandID
        )
        let commandName = CoinLedgerRecordID.releaseCommand(commandID: request.commandID)
        let names = [accountName, reservationName, commandName]

        for attempt in 0...conflictRetryLimit {
            let records = try await fetch(recordNames: names)
            let indexed = try index(records)

            if let commandRecord = indexed[commandName] {
                let command = try releaseCommand(from: commandRecord)
                try validate(command, against: request)
                return try existingReservation(
                    command: command,
                    allowanceRecord: nil,
                    accountRecord: indexed[accountName]
                )
            }
            guard indexed[reservationName] == nil else {
                throw CoinLedgerRepositoryError.reconciliationRequired(
                    commandID: request.commandID
                )
            }
            guard let accountRecord = indexed[accountName] else {
                throw CoinLedgerRepositoryError.ledgerNotCurrent
            }

            let account = try coinAccount(from: accountRecord)
            guard account.purchasedUsable > 0 else {
                throw CoinLedgerRepositoryError.insufficientPurchasedBalance
            }
            let updatedAccount = try CoinAccount(
                purchasedAvailable: account.purchasedAvailable,
                purchasedReserved: try adding(account.purchasedReserved, 1),
                revision: try adding(account.revision, 1),
                updatedAt: request.requestedAt
            )
            let command = try ReleaseCommand.requested(
                commandID: request.commandID,
                occurrenceID: request.occurrenceID,
                ruleID: request.ruleID,
                requestedFrom: request.requestedFrom,
                at: request.requestedAt
            ).transitioning(
                to: .reserved,
                fundingSource: .purchased,
                at: request.requestedAt
            )
            let reservation = try reservationEvent(
                commandID: request.commandID,
                occurrenceID: request.occurrenceID,
                source: .purchased,
                createdAt: request.requestedAt
            )

            do {
                _ = try await database.modify(try modifyRequest(for: [
                    (.coinAccount(updatedAccount), accountRecord.changeTag),
                    (.event(reservation), nil),
                    (.releaseCommand(command), nil),
                ]))
                return CoinReleaseReservation(
                    command: command,
                    allowance: nil,
                    account: updatedAccount
                )
            } catch CoinLedgerDatabaseError.serverRecordChanged
                where attempt < conflictRetryLimit {
                continue
            } catch CoinLedgerDatabaseError.resultUnknown {
                return try await resolveUnknownReservation(
                    commandID: request.commandID,
                    proposedAllowance: nil,
                    proposedAccount: updatedAccount
                )
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
            command.ruleID == request.ruleID,
            command.requestedFrom == request.requestedFrom
        else {
            throw CoinLedgerRepositoryError.database(.invalidRecord)
        }
    }

    func validate(
        _ command: ReleaseCommand,
        against request: PurchasedCoinReservationRequest
    ) throws {
        guard
            command.commandID == request.commandID,
            command.occurrenceID == request.occurrenceID,
            command.ruleID == request.ruleID,
            command.requestedFrom == request.requestedFrom
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

    func resolveUnknownReservation(
        commandID: UUID,
        proposedAllowance: MonthlyAllowance?,
        proposedAccount: CoinAccount?
    ) async throws -> CoinReleaseReservation {
        let name = CoinLedgerRecordID.releaseCommand(commandID: commandID)
        let records = try await fetch(recordNames: [name])
        guard let record = try index(records)[name] else {
            throw CoinLedgerRepositoryError.reconciliationRequired(commandID: commandID)
        }
        let command = try releaseCommand(from: record)
        return try existingReservation(
            command: command,
            allowanceRecord: nil,
            accountRecord: nil
        ).replacingBalances(
            allowance: proposedAllowance,
            account: proposedAccount
        )
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

            do {
                _ = try await database.modify(try modifyRequest(for: [
                    (.releaseCommand(updated), record.changeTag),
                ]))
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

            let reservation = try ledgerEvent(from: reservationRecord)
            guard
                reservation.kind == .reservation,
                reservation.relatedCommandID == commandID,
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
                _ = try await database.modify(try modifyRequest(for: entities))
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

private extension CoinReleaseReservation {
    func replacingBalances(
        allowance: MonthlyAllowance?,
        account: CoinAccount?
    ) -> CoinReleaseReservation {
        CoinReleaseReservation(
            command: command,
            allowance: allowance,
            account: account
        )
    }
}
