import Foundation
import Testing
@testable import GetUp

@Suite("Monthly allowance service")
struct MonthlyAllowanceServiceTests {
    @Test("First foreground in a new month lazily creates quota two")
    func firstForegroundCreatesCurrentMonthAllowance() async throws {
        let repository = MonthlyAllowanceRepositorySpy(result: .success(.septemberFixture()))
        let service = MonthlyAllowanceService(repository: repository)

        let allowance = try await service.ensureAllowanceForAppForeground(
            monthID: "2026-09",
            ledgerState: .current(epoch: .fixture()),
            existingAllowance: nil
        )

        #expect(allowance.quota == 2)
        #expect(await repository.creationRequests == [
            MonthlyAllowanceCreationRequest(
                monthID: "2026-09",
                epochID: LedgerEpoch.fixture().epochID,
                trigger: .appForeground
            )
        ])
    }

    @Test("An existing current-month allowance is returned without another write")
    func existingAllowanceIsIdempotent() async throws {
        let existing = try MonthlyAllowance.septemberFixture(used: 1)
        let repository = MonthlyAllowanceRepositorySpy(result: .failure(TestFailure.unexpectedWrite))
        let service = MonthlyAllowanceService(repository: repository)

        let allowance = try await service.ensureAllowanceForAppForeground(
            monthID: "2026-09",
            ledgerState: .current(epoch: .fixture()),
            existingAllowance: existing
        )

        #expect(allowance == existing)
        #expect(await repository.creationRequests.isEmpty)
    }

    @Test("A failed lazy creation leaves no confirmed allowance")
    func failedLazyCreationDoesNotGrantFreeUses() async {
        let repository = MonthlyAllowanceRepositorySpy(result: .failure(TestFailure.serverUnavailable))
        let service = MonthlyAllowanceService(repository: repository)

        await #expect(throws: TestFailure.serverUnavailable) {
            try await service.ensureAllowanceForAppForeground(
                monthID: "2026-09",
                ledgerState: .current(epoch: .fixture()),
                existingAllowance: nil
            )
        }
        #expect(await repository.confirmedAllowances.isEmpty)
        #expect(await repository.creationRequests.count == 1)
    }

    @Test("A non-current ledger cannot create a monthly allowance")
    func unavailableLedgerDoesNotCreateAllowance() async {
        let repository = MonthlyAllowanceRepositorySpy(result: .failure(TestFailure.unexpectedWrite))
        let service = MonthlyAllowanceService(repository: repository)

        await #expect(throws: MonthlyAllowanceServiceError.ledgerNotCurrent) {
            try await service.ensureAllowanceForAppForeground(
                monthID: "2026-09",
                ledgerState: .setupRequired,
                existingAllowance: nil
            )
        }
        #expect(await repository.creationRequests.isEmpty)
    }
}

private actor MonthlyAllowanceRepositorySpy: MonthlyAllowanceRepository {
    private let result: Result<MonthlyAllowance, any Error>
    private(set) var creationRequests: [MonthlyAllowanceCreationRequest] = []
    private(set) var confirmedAllowances: [MonthlyAllowance] = []

    init(result: Result<MonthlyAllowance, any Error>) {
        self.result = result
    }

    func createAllowanceIfNeeded(
        _ request: MonthlyAllowanceCreationRequest
    ) async throws -> MonthlyAllowance {
        creationRequests.append(request)
        let allowance = try result.get()
        confirmedAllowances.append(allowance)
        return allowance
    }
}

private extension MonthlyAllowance {
    static func septemberFixture(used: Int = 0) throws -> MonthlyAllowance {
        try MonthlyAllowance(
            monthID: "2026-09",
            quota: 2,
            used: used,
            reserved: 0,
            creationDate: Date(timeIntervalSince1970: 1_788_192_000),
            updatedAt: Date(timeIntervalSince1970: 1_788_192_000)
        )
    }
}

private enum TestFailure: Error {
    case serverUnavailable
    case unexpectedWrite
}
