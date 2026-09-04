import Foundation
import Testing
@testable import GetUp

@Suite("CloudKit monthly allowance atomic reservation")
struct CloudKitMonthlyAllowanceTests {
    @Test("First Shield request creates allowance, free grant, reservation, and command in one modify")
    func firstShieldRequestUsesSingleAtomicModify() async throws {
        let database = ScriptedCoinLedgerDatabase(
            fetchResults: [.success([])],
            modifyResults: [.success([])]
        )
        let mapper = CoinLedgerRecordMapper()
        let repository = CloudKitCoinLedgerRepository(database: database, mapper: mapper,
            verifyReservationCompatibility: { _ in true })
        let request = CloudKitLedgerTestFixtures.reservationRequest()

        _ = try await repository.reserveMonthlyFree(request)

        let modify = try #require(await database.modifyRequests.first)
        let names = Set(modify.recordsToSave.map(\.recordName))
        #expect(await database.modifyRequests.count == 1)
        #expect(modify.isAtomic)
        #expect(modify.savePolicy == .ifServerRecordUnchanged)
        #expect(names == [
            CoinLedgerRecordID.ledgerEpoch,
            CoinLedgerRecordID.releaseOccurrenceClaim(
                ledgerEpochID: request.ledgerEpochID, occurrenceID: request.occurrenceID
            ),
            CoinLedgerRecordID.allowance(monthID: request.monthID),
            CoinLedgerDeterministicID.freeGrant(monthID: request.monthID),
            CoinLedgerDeterministicID.reservation(commandID: request.commandID),
            CoinLedgerRecordID.releaseCommand(commandID: request.commandID),
        ])

        let allowanceRecord = try #require(modify.recordsToSave.first {
            $0.recordName == CoinLedgerRecordID.allowance(monthID: request.monthID)
        })
        let allowanceEntity = try mapper.entity(from: allowanceRecord)
        guard case let .monthlyAllowance(allowance) = allowanceEntity else {
            Issue.record("Expected monthly allowance record")
            return
        }
        #expect(allowance.quota == 2)
        #expect(allowance.used == 0)
        #expect(allowance.reserved == 1)
        #expect(allowance.available == 1)
    }

    @Test("Deterministic monthly and command IDs are identical across devices")
    func deterministicIDsMatchAcrossDevices() {
        let requestOnDeviceA = CloudKitLedgerTestFixtures.reservationRequest()
        let requestOnDeviceB = CloudKitLedgerTestFixtures.reservationRequest()

        #expect(
            CoinLedgerRecordID.allowance(monthID: requestOnDeviceA.monthID)
                == CoinLedgerRecordID.allowance(monthID: requestOnDeviceB.monthID)
        )
        #expect(
            CoinLedgerDeterministicID.freeGrant(monthID: requestOnDeviceA.monthID)
                == "free:2026-09"
        )
        #expect(
            CoinLedgerDeterministicID.reservation(commandID: requestOnDeviceA.commandID)
                == CoinLedgerDeterministicID.reservation(commandID: requestOnDeviceB.commandID)
        )
        #expect(
            CoinLedgerRecordID.releaseCommand(commandID: requestOnDeviceA.commandID)
                == CoinLedgerRecordID.releaseCommand(commandID: requestOnDeviceB.commandID)
        )
    }

    @Test("A second device losing allowance creation conflict reuses server grant and reserves only once")
    func multiDeviceCreationConflictDoesNotDuplicateGrant() async throws {
        let mapper = CoinLedgerRecordMapper()
        let serverAllowance = try CloudKitLedgerTestFixtures.record(
            for: .monthlyAllowance(try CloudKitLedgerTestFixtures.allowance(reserved: 1)),
            changeTag: "allowance-device-a",
            mapper: mapper
        )
        let serverFreeGrant = try mapper.record(for: .event(try CoinLedgerEvent(
            eventID: CoinLedgerDeterministicID.freeGrant(
                monthID: CloudKitLedgerTestFixtures.monthID
            ),
            kind: .freeGrant,
            source: .monthlyFree,
            quantity: 2,
            relatedTransactionID: nil,
            relatedCommandID: nil,
            occurrenceID: nil,
            createdAt: CloudKitLedgerTestFixtures.now
        )))
        let deviceBCommandID = UUID(
            uuidString: "00000000-0000-4000-8000-000000000504"
        )!
        let database = ScriptedCoinLedgerDatabase(
            fetchResults: [
                .success([]),
                .success([serverAllowance, serverFreeGrant]),
            ],
            modifyResults: [
                .failure(.serverRecordChanged),
                .success([]),
            ]
        )
        let repository = CloudKitCoinLedgerRepository(
            database: database,
            mapper: mapper,
            conflictRetryLimit: 1,
            verifyReservationCompatibility: { _ in true }
        )

        _ = try await repository.reserveMonthlyFree(
            CloudKitLedgerTestFixtures.reservationRequest(commandID: deviceBCommandID)
        )

        let modifies = await database.modifyRequests
        #expect(await database.fetchRequests.count == 2)
        #expect(modifies.count == 2)
        #expect(modifies.last?.recordsToSave.filter {
            $0.recordName == CoinLedgerDeterministicID.freeGrant(
                monthID: CloudKitLedgerTestFixtures.monthID
            )
        }.isEmpty == true)

        let finalAllowanceRecord = try #require(modifies.last?.recordsToSave.first {
            $0.recordName == CoinLedgerRecordID.allowance(
                monthID: CloudKitLedgerTestFixtures.monthID
            )
        })
        guard case let .monthlyAllowance(finalAllowance) = try mapper.entity(
            from: finalAllowanceRecord
        ) else {
            Issue.record("Expected monthly allowance record")
            return
        }
        #expect(finalAllowance.quota == 2)
        #expect(finalAllowance.reserved == 2)
        #expect(finalAllowance.available == 0)
    }

    @Test("When both free uses are reserved a conflicting third device cannot overdraw")
    func multiDeviceConflictCannotExceedQuota() async throws {
        let mapper = CoinLedgerRecordMapper()
        let exhausted = try CloudKitLedgerTestFixtures.record(
            for: .monthlyAllowance(try CloudKitLedgerTestFixtures.allowance(reserved: 2)),
            changeTag: "allowance-exhausted",
            mapper: mapper
        )
        let database = ScriptedCoinLedgerDatabase(
            fetchResults: [.success([exhausted])],
            modifyResults: []
        )
        let repository = CloudKitCoinLedgerRepository(database: database, mapper: mapper,
            verifyReservationCompatibility: { _ in true })

        await #expect(throws: CoinLedgerRepositoryError.insufficientMonthlyAllowance) {
            _ = try await repository.reserveMonthlyFree(
                CloudKitLedgerTestFixtures.reservationRequest(
                    commandID: UUID(
                        uuidString: "00000000-0000-4000-8000-000000000505"
                    )!
                )
            )
        }

        #expect(await database.modifyRequests.isEmpty)
    }
}
