import Foundation
import Testing
@testable import GetUp

@Suite("Monthly allowance acceptance", .serialized)
struct MonthlyAllowanceAcceptanceTests {
    private static let deviceCount = 100

    @Test("One hundred devices converge on one monthly allowance record")
    func concurrentDevicesCreateOneAllowance() async throws {
        let database = MonthlyAllowanceAcceptanceDatabase()
        let request = MonthlyAllowanceCreationRequest(
            monthID: MonthlyAllowancePolicy.monthID(containing: Date()),
            epochID: CloudKitLedgerTestFixtures.epochID,
            trigger: .appForeground
        )

        let allowances = try await withThrowingTaskGroup(
            of: MonthlyAllowance.self,
            returning: [MonthlyAllowance].self
        ) { group in
            for _ in 0..<Self.deviceCount {
                group.addTask {
                    let repository = CloudKitCoinLedgerRepository(
                        database: database,
                        conflictRetryLimit: 1
                    )
                    return try await repository.createAllowanceIfNeeded(request)
                }
            }

            var values: [MonthlyAllowance] = []
            for try await allowance in group {
                values.append(allowance)
            }
            return values
        }

        #expect(allowances.count == Self.deviceCount)
        #expect(allowances.allSatisfy { $0.monthID == request.monthID })
        #expect(allowances.allSatisfy { $0.quota == 2 && $0.available == 2 })
        #expect(await database.recordCount(type: "MonthlyAllowance") == 1)
        #expect(await database.recordCount(type: "CoinLedgerEvent") == 1)
        #expect(await database.successfulModifyCount == 1)
        let conflictCount = await database.conflictCount

        print(
            "MONTHLY_ALLOWANCE_ACCEPTANCE_RESULT "
                + "scenario=same_record_multi_device samples=\(Self.deviceCount) "
                + "allowance_records=1 free_grant_records=1 "
                + "cas_conflicts=\(conflictCount) result=PASS"
        )
    }

    @Test("A server allowance created outside its Seoul month is rejected")
    func serverCreationMonthMismatchIsRejected() async throws {
        let mapper = CoinLedgerRecordMapper()
        let invalidAllowance = try MonthlyAllowance(
            monthID: "2026-09",
            quota: 2,
            used: 0,
            reserved: 0,
            creationDate: try #require(Self.date("2026-08-31T14:59:59Z")),
            updatedAt: try #require(Self.date("2026-09-01T00:00:00Z"))
        )
        let record = try CloudKitLedgerTestFixtures.record(
            for: .monthlyAllowance(invalidAllowance),
            changeTag: "server-invalid-month",
            mapper: mapper
        )
        let database = ScriptedCoinLedgerDatabase(
            fetchResults: [.success([record])],
            modifyResults: []
        )
        let repository = CloudKitCoinLedgerRepository(database: database, mapper: mapper)

        await #expect(throws: CoinLedgerRepositoryError.database(.invalidRecord)) {
            try await repository.createAllowanceIfNeeded(
                MonthlyAllowanceCreationRequest(
                    monthID: "2026-09",
                    epochID: CloudKitLedgerTestFixtures.epochID,
                    trigger: .appForeground
                )
            )
        }
        #expect(await database.modifyRequests.isEmpty)

        print(
            "MONTHLY_ALLOWANCE_ACCEPTANCE_RESULT "
                + "scenario=server_creation_month_mismatch samples=1 rejected=1 result=PASS"
        )
    }

    @Test("Account unavailability writes nothing and succeeds only after an explicit retry")
    func accountUnavailableRequiresExplicitRetry() async throws {
        let database = ScriptedCoinLedgerDatabase(
            fetchResults: [
                .failure(.accountUnavailable),
                .success([]),
            ],
            modifyResults: [.success([])]
        )
        let repository = CloudKitCoinLedgerRepository(database: database)
        let request = MonthlyAllowanceCreationRequest(
            monthID: MonthlyAllowancePolicy.monthID(containing: Date()),
            epochID: CloudKitLedgerTestFixtures.epochID,
            trigger: .appForeground
        )

        await #expect(throws: CoinLedgerRepositoryError.database(.accountUnavailable)) {
            try await repository.createAllowanceIfNeeded(request)
        }
        #expect(await database.fetchRequests.count == 1)
        #expect(await database.modifyRequests.isEmpty)

        let allowance = try await repository.createAllowanceIfNeeded(request)

        #expect(allowance.monthID == request.monthID)
        #expect(allowance.available == 2)
        #expect(await database.fetchRequests.count == 2)
        #expect(await database.modifyRequests.count == 1)

        print(
            "MONTHLY_ALLOWANCE_ACCEPTANCE_RESULT "
                + "scenario=account_unavailable attempts=2 blocked_writes=1 "
                + "successful_explicit_retries=1 result=PASS"
        )
    }

    private static func date(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}

private actor MonthlyAllowanceAcceptanceDatabase: CoinLedgerCloudDatabase {
    private var records: [String: CloudKitRecordSnapshot] = [:]
    private var revision = 0
    private(set) var successfulModifyCount = 0
    private(set) var conflictCount = 0

    func fetch(_ request: CoinLedgerFetchRequest) async -> [CloudKitRecordSnapshot] {
        let result = request.recordNames.compactMap { records[$0] }
        await Task.yield()
        return result
    }

    func modify(_ request: CoinLedgerModifyRequest) throws -> [CloudKitRecordSnapshot] {
        guard request.isAtomic,
              request.savePolicy == .ifServerRecordUnchanged,
              request.recordNamesToDelete.isEmpty
        else {
            throw CoinLedgerDatabaseError.unexpectedRequest
        }
        for record in request.recordsToSave where records[record.recordName]?.changeTag != record.changeTag {
            conflictCount += 1
            throw CoinLedgerDatabaseError.serverRecordChanged
        }

        revision += 1
        let saved = request.recordsToSave.map { record in
            CloudKitRecordSnapshot(
                recordType: record.recordType,
                recordName: record.recordName,
                changeTag: String(revision),
                fields: record.fields
            )
        }
        for record in saved {
            records[record.recordName] = record
        }
        successfulModifyCount += 1
        return saved
    }

    func recordCount(type: String) -> Int {
        records.values.filter { $0.recordType == type }.count
    }
}
