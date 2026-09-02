import Foundation
import Testing
@testable import GetUp

@Suite("Monthly allowance service")
struct MonthlyAllowanceServiceTests {
    @Test("First foreground in a new month lazily creates quota two")
    func firstForegroundCreatesCurrentMonthAllowance() async throws {
        let repository = MonthlyAllowanceRepositorySpy(result: .success(try .septemberFixture()))
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
        let repository = MonthlyAllowanceRepositorySpy(result: .failure(.unexpectedWrite))
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
        let repository = MonthlyAllowanceRepositorySpy(result: .failure(.serverUnavailable))
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
        let repository = MonthlyAllowanceRepositorySpy(result: .failure(.unexpectedWrite))
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

    @Test("Shield release delegates allowance creation and reservation as one repository command")
    func shieldReleaseUsesAtomicReservationPath() async throws {
        let repository = MonthlyAllowanceRepositorySpy(result: .failure(.unexpectedWrite))
        let reservationRepository = MonthlyFreeReservationSpy()
        let service = MonthlyAllowanceService(
            repository: repository,
            reserveMonthlyFree: { request in
                try await reservationRepository.reserve(request)
            }
        )
        let request = MonthlyFreeReservationRequest.fixture()

        let reservation = try await service.reserveAllowanceForShield(
            request,
            ledgerState: .current(epoch: .fixture())
        )

        #expect(reservation.command.commandID == request.commandID)
        #expect(reservation.command.state == .reserved)
        #expect(reservation.allowance?.reserved == 1)
        #expect(await repository.creationRequests.isEmpty)
        #expect(await reservationRepository.requests == [request])
    }

    @Test("Shield release cannot reserve against a non-current ledger")
    func shieldReleaseRejectsUnavailableLedger() async {
        let repository = MonthlyAllowanceRepositorySpy(result: .failure(.unexpectedWrite))
        let reservationRepository = MonthlyFreeReservationSpy()
        let service = MonthlyAllowanceService(
            repository: repository,
            reserveMonthlyFree: { request in
                try await reservationRepository.reserve(request)
            }
        )

        await #expect(throws: MonthlyAllowanceServiceError.ledgerNotCurrent) {
            try await service.reserveAllowanceForShield(
                .fixture(),
                ledgerState: .setupRequired
            )
        }
        #expect(await reservationRepository.requests.isEmpty)
    }
}

private actor MonthlyAllowanceRepositorySpy: MonthlyAllowanceRepository {
    private let result: Result<MonthlyAllowance, TestFailure>
    private(set) var creationRequests: [MonthlyAllowanceCreationRequest] = []
    private(set) var confirmedAllowances: [MonthlyAllowance] = []

    init(result: Result<MonthlyAllowance, TestFailure>) {
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

private actor MonthlyFreeReservationSpy {
    private(set) var requests: [MonthlyFreeReservationRequest] = []

    func reserve(
        _ request: MonthlyFreeReservationRequest
    ) async throws -> CoinReleaseReservation {
        requests.append(request)
        let allowance = try MonthlyAllowance.septemberFixture(reserved: 1)
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
        return CoinReleaseReservation(
            command: command,
            allowance: allowance,
            account: nil
        )
    }
}

private extension MonthlyAllowance {
    static func septemberFixture(
        used: Int = 0,
        reserved: Int = 0
    ) throws -> MonthlyAllowance {
        try MonthlyAllowance(
            monthID: "2026-09",
            quota: 2,
            used: used,
            reserved: reserved,
            creationDate: Date(timeIntervalSince1970: 1_788_192_000),
            updatedAt: Date(timeIntervalSince1970: 1_788_192_000)
        )
    }
}

private extension MonthlyFreeReservationRequest {
    static func fixture() -> MonthlyFreeReservationRequest {
        MonthlyFreeReservationRequest(
            commandID: UUID(uuidString: "00000000-0000-4000-8000-000000000211")!,
            occurrenceID: "rule:1:2026-09-02T00:00:00Z",
            ruleID: UUID(uuidString: "00000000-0000-4000-8000-000000000212")!,
            ruleRevision: 1,
            monthID: "2026-09",
            ledgerEpochID: LedgerEpoch.fixture().epochID,
            requestedFrom: .shield,
            requestedAt: Date(timeIntervalSince1970: 1_788_192_000)
        )
    }
}

private enum TestFailure: Error, Sendable {
    case serverUnavailable
    case unexpectedWrite
}
