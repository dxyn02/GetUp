@preconcurrency import CloudKit
import Foundation

struct SystemCloudKitRecordEnvelope: @unchecked Sendable {
    let record: CKRecord
    let changeTag: String?
    let creationDate: Date?

    init(record: CKRecord, changeTag: String?, creationDate: Date?) {
        self.record = record
        self.changeTag = changeTag
        self.creationDate = creationDate
    }

    init(record: CKRecord) {
        self.init(
            record: record,
            changeTag: record.recordChangeTag,
            creationDate: record.creationDate
        )
    }
}

struct SystemCloudKitModifyResult: @unchecked Sendable {
    let saveResults: [CKRecord.ID: Result<SystemCloudKitRecordEnvelope, Error>]
    let deleteResults: [CKRecord.ID: Result<Void, Error>]
}

protocol SystemCloudKitDatabaseClient: Sendable {
    func saveZone(_ zone: CKRecordZone) async throws
    func fetchRecords(
        _ recordIDs: [CKRecord.ID]
    ) async throws -> [CKRecord.ID: Result<SystemCloudKitRecordEnvelope, Error>]
    func modifyRecords(
        saving recordsToSave: [CKRecord],
        deleting recordIDsToDelete: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        atomically: Bool
    ) async throws -> SystemCloudKitModifyResult
}

struct CKDatabaseSystemCloudKitClient: SystemCloudKitDatabaseClient, @unchecked Sendable {
    private let database: CKDatabase

    init(database: CKDatabase) {
        self.database = database
    }

    func saveZone(_ zone: CKRecordZone) async throws {
        _ = try await database.save(zone)
    }

    func fetchRecords(
        _ recordIDs: [CKRecord.ID]
    ) async throws -> [CKRecord.ID: Result<SystemCloudKitRecordEnvelope, Error>] {
        try await database.records(for: recordIDs).mapValues { result in
            result.map(SystemCloudKitRecordEnvelope.init(record:))
        }
    }

    func modifyRecords(
        saving recordsToSave: [CKRecord],
        deleting recordIDsToDelete: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        atomically: Bool
    ) async throws -> SystemCloudKitModifyResult {
        let result = try await database.modifyRecords(
            saving: recordsToSave,
            deleting: recordIDsToDelete,
            savePolicy: savePolicy,
            atomically: atomically
        )
        return SystemCloudKitModifyResult(
            saveResults: result.saveResults.mapValues { saveResult in
                saveResult.map(SystemCloudKitRecordEnvelope.init(record:))
            },
            deleteResults: result.deleteResults
        )
    }
}

actor SystemCoinLedgerCloudDatabase: CoinLedgerCloudDatabase {
    private let client: any SystemCloudKitDatabaseClient
    private let zoneID: CKRecordZone.ID
    private var preparedZone = false
    private var cachedRecords: [String: SystemCloudKitRecordEnvelope] = [:]

    init(
        client: any SystemCloudKitDatabaseClient,
        zoneName: String = SharedIdentifiers.coinLedgerZoneName
    ) {
        self.client = client
        zoneID = CKRecordZone.ID(
            zoneName: zoneName,
            ownerName: CKCurrentUserDefaultName
        )
    }

    init(
        container: CKContainer = .default(),
        zoneName: String = SharedIdentifiers.coinLedgerZoneName
    ) {
        self.init(
            client: CKDatabaseSystemCloudKitClient(database: container.privateCloudDatabase),
            zoneName: zoneName
        )
    }

    func fetch(_ request: CoinLedgerFetchRequest) async throws -> [CloudKitRecordSnapshot] {
        try validateRecordNames(request.recordNames)
        guard !request.recordNames.isEmpty else { return [] }

        let recordIDs = request.recordNames.map(recordID(named:))
        let results: [CKRecord.ID: Result<SystemCloudKitRecordEnvelope, Error>]
        do {
            results = try await client.fetchRecords(recordIDs)
        } catch {
            throw Self.map(error)
        }

        var snapshots: [CloudKitRecordSnapshot] = []
        for recordID in recordIDs {
            guard let result = results[recordID] else {
                throw CoinLedgerDatabaseError.resultUnknown
            }
            switch result {
            case .success(let envelope):
                let snapshot = try snapshot(from: envelope)
                cachedRecords[recordID.recordName] = envelope
                snapshots.append(snapshot)
            case .failure(let error) where Self.isMissingRecord(error):
                cachedRecords.removeValue(forKey: recordID.recordName)
            case .failure(let error):
                throw Self.map(error)
            }
        }
        return snapshots
    }

    func modify(_ request: CoinLedgerModifyRequest) async throws -> [CloudKitRecordSnapshot] {
        try validate(request)
        guard !request.recordsToSave.isEmpty || !request.recordNamesToDelete.isEmpty else {
            return []
        }
        try await ensureZone()

        let recordsToSave = try request.recordsToSave.map(recordForSave(from:))
        let recordIDsToDelete = request.recordNamesToDelete.map(recordID(named:))
        let result: SystemCloudKitModifyResult
        do {
            result = try await client.modifyRecords(
                saving: recordsToSave,
                deleting: recordIDsToDelete,
                savePolicy: .ifServerRecordUnchanged,
                atomically: request.isAtomic
            )
        } catch {
            throw Self.map(error)
        }

        var snapshots: [CloudKitRecordSnapshot] = []
        for record in recordsToSave {
            guard let saveResult = result.saveResults[record.recordID] else {
                throw CoinLedgerDatabaseError.resultUnknown
            }
            switch saveResult {
            case .success(let envelope):
                let snapshot = try snapshot(from: envelope)
                cachedRecords[record.recordID.recordName] = envelope
                snapshots.append(snapshot)
            case .failure(let error):
                throw Self.map(error)
            }
        }
        for recordID in recordIDsToDelete {
            guard let deleteResult = result.deleteResults[recordID] else {
                throw CoinLedgerDatabaseError.resultUnknown
            }
            if case .failure(let error) = deleteResult, !Self.isMissingRecord(error) {
                throw Self.map(error)
            }
            cachedRecords.removeValue(forKey: recordID.recordName)
        }
        return snapshots
    }
}

private extension SystemCoinLedgerCloudDatabase {
    static let uuidFields: Set<String> = [
        "epochID", "commandID", "ruleID", "relatedCommandID",
    ]
    static let int64Fields: Set<String> = [
        "transactionID", "relatedTransactionID",
    ]

    func ensureZone() async throws {
        guard !preparedZone else { return }
        do {
            try await client.saveZone(CKRecordZone(zoneID: zoneID))
            preparedZone = true
        } catch {
            throw Self.map(error)
        }
    }

    func recordID(named name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    func validateRecordNames(_ names: [String]) throws {
        guard names.allSatisfy({ !$0.isEmpty }), Set(names).count == names.count else {
            throw CoinLedgerDatabaseError.invalidRecord
        }
    }

    func validate(_ request: CoinLedgerModifyRequest) throws {
        let saveNames = request.recordsToSave.map(\.recordName)
        try validateRecordNames(saveNames)
        try validateRecordNames(request.recordNamesToDelete)
        guard Set(saveNames).isDisjoint(with: request.recordNamesToDelete),
              request.recordsToSave.allSatisfy({ !$0.recordType.isEmpty }),
              request.savePolicy == .ifServerRecordUnchanged else {
            throw CoinLedgerDatabaseError.unexpectedRequest
        }
    }

    func recordForSave(from snapshot: CloudKitRecordSnapshot) throws -> CKRecord {
        let record: CKRecord
        if let changeTag = snapshot.changeTag {
            guard let cached = cachedRecords[snapshot.recordName],
                  cached.changeTag == changeTag,
                  cached.record.recordType == snapshot.recordType,
                  cached.record.recordID.zoneID == zoneID else {
                throw CoinLedgerDatabaseError.serverRecordChanged
            }
            record = cached.record
        } else {
            record = CKRecord(
                recordType: snapshot.recordType,
                recordID: recordID(named: snapshot.recordName)
            )
        }

        for key in record.allKeys() {
            record[key] = nil
        }
        for (key, value) in snapshot.fields {
            if key == "creationDate" {
                continue
            }
            switch value {
            case .string(let value): record[key] = value as NSString
            case .int(let value): record[key] = NSNumber(value: value)
            case .int64(let value): record[key] = NSNumber(value: value)
            case .date(let value): record[key] = value as NSDate
            case .uuid(let value): record[key] = value.uuidString.lowercased() as NSString
            case .bool(let value): record[key] = NSNumber(value: value)
            }
        }
        return record
    }

    func snapshot(from envelope: SystemCloudKitRecordEnvelope) throws -> CloudKitRecordSnapshot {
        let record = envelope.record
        guard record.recordID.zoneID == zoneID,
              !record.recordID.recordName.isEmpty,
              !record.recordType.isEmpty else {
            throw CoinLedgerDatabaseError.invalidRecord
        }
        var fields: [String: CloudKitRecordValue] = [:]
        for key in record.allKeys() {
            guard let value = record[key] else { continue }
            fields[key] = try cloudValue(value, field: key)
        }
        if record.recordType == CoinLedgerRecordType.monthlyAllowance {
            guard let creationDate = envelope.creationDate else {
                throw CoinLedgerDatabaseError.resultUnknown
            }
            fields["creationDate"] = .date(creationDate)
        }
        return CloudKitRecordSnapshot(
            recordType: record.recordType,
            recordName: record.recordID.recordName,
            changeTag: envelope.changeTag,
            fields: fields
        )
    }

    func cloudValue(_ value: Any, field: String) throws -> CloudKitRecordValue {
        if let date = value as? Date {
            return .date(date)
        }
        if let string = value as? String {
            if Self.uuidFields.contains(field) {
                guard let identifier = UUID(uuidString: string) else {
                    throw CoinLedgerDatabaseError.invalidRecord
                }
                return .uuid(identifier)
            }
            return .string(string)
        }
        if let number = value as? NSNumber {
            if Self.int64Fields.contains(field) {
                return .int64(number.int64Value)
            }
            if String(cString: number.objCType) == "c" {
                return .bool(number.boolValue)
            }
            let int64 = number.int64Value
            guard let integer = Int(exactly: int64) else {
                throw CoinLedgerDatabaseError.invalidRecord
            }
            return .int(integer)
        }
        throw CoinLedgerDatabaseError.invalidRecord
    }

    static func isMissingRecord(_ error: Error) -> Bool {
        (error as? CKError)?.code == .unknownItem
    }

    static func map(_ error: Error) -> CoinLedgerDatabaseError {
        if let error = error as? CoinLedgerDatabaseError { return error }
        guard let cloudError = error as? CKError else { return .unexpectedRequest }
        if cloudError.code == .partialFailure,
           let partial = cloudError.userInfo[CKPartialErrorsByItemIDKey]
            as? [AnyHashable: Error],
           let first = partial.values.first {
            return map(first)
        }
        switch cloudError.code {
        case .notAuthenticated, .accountTemporarilyUnavailable, .quotaExceeded:
            return .accountUnavailable
        case .networkUnavailable, .networkFailure, .serviceUnavailable,
             .requestRateLimited, .zoneBusy:
            return .serverUnavailable
        case .serverRecordChanged:
            return .serverRecordChanged
        case .serverResponseLost, .operationCancelled:
            return .resultUnknown
        case .unknownItem, .zoneNotFound, .userDeletedZone, .constraintViolation,
             .invalidArguments, .assetFileNotFound, .assetFileModified:
            return .invalidRecord
        case .incompatibleVersion:
            return .unsupportedSchema
        default:
            return .unexpectedRequest
        }
    }
}
