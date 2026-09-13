import Foundation
import Testing
@testable import GetUp

@Suite("Reservation compatibility migration provider")
struct ReservationCompatibilityMigrationProviderTests {
    @Test("Migration remains closed without explicit legacy-writer retirement approval")
    func migrationRequiresExplicitApproval() async throws {
        let store = try ReservationMigrationDatabaseFake(records: Self.baseRecords())
        let provider = Self.provider(store)

        await #expect(throws: ReservationCompatibilityMigrationError.authorizationRequired) {
            _ = try await provider.migrate(epochID: Self.epochID, authorization: nil)
        }

        #expect(try await provider.verifyReservationCompatibility(epochID: Self.epochID) == false)
        #expect(await store.modifyRequests.isEmpty)
        #expect(await store.deletedRecordNames.isEmpty)
    }

    @Test("An unresolved claimless command stops migration without reset or deletion")
    func unresolvedLegacyCommandStopsMigration() async throws {
        let command = try Self.command(state: .reserved)
        let store = try ReservationMigrationDatabaseFake(
            records: Self.baseRecords() + [Self.record(for: .releaseCommand(command))]
        )
        let provider = Self.provider(store)

        await #expect(throws: ReservationCompatibilityMigrationError.unresolvedCommand(
            commandID: command.commandID
        )) {
            _ = try await provider.migrate(
                epochID: Self.epochID,
                authorization: Self.authorization
            )
        }

        #expect(try await provider.verifyReservationCompatibility(epochID: Self.epochID) == false)
        #expect(await store.deletedRecordNames.isEmpty)
        #expect(await store.epochID == Self.epochID)
    }

    @Test("Interrupted migration remains closed and completes on retry")
    func interruptedMigrationRetries() async throws {
        let command = try Self.command(state: .committed)
        let store = try ReservationMigrationDatabaseFake(
            records: Self.baseRecords() + [Self.record(for: .releaseCommand(command))],
            failureOnModifyCall: 2
        )
        let provider = Self.provider(store)

        await #expect(throws: ReservationCompatibilityMigrationError.database(.serverUnavailable)) {
            _ = try await provider.migrate(
                epochID: Self.epochID,
                authorization: Self.authorization
            )
        }
        #expect(try await provider.verifyReservationCompatibility(epochID: Self.epochID) == false)

        let result = try await provider.migrate(
            epochID: Self.epochID,
            authorization: Self.authorization
        )

        #expect(result == .completed(epochID: Self.epochID))
        #expect(try await provider.verifyReservationCompatibility(epochID: Self.epochID))
        #expect(await store.hasCompatibilityStamp(commandID: command.commandID))
        #expect(await store.claim(commandID: command.commandID)?.state == .held)
        #expect(await store.epochID == Self.epochID)
        #expect(await store.deletedRecordNames.isEmpty)
    }

    @Test("A claim-aware in-flight command can be stamped and migration can finish")
    func claimAwareInFlightCommandCanMigrate() async throws {
        let command = try Self.command(state: .applied)
        let claim = try ReleaseOccurrenceClaim(
            ledgerEpochID: Self.epochID,
            occurrenceID: command.occurrenceID,
            commandID: command.commandID,
            state: .held,
            updatedAt: Self.now
        )
        let store = try ReservationMigrationDatabaseFake(records: Self.baseRecords() + [
            Self.record(for: .releaseCommand(command)),
            Self.record(for: .releaseOccurrenceClaim(claim)),
        ])
        let provider = Self.provider(store)

        _ = try await provider.migrate(
            epochID: Self.epochID,
            authorization: Self.authorization
        )

        #expect(try await provider.verifyReservationCompatibility(epochID: Self.epochID))
        #expect(await store.hasCompatibilityStamp(commandID: command.commandID))
    }

    @Test("A claimless old writer command added after completion closes the gate")
    func oldWriterCoexistenceClosesCompletedMigration() async throws {
        let store = try ReservationMigrationDatabaseFake(records: Self.baseRecords())
        let provider = Self.provider(store)
        _ = try await provider.migrate(
            epochID: Self.epochID,
            authorization: Self.authorization
        )
        #expect(try await provider.verifyReservationCompatibility(epochID: Self.epochID))

        let oldWriterCommand = try Self.command(
            commandID: UUID(uuidString: "00000000-0000-4000-8000-000000000812")!,
            occurrenceID: "legacy-late-occurrence",
            state: .committed
        )
        try await store.insert(Self.record(for: .releaseCommand(oldWriterCommand)))

        #expect(try await provider.verifyReservationCompatibility(epochID: Self.epochID) == false)
    }

    @Test("Repository reservation writes a protocol stamp atomically")
    func repositoryWritesCompatibilityStamp() async throws {
        let store = try ReservationMigrationDatabaseFake(records: Self.reservationRecords())
        let repository = CloudKitCoinLedgerRepository(
            database: store,
            verifyReservationCompatibility: { _ in true }
        )
        let commandID = UUID(uuidString: "00000000-0000-4000-8000-000000000813")!

        _ = try await repository.reserveMonthlyFree(MonthlyFreeReservationRequest(
            commandID: commandID,
            occurrenceID: "new-occurrence",
            ruleID: Self.ruleID,
            ruleRevision: 1,
            monthID: "2026-09",
            ledgerEpochID: Self.epochID,
            requestedFrom: .app,
            requestedAt: Self.now
        ))

        #expect(await store.hasCompatibilityStamp(commandID: commandID))
        let request = try #require(await store.modifyRequests.last)
        #expect(request.recordsToSave.contains {
            $0.recordName == CoinLedgerRecordID.reservationCompatibilityStamp(commandID: commandID)
        })
    }
}

private extension ReservationCompatibilityMigrationProviderTests {
    static let epochID = UUID(uuidString: "00000000-0000-4000-8000-000000000801")!
    static let ruleID = UUID(uuidString: "00000000-0000-4000-8000-000000000802")!
    static let commandID = UUID(uuidString: "00000000-0000-4000-8000-000000000803")!
    static let now = Date(timeIntervalSince1970: 1_788_192_000)
    static let authorization = ReservationMigrationAuthorization(
        epochID: epochID,
        legacyWritersRetiredAt: now,
        evidenceVersion: 1
    )

    static func provider(
        _ store: ReservationMigrationDatabaseFake
    ) -> ReservationCompatibilityMigrationProvider {
        ReservationCompatibilityMigrationProvider(
            database: store,
            fetchRemoteRecords: { await store.allRecords() },
            now: { now }
        )
    }

    static func baseRecords() throws -> [CloudKitRecordSnapshot] {
        [try record(for: .ledgerEpoch(LedgerEpoch(
            epochID: epochID,
            createdAt: now,
            reason: .initialSetup,
            suppressedFreeMonthID: nil,
            disclosureVersion: 1
        )))]
    }

    static func reservationRecords() throws -> [CloudKitRecordSnapshot] {
        try baseRecords() + [
            record(for: .coinAccount(CoinAccount(
                purchasedAvailable: 0,
                purchasedReserved: 0,
                revision: 0,
                updatedAt: now
            ))),
            record(for: .monthlyAllowance(MonthlyAllowance(
                monthID: "2026-09",
                quota: 2,
                used: 0,
                reserved: 0,
                creationDate: now,
                updatedAt: now
            ))),
        ]
    }

    static func command(
        commandID: UUID = commandID,
        occurrenceID: String = "legacy-occurrence",
        state: ReleaseCommandState
    ) throws -> ReleaseCommand {
        var value = try ReleaseCommand.requested(
            commandID: commandID,
            occurrenceID: occurrenceID,
            ruleID: ruleID,
            requestedFrom: .app,
            at: now
        )
        switch state {
        case .requested:
            return value
        case .rejected:
            return try value.transitioning(to: .rejected, at: now)
        case .reserved:
            return try value.transitioning(to: .reserved, fundingSource: .monthlyFree, at: now)
        case .applied:
            value = try value.transitioning(to: .reserved, fundingSource: .monthlyFree, at: now)
            return try value.transitioning(to: .applied, at: now)
        case .committed:
            value = try value.transitioning(to: .reserved, fundingSource: .monthlyFree, at: now)
            value = try value.transitioning(to: .applied, at: now)
            return try value.transitioning(to: .committed, at: now)
        case .compensating:
            value = try value.transitioning(to: .reserved, fundingSource: .monthlyFree, at: now)
            return try value.transitioning(to: .compensating, at: now)
        case .compensated:
            value = try value.transitioning(to: .reserved, fundingSource: .monthlyFree, at: now)
            value = try value.transitioning(to: .compensating, at: now)
            return try value.transitioning(to: .compensated, at: now)
        case .reconciliationRequired:
            return try value.transitioning(to: .reconciliationRequired, at: now)
        }
    }

    static func record(for entity: CoinLedgerRecordEntity) throws -> CloudKitRecordSnapshot {
        try CoinLedgerRecordMapper().record(for: entity)
    }
}

private actor ReservationMigrationDatabaseFake: CoinLedgerCloudDatabase {
    private var records: [String: CloudKitRecordSnapshot]
    private var revision = 0
    private var failureOnModifyCall: Int?
    private(set) var modifyRequests: [CoinLedgerModifyRequest] = []
    private(set) var deletedRecordNames: [String] = []

    init(
        records: [CloudKitRecordSnapshot],
        failureOnModifyCall: Int? = nil
    ) throws {
        self.records = Dictionary(uniqueKeysWithValues: records.enumerated().map { index, record in
            (record.recordName, record.withChangeTag("initial-\(index)"))
        })
        self.failureOnModifyCall = failureOnModifyCall
    }

    var epochID: UUID? {
        guard case .uuid(let value) = records[CoinLedgerRecordID.ledgerEpoch]?.fields["epochID"] else {
            return nil
        }
        return value
    }

    func allRecords() -> [CloudKitRecordSnapshot] {
        records.values.sorted { $0.recordName < $1.recordName }
    }

    func insert(_ record: CloudKitRecordSnapshot) {
        revision += 1
        records[record.recordName] = record.withChangeTag("external-\(revision)")
    }

    func hasCompatibilityStamp(commandID: UUID) -> Bool {
        records[CoinLedgerRecordID.reservationCompatibilityStamp(commandID: commandID)] != nil
    }

    func claim(commandID: UUID) -> ReleaseOccurrenceClaim? {
        records.values.compactMap { record -> ReleaseOccurrenceClaim? in
            guard record.recordType == CoinLedgerRecordType.releaseOccurrenceClaim,
                  case .releaseOccurrenceClaim(let claim) = try? CoinLedgerRecordMapper().entity(from: record),
                  claim.commandID == commandID else { return nil }
            return claim
        }.first
    }

    func fetch(_ request: CoinLedgerFetchRequest) async throws -> [CloudKitRecordSnapshot] {
        request.recordNames.compactMap { records[$0] }
    }

    func modify(_ request: CoinLedgerModifyRequest) async throws -> [CloudKitRecordSnapshot] {
        modifyRequests.append(request)
        if failureOnModifyCall == modifyRequests.count {
            failureOnModifyCall = nil
            throw CoinLedgerDatabaseError.serverUnavailable
        }
        guard request.isAtomic, request.recordNamesToDelete.isEmpty else {
            deletedRecordNames.append(contentsOf: request.recordNamesToDelete)
            throw CoinLedgerDatabaseError.unexpectedRequest
        }
        for proposed in request.recordsToSave {
            if let existing = records[proposed.recordName] {
                guard existing.changeTag == proposed.changeTag else {
                    throw CoinLedgerDatabaseError.serverRecordChanged
                }
            } else if proposed.changeTag != nil {
                throw CoinLedgerDatabaseError.serverRecordChanged
            }
        }
        revision += 1
        let saved = request.recordsToSave.map { $0.withChangeTag("save-\(revision)") }
        for record in saved { records[record.recordName] = record }
        return saved
    }
}

private extension CloudKitRecordSnapshot {
    func withChangeTag(_ changeTag: String) -> Self {
        Self(
            recordType: recordType,
            recordName: recordName,
            changeTag: changeTag,
            fields: fields
        )
    }
}
