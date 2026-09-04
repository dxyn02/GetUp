import Foundation
import Testing
@testable import GetUp

@Suite("CloudKit coin ledger record mapping")
struct CloudKitCoinLedgerRecordMapperTests {
    @Test("Occurrence claims round-trip held and released ownership", arguments: ["held", "released"])
    func claimRoundTrip(state: String) throws {
        let mapper = CoinLedgerRecordMapper()
        let claim = try ReleaseOccurrenceClaim(
            ledgerEpochID: CloudKitLedgerTestFixtures.epochID,
            occurrenceID: "occurrence-1",
            commandID: CloudKitLedgerTestFixtures.commandID,
            state: try #require(ReleaseOccurrenceClaim.State(rawValue: state)),
            updatedAt: CloudKitLedgerTestFixtures.now
        )
        let record = try mapper.record(for: .releaseOccurrenceClaim(claim))
        #expect(try mapper.entity(from: record) == .releaseOccurrenceClaim(claim))
        #expect(record.recordType == "ReleaseOccurrenceClaim")
        #expect(record.schemaVersion == 1)
        #expect(Set(record.fields.keys) == [
            "schemaVersion", "epochID", "occurrenceID", "commandID", "state", "updatedAt",
        ])
    }

    @Test("Claim identity depends on epoch and occurrence, never command or funding source")
    func claimIdentity() throws {
        let epoch = CloudKitLedgerTestFixtures.epochID
        let name = CoinLedgerRecordID.releaseOccurrenceClaim(
            ledgerEpochID: epoch, occurrenceID: "occurrence-1"
        )
        #expect(name == "release-claim:00000000-0000-4000-8000-000000000501:"
            + "8a18206abc262875a31e18ff1ecb49856497b9e9fd56493bdbe66bc03c93553e")
        #expect(name == CoinLedgerRecordID.releaseOccurrenceClaim(
            ledgerEpochID: epoch, occurrenceID: "occurrence-1"
        ))
        #expect(name != CoinLedgerRecordID.releaseOccurrenceClaim(
            ledgerEpochID: UUID(), occurrenceID: "occurrence-1"
        ))
        #expect(name != CoinLedgerRecordID.releaseOccurrenceClaim(
            ledgerEpochID: epoch, occurrenceID: "occurrence-2"
        ))
        let first = try claimRecord(commandID: CloudKitLedgerTestFixtures.commandID)
        let next = try claimRecord(commandID: UUID())
        #expect(first.recordName == next.recordName)
        #expect(!name.contains("occurrence-1"))
        #expect(name.utf8.count == "release-claim:".utf8.count + 36 + 1 + 64)
    }

    @Test("Claim decoding rejects missing, unknown, malformed, and mismatched fields")
    func invalidClaimRecords() throws {
        let mapper = CoinLedgerRecordMapper()
        let record = try claimRecord()
        for key in record.fields.keys {
            var fields = record.fields
            fields.removeValue(forKey: key)
            #expect(throws: (any Error).self) {
                try mapper.entity(from: CloudKitRecordSnapshot(
                    recordType: record.recordType, recordName: record.recordName,
                    changeTag: nil, fields: fields
                ))
            }
        }
        for invalid in [
            record.replacingField("schemaVersion", with: .int(2)),
            record.replacingField("state", with: .string("unknown")),
            record.replacingField("epochID", with: .string("not-a-uuid")),
            record.replacingField("occurrenceID", with: .string("")),
            record.replacingField("occurrenceID", with: .string("another-occurrence")),
            record.replacingField("updatedAt", with: .date(Date(timeIntervalSince1970: .infinity))),
            record.replacingField("latitude", with: .string("forbidden")),
        ] {
            #expect(throws: (any Error).self) { try mapper.entity(from: invalid) }
        }
    }

    @Test("A claim rejects empty occurrences and non-finite timestamps")
    func invalidClaimModel() throws {
        for (occurrence, date) in [
            ("", CloudKitLedgerTestFixtures.now),
            ("occurrence-1", Date(timeIntervalSince1970: .infinity)),
            ("occurrence-1", Date(timeIntervalSince1970: .nan)),
        ] {
            #expect(throws: ReleaseOccurrenceClaim.ValidationError.invalidValue) {
                try ReleaseOccurrenceClaim(
                    ledgerEpochID: CloudKitLedgerTestFixtures.epochID,
                    occurrenceID: occurrence, commandID: CloudKitLedgerTestFixtures.commandID,
                    state: .held, updatedAt: date
                )
            }
        }
    }

    private func claimRecord(
        commandID: UUID = CloudKitLedgerTestFixtures.commandID
    ) throws -> CloudKitRecordSnapshot {
        try CoinLedgerRecordMapper().record(for: .releaseOccurrenceClaim(
            try ReleaseOccurrenceClaim(
                ledgerEpochID: CloudKitLedgerTestFixtures.epochID,
                occurrenceID: "occurrence-1", commandID: commandID,
                state: .held, updatedAt: CloudKitLedgerTestFixtures.now
            )
        ))
    }

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
        let repository = CloudKitCoinLedgerRepository(database: database, mapper: mapper,
            verifyReservationCompatibility: { _ in true })
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
            conflictRetryLimit: 1,
            verifyReservationCompatibility: { _ in true }
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
            fetchResults: [.success([allowance]), .success([
                committedCommand, allowance,
                try CloudKitLedgerTestFixtures.claimRecord(),
                try CloudKitLedgerTestFixtures.reservationRecord(),
            ])],
            modifyResults: [.failure(.resultUnknown)]
        )
        let repository = CloudKitCoinLedgerRepository(database: database, mapper: mapper,
            verifyReservationCompatibility: { _ in true })
        let request = CloudKitLedgerTestFixtures.reservationRequest()

        let result = try await repository.reserveMonthlyFree(request)

        #expect(result.command.commandID == request.commandID)
        #expect(result.command.state == .reserved)
        #expect(await database.modifyRequests.count == 1)
        #expect(await database.fetchRequests.last?.recordNames.contains(
            CoinLedgerRecordID.releaseCommand(commandID: request.commandID)
        ) == true)
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
        let repository = CloudKitCoinLedgerRepository(database: database, mapper: mapper,
            verifyReservationCompatibility: { _ in true })
        let request = CloudKitLedgerTestFixtures.reservationRequest()

        await #expect(throws: CoinLedgerRepositoryError.reconciliationRequired(
            commandID: request.commandID
        )) {
            _ = try await repository.reserveMonthlyFree(request)
        }

        #expect(await database.modifyRequests.count == 1)
        #expect(await database.fetchRequests.last?.recordNames.contains(
            CoinLedgerRecordID.releaseCommand(commandID: request.commandID)
        ) == true)
    }
}

@Suite("Occurrence claim atomic repository")
struct OccurrenceClaimRepositoryTests {
    @Test("Independent app and Shield repositories reserve one occurrence once in 100 requests", arguments: [0, 2])
    func concurrentClaim(freeUsed: Int) async throws {
        let database = try ClaimDatabase(freeUsed: freeUsed)
        let results = await withTaskGroup(of: Bool.self) { group in
            for index in 0..<100 {
                group.addTask {
                    let repository = self.repository(database)
                    do {
                        let request = self.purchased(
                            commandID: UUID(), source: index.isMultiple(of: 2) ? .app : .shield
                        )
                        if index.isMultiple(of: 2) {
                            _ = try await repository.reserveMonthlyFree(MonthlyFreeReservationRequest(
                                commandID: request.commandID, occurrenceID: request.occurrenceID,
                                ruleID: request.ruleID, ruleRevision: request.ruleRevision,
                                monthID: CloudKitLedgerTestFixtures.monthID,
                                ledgerEpochID: request.ledgerEpochID, requestedFrom: request.requestedFrom,
                                requestedAt: request.requestedAt
                            ))
                        } else {
                            _ = try await repository.reservePurchasedCoin(request)
                        }
                        return true
                    } catch { return false }
                }
            }
            var count = 0
            for await success in group where success { count += 1 }
            return count
        }
        #expect(results == 1)
        #expect(await database.savedCommands == 1)
        #expect(await database.accountReserved == (freeUsed == 2 ? 1 : 0))
        #expect(await database.freeReserved == (freeUsed == 2 ? 0 : 1))
        let write = try #require(await database.modifications.first)
        #expect(write.recordsToSave.contains { $0.recordType == "ReleaseOccurrenceClaim" })
        #expect(write.recordsToSave.contains { $0.recordType == "MonthlyAllowance" })
    }

    @Test("Compensation releases ownership atomically and an old retry cannot release a new owner")
    func compensationAndRetry() async throws {
        let database = try ClaimDatabase(freeUsed: 2)
        let repository = repository(database)
        let first = purchased()
        _ = try await repository.reservePurchasedCoin(first)
        _ = try await repository.compensateRelease(commandID: first.commandID, at: Self.now)
        #expect(await database.accountReserved == 0)
        #expect(await database.claimState == .released)
        let next = purchased(commandID: UUID())
        _ = try await repository.reservePurchasedCoin(next)
        _ = try await repository.compensateRelease(commandID: first.commandID, at: Self.now)
        #expect(await database.accountReserved == 1)
        #expect(await database.claimOwner == next.commandID)
        #expect(await database.claimState == .held)
    }

    @Test("Committed ownership blocks a fresh command and cross-surface retry preserves audit source")
    func commitAndReplay() async throws {
        let database = try ClaimDatabase()
        let repository = repository(database)
        let request = purchased()
        _ = try await repository.reservePurchasedCoin(request)
        _ = try await repository.markReleaseApplied(commandID: request.commandID, at: Self.now)
        _ = try await repository.commitRelease(commandID: request.commandID, at: Self.now)
        let replay = try await repository.reservePurchasedCoin(purchased(
            commandID: request.commandID, source: .shield
        ))
        #expect(replay.command.requestedFrom == .app)
        #expect(replay.command.state == .committed)
        await #expect(throws: CoinLedgerRepositoryError.reconciliationRequired(commandID: request.commandID)) {
            try await repository.reservePurchasedCoin(purchased(commandID: UUID()))
        }
        #expect(await database.claimState == .held)
    }

    @Test("Unknown outcomes retain ownership and resolve the same command without another reservation")
    func unknownResult() async throws {
        let database = try ClaimDatabase()
        await database.loseNextResponse()
        let repository = repository(database)
        let request = purchased()
        let result = try await repository.reservePurchasedCoin(request)
        #expect(result.command.commandID == request.commandID)
        #expect(await database.savedCommands == 1)
        #expect(await database.freeReserved == 1)
        #expect(await database.claimState == .held)
    }

    @Test("Unverified compatibility and wrong epochs cannot mutate the ledger")
    func compatibilityAndEpoch() async throws {
        let database = try ClaimDatabase()
        await #expect(throws: CoinLedgerRepositoryError.ledgerNotCurrent) {
            try await CloudKitCoinLedgerRepository(database: database).reservePurchasedCoin(purchased())
        }
        await #expect(throws: CoinLedgerRepositoryError.ledgerEpochMismatch) {
            try await repository(database).reservePurchasedCoin(purchased(epochID: UUID()))
        }
        #expect(await database.modifications.isEmpty)
    }

    @Test("A legacy command with no claim fails closed even in an explicitly permitted fixture")
    func legacyCommand() async throws {
        let database = try ClaimDatabase()
        let request = purchased()
        try await database.insert(.releaseCommand(try .requested(
            commandID: request.commandID, occurrenceID: request.occurrenceID,
            ruleID: request.ruleID, requestedFrom: .app, at: Self.now
        ).transitioning(to: .reserved, fundingSource: .monthlyFree, at: Self.now)))
        await #expect(throws: CoinLedgerRepositoryError.reconciliationRequired(commandID: request.commandID)) {
            try await repository(database).reservePurchasedCoin(request)
        }
        #expect(await database.modifications.isEmpty)
    }

    private static let now = CloudKitLedgerTestFixtures.now

    @Test("A free balance restored during a purchased CAS conflict is selected on retry")
    func freeRestoredDuringConflict() async throws {
        let database = try ClaimDatabase(freeUsed: 2)
        await database.restoreFreeOnNextModify()
        let result = try await repository(database).reservePurchasedCoin(purchased())
        #expect(result.command.fundingSource == .monthlyFree)
        #expect(await database.accountReserved == 0)
        #expect(await database.freeReserved == 1)
    }

    @Test("An epoch replacement during CAS prevents the old request from reserving")
    func epochChangesDuringConflict() async throws {
        let database = try ClaimDatabase()
        await database.replaceEpochOnNextModify()
        await #expect(throws: CoinLedgerRepositoryError.ledgerEpochMismatch) {
            try await repository(database).reservePurchasedCoin(purchased())
        }
        #expect(await database.modifications.isEmpty)
        #expect(await database.freeReserved == 0)
    }

    @Test("An unknown write with no confirmed command is not retried")
    func unknownWithoutCommit() async throws {
        let database = try ClaimDatabase()
        await database.failNextModify(.resultUnknown)
        let request = purchased()
        await #expect(throws: CoinLedgerRepositoryError.reconciliationRequired(commandID: request.commandID)) {
            try await repository(database).reservePurchasedCoin(request)
        }
        #expect(await database.modifications.isEmpty)
        #expect(await database.modifyAttempts == 1)
    }

    @Test("A failed read after an unknown reservation remains reconciliation-required")
    func unknownReadFailure() async throws {
        let database = try ClaimDatabase()
        await database.loseNextResponse(failRead: true)
        let request = purchased()
        await #expect(throws: CoinLedgerRepositoryError.reconciliationRequired(commandID: request.commandID)) {
            try await repository(database).reservePurchasedCoin(request)
        }
        #expect(await database.claimState == .held)
        #expect(await database.savedCommands == 1)
        let replay = try await repository(database).reservePurchasedCoin(request)
        #expect(replay.command.commandID == request.commandID)
        #expect(await database.modifyAttempts == 1)
    }

    @Test("A failed compensation preserves both reservation and ownership")
    func failedCompensation() async throws {
        let database = try ClaimDatabase()
        let repository = repository(database)
        let request = purchased()
        _ = try await repository.reservePurchasedCoin(request)
        await database.failNextModify(.serverUnavailable)
        await #expect(throws: CoinLedgerRepositoryError.database(.serverUnavailable)) {
            try await repository.compensateRelease(commandID: request.commandID, at: Self.now)
        }
        #expect(await database.freeReserved == 1)
        #expect(await database.claimState == .held)
        await database.loseNextResponse()
        let compensated = try await repository.compensateRelease(commandID: request.commandID, at: Self.now)
        #expect(compensated.state == .compensated)
        #expect(await database.freeReserved == 0)
        #expect(await database.claimState == .released)
        let last = try #require(await database.modifications.last)
        #expect(Set(last.recordsToSave.map(\.recordType)) == [
            "ReleaseCommand", "ReleaseOccurrenceClaim", "MonthlyAllowance", "CoinLedgerEvent", "LedgerEpoch",
        ])
    }

    @Test("Different occurrences acquire independent claims")
    func independentOccurrences() async throws {
        let database = try ClaimDatabase()
        let first = try await repository(database).reservePurchasedCoin(purchased())
        let second = try await repository(database).reservePurchasedCoin(purchased(
            commandID: UUID(), occurrenceID: "occurrence-2"
        ))
        #expect(first.command.occurrenceID != second.command.occurrenceID)
        #expect(await database.savedCommands == 2)
        #expect(await database.freeReserved == 2)
    }

    private func repository(_ database: ClaimDatabase) -> CloudKitCoinLedgerRepository {
        CloudKitCoinLedgerRepository(database: database, verifyReservationCompatibility: { _ in true })
    }

    private func purchased(
        commandID: UUID = CloudKitLedgerTestFixtures.commandID,
        source: ReleaseRequestSource = .app,
        epochID: UUID = CloudKitLedgerTestFixtures.epochID,
        occurrenceID: String = "occurrence-1"
    ) -> PurchasedCoinReservationRequest {
        PurchasedCoinReservationRequest(
            commandID: commandID, occurrenceID: occurrenceID,
            ruleID: CloudKitLedgerTestFixtures.ruleID, ruleRevision: 3,
            ledgerEpochID: epochID, requestedFrom: source, requestedAt: Self.now
        )
    }
}

private actor ClaimDatabase: CoinLedgerCloudDatabase {
    private var records: [String: CloudKitRecordSnapshot] = [:]
    private var revision = 0
    private var loseResponse = false
    private var failReadAfterLostResponse = false
    private var failFetch = false
    private var nextFailure: CoinLedgerDatabaseError?
    private var restoreFree = false
    private var replaceEpoch = false
    private(set) var modifyAttempts = 0
    private(set) var modifications: [CoinLedgerModifyRequest] = []

    init(freeUsed: Int = 0) throws {
        let mapper = CoinLedgerRecordMapper()
        let values: [CoinLedgerRecordEntity] = [
            .ledgerEpoch(LedgerEpoch(
                epochID: CloudKitLedgerTestFixtures.epochID,
                createdAt: CloudKitLedgerTestFixtures.now, reason: .initialSetup,
                suppressedFreeMonthID: nil, disclosureVersion: 1
            )),
            .coinAccount(try CloudKitLedgerTestFixtures.coinAccount()),
            .monthlyAllowance(try CloudKitLedgerTestFixtures.allowance(used: freeUsed)),
        ]
        for value in values {
            let record = try mapper.record(for: value)
            records[record.recordName] = CloudKitRecordSnapshot(
                recordType: record.recordType, recordName: record.recordName,
                changeTag: "initial", fields: record.fields
            )
        }
    }

    var savedCommands: Int { records.values.filter { $0.recordType == "ReleaseCommand" }.count }
    var accountReserved: Int { integer("purchasedReserved", type: "CoinAccount") }
    var freeReserved: Int { integer("reserved", type: "MonthlyAllowance") }
    var claimState: ReleaseOccurrenceClaim.State? {
        guard case .string(let value) = claim?.fields["state"] else { return nil }
        return .init(rawValue: value)
    }
    var claimOwner: UUID? {
        guard case .uuid(let value) = claim?.fields["commandID"] else { return nil }
        return value
    }
    private var claim: CloudKitRecordSnapshot? {
        records.values.first { $0.recordType == "ReleaseOccurrenceClaim" }
    }
    private func integer(_ key: String, type: String) -> Int {
        guard case .int(let value) = records.values.first(where: { $0.recordType == type })?.fields[key]
        else { return -1 }
        return value
    }
    func insert(_ entity: CoinLedgerRecordEntity) throws {
        let record = try CoinLedgerRecordMapper().record(for: entity)
        revision += 1
        records[record.recordName] = CloudKitRecordSnapshot(
            recordType: record.recordType, recordName: record.recordName,
            changeTag: String(revision), fields: record.fields
        )
    }
    func loseNextResponse(failRead: Bool = false) {
        loseResponse = true
        failReadAfterLostResponse = failRead
    }
    func failNextModify(_ error: CoinLedgerDatabaseError) { nextFailure = error }
    func restoreFreeOnNextModify() { restoreFree = true }
    func replaceEpochOnNextModify() { replaceEpoch = true }
    func fetch(_ request: CoinLedgerFetchRequest) async throws -> [CloudKitRecordSnapshot] {
        if failFetch {
            failFetch = false
            throw CoinLedgerDatabaseError.serverUnavailable
        }
        let snapshot = request.recordNames.compactMap { records[$0] }
        await Task.yield()
        return snapshot
    }
    func modify(_ request: CoinLedgerModifyRequest) throws -> [CloudKitRecordSnapshot] {
        modifyAttempts += 1
        if let error = nextFailure {
            nextFailure = nil
            throw error
        }
        if restoreFree {
            restoreFree = false
            try insert(.monthlyAllowance(CloudKitLedgerTestFixtures.allowance()))
        }
        if replaceEpoch {
            replaceEpoch = false
            try insert(.ledgerEpoch(LedgerEpoch(
                epochID: UUID(), createdAt: CloudKitLedgerTestFixtures.now,
                reason: .initialSetup, suppressedFreeMonthID: nil, disclosureVersion: 1
            )))
        }
        guard request.isAtomic, request.savePolicy == .ifServerRecordUnchanged,
              request.recordNamesToDelete.isEmpty else { throw CoinLedgerDatabaseError.unexpectedRequest }
        for record in request.recordsToSave {
            guard records[record.recordName]?.changeTag == record.changeTag else {
                throw CoinLedgerDatabaseError.serverRecordChanged
            }
        }
        revision += 1
        let saved = request.recordsToSave.map { record in
            CloudKitRecordSnapshot(recordType: record.recordType, recordName: record.recordName,
                changeTag: String(revision), fields: record.fields)
        }
        for record in saved { records[record.recordName] = record }
        modifications.append(request)
        if loseResponse {
            loseResponse = false
            failFetch = failReadAfterLostResponse
            failReadAfterLostResponse = false
            throw CoinLedgerDatabaseError.resultUnknown
        }
        return saved
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
        var result = try fetchResults.removeFirst().get()
        // These legacy scripts model a confirmed fixture epoch; the stateful claim fake does not inject it.
        if request.recordNames.contains(CoinLedgerRecordID.ledgerEpoch),
           !result.contains(where: { $0.recordName == CoinLedgerRecordID.ledgerEpoch }) {
            result.append(try CloudKitLedgerTestFixtures.record(
                for: .ledgerEpoch(LedgerEpoch(
                    epochID: CloudKitLedgerTestFixtures.epochID,
                    createdAt: CloudKitLedgerTestFixtures.now, reason: .initialSetup,
                    suppressedFreeMonthID: nil, disclosureVersion: 1
                )), changeTag: "epoch-fixture", mapper: CoinLedgerRecordMapper()
            ))
        }
        return result
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
    static func claimRecord() throws -> CloudKitRecordSnapshot {
        try record(for: .releaseOccurrenceClaim(ReleaseOccurrenceClaim(
            ledgerEpochID: epochID, occurrenceID: "occurrence-1", commandID: commandID,
            state: .held, updatedAt: now
        )), changeTag: "claim-fixture", mapper: CoinLedgerRecordMapper())
    }

    static func reservationRecord() throws -> CloudKitRecordSnapshot {
        try CoinLedgerRecordMapper().record(for: .event(CoinLedgerEvent(
            eventID: CoinLedgerDeterministicID.reservation(commandID: commandID),
            kind: .reservation, source: .monthlyFree, quantity: 1,
            relatedTransactionID: nil, relatedCommandID: commandID,
            occurrenceID: "occurrence-1", createdAt: now
        )))
    }

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
