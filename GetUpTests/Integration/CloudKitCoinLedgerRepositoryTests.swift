import Foundation
import Testing
@testable import GetUp

@Suite("CloudKit coin ledger record mapping")
struct CloudKitCoinLedgerRecordMapperTests {
    @Test("Every ledger entity round-trips through its CloudKit record schema")
    func entityRoundTrip() throws {
        let mapper = CoinLedgerRecordMapper()

        for entity in try CloudKitLedgerTestFixtures.entities() {
            let record = try mapper.record(for: entity)
            let decoded = try mapper.entity(from: record)

            #expect(decoded == entity)
            #expect(record.schemaVersion == 1)
        }
    }

    @Test("CloudKit records contain no location or Family Controls identifiers")
    func privacySensitiveFieldsAreExcluded() throws {
        let mapper = CoinLedgerRecordMapper()
        let forbiddenFragments = [
            "latitude", "longitude", "coordinate", "accuracy",
            "applicationtoken", "categorytoken", "webdomaintoken",
        ]

        for entity in try CloudKitLedgerTestFixtures.entities() {
            let record = try mapper.record(for: entity)
            let normalizedKeys = record.fields.keys.map {
                $0.lowercased().replacingOccurrences(of: "_", with: "")
            }

            for fragment in forbiddenFragments {
                #expect(!normalizedKeys.contains { $0.contains(fragment) })
            }
        }
    }

    @Test("Record IDs are stable for mutable account and monthly allowance records")
    func mutableRecordIDsAreDeterministic() throws {
        let mapper = CoinLedgerRecordMapper()
        let firstAccount = try mapper.record(for: .coinAccount(
            try CloudKitLedgerTestFixtures.coinAccount(revision: 1)
        ))
        let secondAccount = try mapper.record(for: .coinAccount(
            try CloudKitLedgerTestFixtures.coinAccount(revision: 2)
        ))
        let firstAllowance = try mapper.record(for: .monthlyAllowance(
            try CloudKitLedgerTestFixtures.allowance(used: 0, reserved: 0)
        ))
        let secondAllowance = try mapper.record(for: .monthlyAllowance(
            try CloudKitLedgerTestFixtures.allowance(used: 1, reserved: 0)
        ))

        #expect(firstAccount.recordName == secondAccount.recordName)
        #expect(firstAccount.recordName == CoinLedgerRecordID.coinAccount)
        #expect(firstAllowance.recordName == secondAllowance.recordName)
        #expect(
            firstAllowance.recordName
                == CoinLedgerRecordID.allowance(monthID: CloudKitLedgerTestFixtures.monthID)
        )
    }

    @Test("Unknown record type and unsupported schema are rejected")
    func invalidRecordSchemaIsRejected() throws {
        let mapper = CoinLedgerRecordMapper()
        let unknown = CloudKitRecordSnapshot(
            recordType: "Unknown",
            recordName: "unknown",
            changeTag: nil,
            fields: ["schemaVersion": .int(1)]
        )
        let account = try mapper.record(for: .coinAccount(
            try CloudKitLedgerTestFixtures.coinAccount()
        ))
        let newer = account.replacingField("schemaVersion", with: .int(2))

        #expect(throws: CoinLedgerRecordMapperError.unsupportedRecordType("Unknown")) {
            _ = try mapper.entity(from: unknown)
        }
        #expect(throws: CoinLedgerRecordMapperError.unsupportedSchema(
            recordType: account.recordType,
            found: 2,
            supported: 1
        )) {
            _ = try mapper.entity(from: newer)
        }
    }
}

@Suite("CloudKit coin ledger repository")
struct CloudKitCoinLedgerRepositoryTests {
    @Test("Reservation updates mutable state and audit records in one atomic compare-and-swap")
    func reservationUsesOneAtomicModify() async throws {
        let mapper = CoinLedgerRecordMapper()
        let allowanceRecord = try CloudKitLedgerTestFixtures.record(
            for: .monthlyAllowance(try CloudKitLedgerTestFixtures.allowance()),
            changeTag: "allowance-v1",
            mapper: mapper
        )
        let database = ScriptedCoinLedgerDatabase(
            fetchResults: [.success([allowanceRecord])],
            modifyResults: [.success([])]
        )
        let repository = CloudKitCoinLedgerRepository(database: database, mapper: mapper)
        let request = CloudKitLedgerTestFixtures.reservationRequest()

        _ = try await repository.reserveMonthlyFree(request)

        let modify = try #require(await database.modifyRequests.first)
        #expect(await database.fetchRequests.count == 1)
        #expect(await database.modifyRequests.count == 1)
        #expect(modify.isAtomic)
        #expect(modify.savePolicy == .ifServerRecordUnchanged)
        #expect(modify.recordsToSave.map(\.recordName).contains(
            CoinLedgerRecordID.allowance(monthID: request.monthID)
        ))
        #expect(modify.recordsToSave.map(\.recordName).contains(
            CoinLedgerDeterministicID.reservation(commandID: request.commandID)
        ))
        #expect(modify.recordsToSave.map(\.recordName).contains(
            CoinLedgerRecordID.releaseCommand(commandID: request.commandID)
        ))
        #expect(
            modify.recordsToSave.first {
                $0.recordName == CoinLedgerRecordID.allowance(monthID: request.monthID)
            }?.changeTag == "allowance-v1"
        )
    }

    @Test("A change-tag conflict refetches server state and retries with identical deterministic IDs")
    func conflictRefetchesAndRetriesIdempotently() async throws {
        let mapper = CoinLedgerRecordMapper()
        let stale = try CloudKitLedgerTestFixtures.record(
            for: .monthlyAllowance(try CloudKitLedgerTestFixtures.allowance()),
            changeTag: "allowance-v1",
            mapper: mapper
        )
        let current = try CloudKitLedgerTestFixtures.record(
            for: .monthlyAllowance(
                try CloudKitLedgerTestFixtures.allowance(reserved: 1)
            ),
            changeTag: "allowance-v2",
            mapper: mapper
        )
        let database = ScriptedCoinLedgerDatabase(
            fetchResults: [.success([stale]), .success([current])],
            modifyResults: [.failure(.serverRecordChanged), .success([])]
        )
        let repository = CloudKitCoinLedgerRepository(
            database: database,
            mapper: mapper,
            conflictRetryLimit: 1
        )
        let request = CloudKitLedgerTestFixtures.reservationRequest()

        _ = try await repository.reserveMonthlyFree(request)

        let modifies = await database.modifyRequests
        #expect(await database.fetchRequests.count == 2)
        #expect(modifies.count == 2)
        #expect(Set(modifies.flatMap(\.recordsToSave).filter {
            $0.recordType == CoinLedgerRecordType.event
        }.map(\.recordName)) == [
            CoinLedgerDeterministicID.reservation(commandID: request.commandID),
        ])
        #expect(modifies.last?.recordsToSave.first {
            $0.recordName == CoinLedgerRecordID.allowance(monthID: request.monthID)
        }?.changeTag == "allowance-v2")
    }

    @Test("An unknown modify result refetches the same command before any retry")
    func unknownResultRefetchesStableCommand() async throws {
        let mapper = CoinLedgerRecordMapper()
        let allowance = try CloudKitLedgerTestFixtures.record(
            for: .monthlyAllowance(try CloudKitLedgerTestFixtures.allowance()),
            changeTag: "allowance-v1",
            mapper: mapper
        )
        let committedCommand = try CloudKitLedgerTestFixtures.record(
            for: .releaseCommand(
                try CloudKitLedgerTestFixtures.reservedCommand()
            ),
            changeTag: "command-v1",
            mapper: mapper
        )
        let database = ScriptedCoinLedgerDatabase(
            fetchResults: [.success([allowance]), .success([committedCommand])],
            modifyResults: [.failure(.resultUnknown)]
        )
        let repository = CloudKitCoinLedgerRepository(database: database, mapper: mapper)
        let request = CloudKitLedgerTestFixtures.reservationRequest()

        let result = try await repository.reserveMonthlyFree(request)

        #expect(result.command.commandID == request.commandID)
        #expect(result.command.state == .reserved)
        #expect(await database.modifyRequests.count == 1)
        #expect(await database.fetchRequests.last?.recordNames == [
            CoinLedgerRecordID.releaseCommand(commandID: request.commandID),
        ])
    }

    @Test("An unknown result without a command becomes reconciliation-required without a new command ID")
    func unknownResultWithoutCommandRequiresReconciliation() async throws {
        let mapper = CoinLedgerRecordMapper()
        let allowance = try CloudKitLedgerTestFixtures.record(
            for: .monthlyAllowance(try CloudKitLedgerTestFixtures.allowance()),
            changeTag: "allowance-v1",
            mapper: mapper
        )
        let database = ScriptedCoinLedgerDatabase(
            fetchResults: [.success([allowance]), .success([])],
            modifyResults: [.failure(.resultUnknown)]
        )
        let repository = CloudKitCoinLedgerRepository(database: database, mapper: mapper)
        let request = CloudKitLedgerTestFixtures.reservationRequest()

        await #expect(throws: CoinLedgerRepositoryError.reconciliationRequired(
            commandID: request.commandID
        )) {
            _ = try await repository.reserveMonthlyFree(request)
        }

        #expect(await database.modifyRequests.count == 1)
        #expect(await database.fetchRequests.last?.recordNames == [
            CoinLedgerRecordID.releaseCommand(commandID: request.commandID),
        ])
    }
}

actor ScriptedCoinLedgerDatabase: CoinLedgerCloudDatabase {
    private var fetchResults: [Result<[CloudKitRecordSnapshot], CoinLedgerDatabaseError>]
    private var modifyResults: [Result<[CloudKitRecordSnapshot], CoinLedgerDatabaseError>]
    private(set) var fetchRequests: [CoinLedgerFetchRequest] = []
    private(set) var modifyRequests: [CoinLedgerModifyRequest] = []

    init(
        fetchResults: [Result<[CloudKitRecordSnapshot], CoinLedgerDatabaseError>],
        modifyResults: [Result<[CloudKitRecordSnapshot], CoinLedgerDatabaseError>]
    ) {
        self.fetchResults = fetchResults
        self.modifyResults = modifyResults
    }

    func fetch(_ request: CoinLedgerFetchRequest) async throws -> [CloudKitRecordSnapshot] {
        fetchRequests.append(request)
        guard !fetchResults.isEmpty else {
            throw CocoaError(.coderInvalidValue)
        }
        return try fetchResults.removeFirst().get()
    }

    func modify(_ request: CoinLedgerModifyRequest) async throws -> [CloudKitRecordSnapshot] {
        modifyRequests.append(request)
        guard !modifyResults.isEmpty else {
            throw CocoaError(.coderInvalidValue)
        }
        return try modifyResults.removeFirst().get()
    }
}

enum CloudKitLedgerTestFixtures {
    static let epochID = UUID(uuidString: "00000000-0000-4000-8000-000000000501")!
    static let ruleID = UUID(uuidString: "00000000-0000-4000-8000-000000000502")!
    static let commandID = UUID(uuidString: "00000000-0000-4000-8000-000000000503")!
    static let monthID = "2026-09"
    static let now = Date(timeIntervalSince1970: 1_788_192_000)

    static func entities() throws -> [CoinLedgerRecordEntity] {
        [
            .ledgerEpoch(LedgerEpoch(
                epochID: epochID,
                createdAt: now,
                reason: .initialSetup,
                suppressedFreeMonthID: nil,
                disclosureVersion: 1
            )),
            .coinAccount(try coinAccount()),
            .monthlyAllowance(try allowance()),
            .purchaseGrant(try PurchaseGrant(
                transactionID: 42,
                environment: .sandbox,
                productID: "com.dxyn02.GetUp.coin.3",
                quantity: 3,
                purchaseDate: now,
                adjustedQuantity: 0
            )),
            .event(try CoinLedgerEvent(
                eventID: "free:\(monthID)",
                kind: .freeGrant,
                source: .monthlyFree,
                quantity: 2,
                relatedTransactionID: nil,
                relatedCommandID: nil,
                occurrenceID: nil,
                createdAt: now
            )),
            .releaseCommand(try reservedCommand()),
        ]
    }

    static func coinAccount(revision: Int = 1) throws -> CoinAccount {
        try CoinAccount(
            purchasedAvailable: 3,
            purchasedReserved: 0,
            revision: revision,
            updatedAt: now
        )
    }

    static func allowance(
        used: Int = 0,
        reserved: Int = 0
    ) throws -> MonthlyAllowance {
        try MonthlyAllowance(
            monthID: monthID,
            quota: 2,
            used: used,
            reserved: reserved,
            creationDate: now,
            updatedAt: now
        )
    }

    static func reservedCommand(
        commandID: UUID = commandID
    ) throws -> ReleaseCommand {
        try ReleaseCommand.requested(
            commandID: commandID,
            occurrenceID: "occurrence-1",
            ruleID: ruleID,
            requestedFrom: .shield,
            at: now
        ).transitioning(
            to: .reserved,
            fundingSource: .monthlyFree,
            at: now
        )
    }

    static func reservationRequest(
        commandID: UUID = commandID
    ) -> MonthlyFreeReservationRequest {
        MonthlyFreeReservationRequest(
            commandID: commandID,
            occurrenceID: "occurrence-1",
            ruleID: ruleID,
            ruleRevision: 3,
            monthID: monthID,
            ledgerEpochID: epochID,
            requestedFrom: .shield,
            requestedAt: now
        )
    }

    static func record(
        for entity: CoinLedgerRecordEntity,
        changeTag: String,
        mapper: CoinLedgerRecordMapper
    ) throws -> CloudKitRecordSnapshot {
        let record = try mapper.record(for: entity)
        return CloudKitRecordSnapshot(
            recordType: record.recordType,
            recordName: record.recordName,
            changeTag: changeTag,
            fields: record.fields
        )
    }
}
