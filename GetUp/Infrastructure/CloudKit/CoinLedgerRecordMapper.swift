import Foundation

enum CoinLedgerRecordEntity: Equatable, Sendable {
    case ledgerEpoch(LedgerEpoch)
    case coinAccount(CoinAccount)
    case monthlyAllowance(MonthlyAllowance)
    case purchaseGrant(PurchaseGrant)
    case event(CoinLedgerEvent)
    case releaseCommand(ReleaseCommand)
}

enum CoinLedgerRecordMapperError: Error, Equatable, Sendable {
    case unsupportedRecordType(String)
    case unsupportedSchema(recordType: String, found: Int, supported: Int)
    case missingField(recordType: String, field: String)
    case invalidField(recordType: String, field: String)
    case unexpectedField(recordType: String, field: String)
    case invalidRecordName(recordType: String, found: String, expected: String)
    case invalidEntity(recordType: String)
}

struct CoinLedgerRecordMapper: Sendable {
    func record(for entity: CoinLedgerRecordEntity) throws -> CloudKitRecordSnapshot {
        switch entity {
        case let .ledgerEpoch(epoch):
            try validateSchema(
                epoch.schemaVersion,
                recordType: CoinLedgerRecordType.ledgerEpoch
            )
            var fields: [String: CloudKitRecordValue] = [
                Field.schemaVersion: .int(epoch.schemaVersion),
                Field.epochID: .uuid(epoch.epochID),
                Field.createdAt: .date(epoch.createdAt),
                Field.reason: .string(epoch.reason.rawValue),
                Field.disclosureVersion: .int(epoch.disclosureVersion),
            ]
            fields[Field.suppressedFreeMonthID] = epoch.suppressedFreeMonthID.map(
                CloudKitRecordValue.string
            )
            return snapshot(
                recordType: CoinLedgerRecordType.ledgerEpoch,
                recordName: CoinLedgerRecordID.ledgerEpoch,
                fields: fields
            )

        case let .coinAccount(account):
            try validateSchema(
                account.schemaVersion,
                recordType: CoinLedgerRecordType.coinAccount
            )
            return snapshot(
                recordType: CoinLedgerRecordType.coinAccount,
                recordName: CoinLedgerRecordID.coinAccount,
                fields: [
                    Field.schemaVersion: .int(account.schemaVersion),
                    Field.purchasedAvailable: .int(account.purchasedAvailable),
                    Field.purchasedReserved: .int(account.purchasedReserved),
                    Field.revision: .int(account.revision),
                    Field.updatedAt: .date(account.updatedAt),
                ]
            )

        case let .monthlyAllowance(allowance):
            try validateSchema(
                allowance.schemaVersion,
                recordType: CoinLedgerRecordType.monthlyAllowance
            )
            return snapshot(
                recordType: CoinLedgerRecordType.monthlyAllowance,
                recordName: CoinLedgerRecordID.allowance(monthID: allowance.monthID),
                fields: [
                    Field.schemaVersion: .int(allowance.schemaVersion),
                    Field.monthID: .string(allowance.monthID),
                    Field.quota: .int(allowance.quota),
                    Field.used: .int(allowance.used),
                    Field.reserved: .int(allowance.reserved),
                    Field.creationDate: .date(allowance.creationDate),
                    Field.updatedAt: .date(allowance.updatedAt),
                ]
            )

        case let .purchaseGrant(grant):
            try validateSchema(
                grant.schemaVersion,
                recordType: CoinLedgerRecordType.purchaseGrant
            )
            return snapshot(
                recordType: CoinLedgerRecordType.purchaseGrant,
                recordName: CoinLedgerRecordID.purchaseGrant(
                    environment: grant.environment,
                    transactionID: grant.transactionID
                ),
                fields: [
                    Field.schemaVersion: .int(grant.schemaVersion),
                    Field.transactionID: .int64(try signedInteger(
                        grant.transactionID,
                        recordType: CoinLedgerRecordType.purchaseGrant,
                        field: Field.transactionID
                    )),
                    Field.environment: .string(grant.environment.rawValue),
                    Field.productID: .string(grant.productID),
                    Field.quantity: .int(grant.quantity),
                    Field.purchaseDate: .date(grant.purchaseDate),
                    Field.verificationState: .string(grant.verificationState.rawValue),
                    Field.adjustedQuantity: .int(grant.adjustedQuantity),
                ]
            )

        case let .event(event):
            try validateSchema(
                event.schemaVersion,
                recordType: CoinLedgerRecordType.event
            )
            var fields: [String: CloudKitRecordValue] = [
                Field.schemaVersion: .int(event.schemaVersion),
                Field.eventID: .string(event.eventID),
                Field.kind: .string(event.kind.rawValue),
                Field.source: .string(event.source.rawValue),
                Field.quantity: .int(event.quantity),
                Field.createdAt: .date(event.createdAt),
            ]
            if let transactionID = event.relatedTransactionID {
                fields[Field.relatedTransactionID] = .int64(try signedInteger(
                    transactionID,
                    recordType: CoinLedgerRecordType.event,
                    field: Field.relatedTransactionID
                ))
            }
            fields[Field.relatedCommandID] = event.relatedCommandID.map(
                CloudKitRecordValue.uuid
            )
            fields[Field.occurrenceID] = event.occurrenceID.map(CloudKitRecordValue.string)
            return snapshot(
                recordType: CoinLedgerRecordType.event,
                recordName: CoinLedgerRecordID.event(eventID: event.eventID),
                fields: fields
            )

        case let .releaseCommand(command):
            try validateSchema(
                command.schemaVersion,
                recordType: CoinLedgerRecordType.releaseCommand
            )
            var fields: [String: CloudKitRecordValue] = [
                Field.schemaVersion: .int(command.schemaVersion),
                Field.commandID: .uuid(command.commandID),
                Field.occurrenceID: .string(command.occurrenceID),
                Field.ruleID: .uuid(command.ruleID),
                Field.requestedFrom: .string(command.requestedFrom.rawValue),
                Field.state: .string(command.state.rawValue),
                Field.createdAt: .date(command.createdAt),
                Field.updatedAt: .date(command.updatedAt),
            ]
            fields[Field.fundingSource] = command.fundingSource.map {
                .string($0.rawValue)
            }
            fields[Field.failureCode] = command.failureCode.map(CloudKitRecordValue.string)
            return snapshot(
                recordType: CoinLedgerRecordType.releaseCommand,
                recordName: CoinLedgerRecordID.releaseCommand(commandID: command.commandID),
                fields: fields
            )
        }
    }

    func entity(from record: CloudKitRecordSnapshot) throws -> CoinLedgerRecordEntity {
        let allowedFields = try allowedFields(for: record.recordType)
        try validateSchema(record, allowedFields: allowedFields)

        do {
            switch record.recordType {
            case CoinLedgerRecordType.ledgerEpoch:
                let entity = LedgerEpoch(
                    schemaVersion: try int(Field.schemaVersion, in: record),
                    epochID: try uuid(Field.epochID, in: record),
                    createdAt: try date(Field.createdAt, in: record),
                    reason: try rawValue(Field.reason, in: record),
                    suppressedFreeMonthID: try optionalString(
                        Field.suppressedFreeMonthID,
                        in: record
                    ),
                    disclosureVersion: try int(Field.disclosureVersion, in: record)
                )
                try validateRecordName(record, expected: CoinLedgerRecordID.ledgerEpoch)
                return .ledgerEpoch(entity)

            case CoinLedgerRecordType.coinAccount:
                let entity = try CoinAccount(
                    schemaVersion: try int(Field.schemaVersion, in: record),
                    purchasedAvailable: try int(Field.purchasedAvailable, in: record),
                    purchasedReserved: try int(Field.purchasedReserved, in: record),
                    revision: try int(Field.revision, in: record),
                    updatedAt: try date(Field.updatedAt, in: record)
                )
                try validateRecordName(record, expected: CoinLedgerRecordID.coinAccount)
                return .coinAccount(entity)

            case CoinLedgerRecordType.monthlyAllowance:
                let entity = try MonthlyAllowance(
                    schemaVersion: try int(Field.schemaVersion, in: record),
                    monthID: try string(Field.monthID, in: record),
                    quota: try int(Field.quota, in: record),
                    used: try int(Field.used, in: record),
                    reserved: try int(Field.reserved, in: record),
                    creationDate: try date(Field.creationDate, in: record),
                    updatedAt: try date(Field.updatedAt, in: record)
                )
                try validateRecordName(
                    record,
                    expected: CoinLedgerRecordID.allowance(monthID: entity.monthID)
                )
                return .monthlyAllowance(entity)

            case CoinLedgerRecordType.purchaseGrant:
                let transactionID = try unsignedInteger(Field.transactionID, in: record)
                let environment: PurchaseEnvironment = try rawValue(
                    Field.environment,
                    in: record
                )
                guard try rawValue(
                    Field.verificationState,
                    in: record
                ) as PurchaseVerificationState == .verified else {
                    throw CoinLedgerRecordMapperError.invalidField(
                        recordType: record.recordType,
                        field: Field.verificationState
                    )
                }
                let entity = try PurchaseGrant(
                    schemaVersion: try int(Field.schemaVersion, in: record),
                    transactionID: transactionID,
                    environment: environment,
                    productID: try string(Field.productID, in: record),
                    quantity: try int(Field.quantity, in: record),
                    purchaseDate: try date(Field.purchaseDate, in: record),
                    adjustedQuantity: try int(Field.adjustedQuantity, in: record)
                )
                try validateRecordName(
                    record,
                    expected: CoinLedgerRecordID.purchaseGrant(
                        environment: environment,
                        transactionID: transactionID
                    )
                )
                return .purchaseGrant(entity)

            case CoinLedgerRecordType.event:
                let entity = try CoinLedgerEvent(
                    schemaVersion: try int(Field.schemaVersion, in: record),
                    eventID: try string(Field.eventID, in: record),
                    kind: try rawValue(Field.kind, in: record),
                    source: try rawValue(Field.source, in: record),
                    quantity: try int(Field.quantity, in: record),
                    relatedTransactionID: try optionalUnsignedInteger(
                        Field.relatedTransactionID,
                        in: record
                    ),
                    relatedCommandID: try optionalUUID(Field.relatedCommandID, in: record),
                    occurrenceID: try optionalString(Field.occurrenceID, in: record),
                    createdAt: try date(Field.createdAt, in: record)
                )
                try validateRecordName(
                    record,
                    expected: CoinLedgerRecordID.event(eventID: entity.eventID)
                )
                return .event(entity)

            case CoinLedgerRecordType.releaseCommand:
                let payload = ReleaseCommandPayload(
                    schemaVersion: try int(Field.schemaVersion, in: record),
                    commandID: try uuid(Field.commandID, in: record),
                    occurrenceID: try string(Field.occurrenceID, in: record),
                    ruleID: try uuid(Field.ruleID, in: record),
                    requestedFrom: try rawValue(Field.requestedFrom, in: record),
                    fundingSource: try optionalRawValue(Field.fundingSource, in: record),
                    state: try rawValue(Field.state, in: record),
                    createdAt: try date(Field.createdAt, in: record),
                    updatedAt: try date(Field.updatedAt, in: record),
                    failureCode: try optionalString(Field.failureCode, in: record)
                )
                let data = try JSONEncoder().encode(payload)
                let entity = try JSONDecoder().decode(ReleaseCommand.self, from: data)
                try validateRecordName(
                    record,
                    expected: CoinLedgerRecordID.releaseCommand(commandID: entity.commandID)
                )
                return .releaseCommand(entity)

            default:
                throw CoinLedgerRecordMapperError.unsupportedRecordType(record.recordType)
            }
        } catch let error as CoinLedgerRecordMapperError {
            throw error
        } catch {
            throw CoinLedgerRecordMapperError.invalidEntity(recordType: record.recordType)
        }
    }
}

private extension CoinLedgerRecordMapper {
    enum Field {
        static let schemaVersion = "schemaVersion"
        static let epochID = "epochID"
        static let createdAt = "createdAt"
        static let reason = "reason"
        static let suppressedFreeMonthID = "suppressedFreeMonthID"
        static let disclosureVersion = "disclosureVersion"
        static let purchasedAvailable = "purchasedAvailable"
        static let purchasedReserved = "purchasedReserved"
        static let revision = "revision"
        static let updatedAt = "updatedAt"
        static let monthID = "monthID"
        static let quota = "quota"
        static let used = "used"
        static let reserved = "reserved"
        static let creationDate = "creationDate"
        static let transactionID = "transactionID"
        static let environment = "environment"
        static let productID = "productID"
        static let quantity = "quantity"
        static let purchaseDate = "purchaseDate"
        static let verificationState = "verificationState"
        static let adjustedQuantity = "adjustedQuantity"
        static let eventID = "eventID"
        static let kind = "kind"
        static let source = "source"
        static let relatedTransactionID = "relatedTransactionID"
        static let relatedCommandID = "relatedCommandID"
        static let occurrenceID = "occurrenceID"
        static let commandID = "commandID"
        static let ruleID = "ruleID"
        static let requestedFrom = "requestedFrom"
        static let fundingSource = "fundingSource"
        static let state = "state"
        static let failureCode = "failureCode"
    }

    struct ReleaseCommandPayload: Codable {
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
    }

    func snapshot(
        recordType: String,
        recordName: String,
        fields: [String: CloudKitRecordValue]
    ) -> CloudKitRecordSnapshot {
        CloudKitRecordSnapshot(
            recordType: recordType,
            recordName: recordName,
            changeTag: nil,
            fields: fields
        )
    }

    func allowedFields(for recordType: String) throws -> Set<String> {
        switch recordType {
        case CoinLedgerRecordType.ledgerEpoch:
            [Field.schemaVersion, Field.epochID, Field.createdAt, Field.reason,
             Field.suppressedFreeMonthID, Field.disclosureVersion]
        case CoinLedgerRecordType.coinAccount:
            [Field.schemaVersion, Field.purchasedAvailable, Field.purchasedReserved,
             Field.revision, Field.updatedAt]
        case CoinLedgerRecordType.monthlyAllowance:
            [Field.schemaVersion, Field.monthID, Field.quota, Field.used, Field.reserved,
             Field.creationDate, Field.updatedAt]
        case CoinLedgerRecordType.purchaseGrant:
            [Field.schemaVersion, Field.transactionID, Field.environment, Field.productID,
             Field.quantity, Field.purchaseDate, Field.verificationState,
             Field.adjustedQuantity]
        case CoinLedgerRecordType.event:
            [Field.schemaVersion, Field.eventID, Field.kind, Field.source, Field.quantity,
             Field.relatedTransactionID, Field.relatedCommandID, Field.occurrenceID,
             Field.createdAt]
        case CoinLedgerRecordType.releaseCommand:
            [Field.schemaVersion, Field.commandID, Field.occurrenceID, Field.ruleID,
             Field.requestedFrom, Field.fundingSource, Field.state, Field.createdAt,
             Field.updatedAt, Field.failureCode]
        default:
            throw CoinLedgerRecordMapperError.unsupportedRecordType(recordType)
        }
    }

    func validateSchema(
        _ found: Int,
        recordType: String,
        supported: Int = 1
    ) throws {
        guard found == supported else {
            throw CoinLedgerRecordMapperError.unsupportedSchema(
                recordType: recordType,
                found: found,
                supported: supported
            )
        }
    }

    func validateSchema(
        _ record: CloudKitRecordSnapshot,
        allowedFields: Set<String>
    ) throws {
        guard let value = record.fields[Field.schemaVersion] else {
            throw CoinLedgerRecordMapperError.missingField(
                recordType: record.recordType,
                field: Field.schemaVersion
            )
        }
        guard case let .int(schemaVersion) = value else {
            throw CoinLedgerRecordMapperError.invalidField(
                recordType: record.recordType,
                field: Field.schemaVersion
            )
        }
        try validateSchema(schemaVersion, recordType: record.recordType)
        if let unexpected = record.fields.keys.sorted().first(where: {
            !allowedFields.contains($0)
        }) {
            throw CoinLedgerRecordMapperError.unexpectedField(
                recordType: record.recordType,
                field: unexpected
            )
        }
    }

    func validateRecordName(
        _ record: CloudKitRecordSnapshot,
        expected: String
    ) throws {
        guard record.recordName == expected else {
            throw CoinLedgerRecordMapperError.invalidRecordName(
                recordType: record.recordType,
                found: record.recordName,
                expected: expected
            )
        }
    }

    func signedInteger(
        _ value: UInt64,
        recordType: String,
        field: String
    ) throws -> Int64 {
        guard value <= UInt64(Int64.max) else {
            throw CoinLedgerRecordMapperError.invalidField(
                recordType: recordType,
                field: field
            )
        }
        return Int64(value)
    }

    func string(_ field: String, in record: CloudKitRecordSnapshot) throws -> String {
        guard let value = record.fields[field] else {
            throw missing(field, in: record)
        }
        guard case let .string(value) = value else {
            throw invalid(field, in: record)
        }
        return value
    }

    func int(_ field: String, in record: CloudKitRecordSnapshot) throws -> Int {
        guard let value = record.fields[field] else {
            throw missing(field, in: record)
        }
        guard case let .int(value) = value else {
            throw invalid(field, in: record)
        }
        return value
    }

    func date(_ field: String, in record: CloudKitRecordSnapshot) throws -> Date {
        guard let value = record.fields[field] else {
            throw missing(field, in: record)
        }
        guard case let .date(value) = value else {
            throw invalid(field, in: record)
        }
        return value
    }

    func uuid(_ field: String, in record: CloudKitRecordSnapshot) throws -> UUID {
        guard let value = record.fields[field] else {
            throw missing(field, in: record)
        }
        guard case let .uuid(value) = value else {
            throw invalid(field, in: record)
        }
        return value
    }

    func unsignedInteger(
        _ field: String,
        in record: CloudKitRecordSnapshot
    ) throws -> UInt64 {
        guard let value = record.fields[field] else {
            throw missing(field, in: record)
        }
        guard case let .int64(value) = value, value >= 0 else {
            throw invalid(field, in: record)
        }
        return UInt64(value)
    }

    func optionalString(
        _ field: String,
        in record: CloudKitRecordSnapshot
    ) throws -> String? {
        guard let value = record.fields[field] else {
            return nil
        }
        guard case let .string(value) = value else {
            throw invalid(field, in: record)
        }
        return value
    }

    func optionalUUID(
        _ field: String,
        in record: CloudKitRecordSnapshot
    ) throws -> UUID? {
        guard let value = record.fields[field] else {
            return nil
        }
        guard case let .uuid(value) = value else {
            throw invalid(field, in: record)
        }
        return value
    }

    func optionalUnsignedInteger(
        _ field: String,
        in record: CloudKitRecordSnapshot
    ) throws -> UInt64? {
        guard record.fields[field] != nil else {
            return nil
        }
        return try unsignedInteger(field, in: record)
    }

    func rawValue<Value: RawRepresentable>(
        _ field: String,
        in record: CloudKitRecordSnapshot
    ) throws -> Value where Value.RawValue == String {
        let rawValue = try string(field, in: record)
        guard let value = Value(rawValue: rawValue) else {
            throw invalid(field, in: record)
        }
        return value
    }

    func optionalRawValue<Value: RawRepresentable>(
        _ field: String,
        in record: CloudKitRecordSnapshot
    ) throws -> Value? where Value.RawValue == String {
        guard record.fields[field] != nil else {
            return nil
        }
        return try rawValue(field, in: record)
    }

    func missing(
        _ field: String,
        in record: CloudKitRecordSnapshot
    ) -> CoinLedgerRecordMapperError {
        .missingField(recordType: record.recordType, field: field)
    }

    func invalid(
        _ field: String,
        in record: CloudKitRecordSnapshot
    ) -> CoinLedgerRecordMapperError {
        .invalidField(recordType: record.recordType, field: field)
    }
}
