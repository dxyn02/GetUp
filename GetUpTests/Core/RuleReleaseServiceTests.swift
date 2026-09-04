import Foundation
import Testing
@testable import GetUp

@Suite("Rule release service")
struct RuleReleaseServiceTests {
    @Test("The service fetches current context and reserves the monthly allowance first")
    func monthlyFreeReservationUsesLatestContext() async throws {
        let repository = AtomicOccurrenceReservationRepository()
        let contextSource = RuleReleaseContextSource(
            context: try .fixture(freeAvailable: 1, purchasedAvailable: 2)
        )
        let service = RuleReleaseService(
            repository: repository,
            fetchCurrentContext: { request in
                try await contextSource.fetch(for: request)
            }
        )
        let request = RuleReleaseRequest.fixture()

        let reservation = try await service.reserve(request)

        #expect(reservation.command.fundingSource == .monthlyFree)
        #expect(await contextSource.requests == [request])
        #expect(await repository.operations == [.reserveMonthlyFree])
    }

    @Test("The service falls back to a purchased coin only after free allowance exhaustion")
    func purchasedReservationIsFallback() async throws {
        let repository = AtomicOccurrenceReservationRepository()
        let service = RuleReleaseService(
            repository: repository,
            fetchCurrentContext: { _ in
                try .fixture(freeAvailable: 0, purchasedAvailable: 1)
            }
        )

        let reservation = try await service.reserve(.fixture())

        #expect(reservation.command.fundingSource == .purchased)
        #expect(await repository.operations == [.reservePurchased])
    }

    @Test("Insufficient balance causes no repository mutation")
    func insufficientBalanceDoesNotMutateRepository() async throws {
        let repository = AtomicOccurrenceReservationRepository()
        let service = RuleReleaseService(
            repository: repository,
            fetchCurrentContext: { _ in
                try .fixture(freeAvailable: 0, purchasedAvailable: 0)
            }
        )

        await #expect(throws: CoinReservationPolicyError.insufficientBalance) {
            try await service.reserve(.fixture())
        }
        #expect(await repository.operations.isEmpty)
    }

    @Test("Non-current and mismatched-epoch requests cause no repository mutation")
    func invalidLedgerStateDoesNotMutateRepository() async throws {
        let repository = AtomicOccurrenceReservationRepository()
        let nonCurrent = RuleReleaseService(
            repository: repository,
            fetchCurrentContext: { _ in
                try .fixture(ledgerState: .deletionConfirmed)
            }
        )
        await #expect(throws: CoinReservationPolicyError.ledgerNotCurrent) {
            try await nonCurrent.reserve(.fixture())
        }

        let mismatched = RuleReleaseService(
            repository: repository,
            fetchCurrentContext: { _ in try .fixture() }
        )
        await #expect(throws: CoinReservationPolicyError.ledgerEpochMismatch) {
            try await mismatched.reserve(.fixture(
                ledgerEpochID: UUID(uuidString: "00000000-0000-4000-8000-000000000499")!
            ))
        }

        #expect(await repository.operations.isEmpty)
    }

    @Test("One hundred requests for one occurrence produce exactly one reservation")
    func concurrentRequestsReserveOnce() async throws {
        let repository = AtomicOccurrenceReservationRepository()
        let service = RuleReleaseService(
            repository: repository,
            fetchCurrentContext: { _ in try .fixture() }
        )

        let successCount = await withTaskGroup(of: Bool.self) { group in
            for index in 1...100 {
                group.addTask {
                    do {
                        _ = try await service.reserve(.fixture(
                            commandID: UUID(
                                uuidString: String(
                                    format: "00000000-0000-4000-8000-%012d",
                                    index
                                )
                            )!
                        ))
                        return true
                    } catch {
                        return false
                    }
                }
            }

            var successes = 0
            for await succeeded in group where succeeded {
                successes += 1
            }
            return successes
        }

        #expect(successCount == 1)
        #expect(await repository.reservationCount == 1)
    }

    @Test("A release follows requested, reserved, applied, and committed states")
    func successfulStateTransitions() throws {
        let requested = try ReleaseCommand.fixture()
        let reserved = try requested.transitioning(
            to: .reserved,
            fundingSource: .monthlyFree,
            at: .reservationFixture.addingTimeInterval(1)
        )
        let applied = try reserved.transitioning(
            to: .applied,
            at: .reservationFixture.addingTimeInterval(2)
        )
        let committed = try applied.transitioning(
            to: .committed,
            at: .reservationFixture.addingTimeInterval(3)
        )

        #expect([requested.state, reserved.state, applied.state, committed.state] == [
            .requested, .reserved, .applied, .committed,
        ])
        #expect(committed.fundingSource == .monthlyFree)
    }

    @Test("A failed application compensates a reserved coin")
    func compensationStateTransitions() throws {
        let reserved = try ReleaseCommand.fixture().transitioning(
            to: .reserved,
            fundingSource: .purchased,
            at: .reservationFixture.addingTimeInterval(1)
        )
        let compensating = try reserved.transitioning(
            to: .compensating,
            failureCode: "release_exception_write_failed",
            at: .reservationFixture.addingTimeInterval(2)
        )
        let compensated = try compensating.transitioning(
            to: .compensated,
            at: .reservationFixture.addingTimeInterval(3)
        )

        #expect([reserved.state, compensating.state, compensated.state] == [
            .reserved, .compensating, .compensated,
        ])
        #expect(compensated.fundingSource == .purchased)
    }

    @Test("An unknown result can reconcile to either committed or compensated")
    func unknownResultReconciliationTransitions() throws {
        let reserved = try ReleaseCommand.fixture().transitioning(
            to: .reserved,
            fundingSource: .monthlyFree,
            at: .reservationFixture.addingTimeInterval(1)
        )
        let unknown = try reserved.transitioning(
            to: .reconciliationRequired,
            failureCode: "cloud_result_unknown",
            at: .reservationFixture.addingTimeInterval(2)
        )

        let committed = try unknown.transitioning(
            to: .committed,
            at: .reservationFixture.addingTimeInterval(3)
        )
        let compensated = try unknown.transitioning(
            to: .compensated,
            at: .reservationFixture.addingTimeInterval(3)
        )

        #expect(unknown.state == .reconciliationRequired)
        #expect(committed.state == .committed)
        #expect(compensated.state == .compensated)
    }
}

private actor RuleReleaseContextSource {
    let context: RuleReleaseReservationContext
    private(set) var requests: [RuleReleaseRequest] = []

    init(context: RuleReleaseReservationContext) {
        self.context = context
    }

    func fetch(for request: RuleReleaseRequest) -> RuleReleaseReservationContext {
        requests.append(request)
        return context
    }
}

private actor AtomicOccurrenceReservationRepository: CoinLedgerRepository {
    enum Operation: Equatable, Sendable {
        case reserveMonthlyFree
        case reservePurchased
    }

    private var reservedOccurrences: Set<String> = []
    private(set) var operations: [Operation] = []

    var reservationCount: Int { reservedOccurrences.count }

    func createAllowanceIfNeeded(
        _ request: MonthlyAllowanceCreationRequest
    ) async throws -> MonthlyAllowance {
        try .reservationFixture(available: 2)
    }

    func reserveMonthlyFree(
        _ request: MonthlyFreeReservationRequest
    ) async throws -> CoinReleaseReservation {
        operations.append(.reserveMonthlyFree)
        return try reserve(
            commandID: request.commandID,
            occurrenceID: request.occurrenceID,
            ruleID: request.ruleID,
            requestedFrom: request.requestedFrom,
            requestedAt: request.requestedAt,
            fundingSource: .monthlyFree
        )
    }

    func reservePurchasedCoin(
        _ request: PurchasedCoinReservationRequest
    ) async throws -> CoinReleaseReservation {
        operations.append(.reservePurchased)
        return try reserve(
            commandID: request.commandID,
            occurrenceID: request.occurrenceID,
            ruleID: request.ruleID,
            requestedFrom: request.requestedFrom,
            requestedAt: request.requestedAt,
            fundingSource: .purchased
        )
    }

    func fetchReleaseCommand(commandID: UUID) async throws -> ReleaseCommand? { nil }

    func markReleaseApplied(commandID: UUID, at date: Date) async throws -> ReleaseCommand {
        throw CoinLedgerRepositoryError.database(.unexpectedRequest)
    }

    func commitRelease(commandID: UUID, at date: Date) async throws -> ReleaseCommand {
        throw CoinLedgerRepositoryError.database(.unexpectedRequest)
    }

    func compensateRelease(commandID: UUID, at date: Date) async throws -> ReleaseCommand {
        throw CoinLedgerRepositoryError.database(.unexpectedRequest)
    }

    func grantPurchase(_ request: PurchaseGrantRequest) async throws -> PurchaseGrant {
        throw CoinLedgerRepositoryError.database(.unexpectedRequest)
    }

    private func reserve(
        commandID: UUID,
        occurrenceID: String,
        ruleID: UUID,
        requestedFrom: ReleaseRequestSource,
        requestedAt: Date,
        fundingSource: ReleaseFundingSource
    ) throws -> CoinReleaseReservation {
        guard reservedOccurrences.insert(occurrenceID).inserted else {
            throw CoinLedgerRepositoryError.reconciliationRequired(commandID: commandID)
        }
        let command = try ReleaseCommand.requested(
            commandID: commandID,
            occurrenceID: occurrenceID,
            ruleID: ruleID,
            requestedFrom: requestedFrom,
            at: requestedAt
        ).transitioning(
            to: .reserved,
            fundingSource: fundingSource,
            at: requestedAt
        )
        return CoinReleaseReservation(command: command, allowance: nil, account: nil)
    }
}

private extension RuleReleaseRequest {
    static func fixture(
        commandID: UUID = UUID(uuidString: "00000000-0000-4000-8000-000000000402")!,
        ledgerEpochID: UUID = LedgerEpoch.reservationFixture().epochID
    ) -> RuleReleaseRequest {
        RuleReleaseRequest(
            commandID: commandID,
            occurrenceID: RestrictionOccurrence.reservationFixture.id,
            ruleID: RestrictionOccurrence.reservationFixture.ruleID,
            ruleRevision: RestrictionOccurrence.reservationFixture.ruleRevision,
            endsAt: RestrictionOccurrence.reservationFixture.endAt,
            ledgerEpochID: ledgerEpochID,
            monthID: "2026-09",
            requestedFrom: .app,
            requestedAt: .reservationFixture
        )
    }
}

private extension RuleReleaseReservationContext {
    static func fixture(
        ledgerState: MonthlyAllowanceLedgerState = .current(epoch: .reservationFixture()),
        freeAvailable: Int = 1,
        purchasedAvailable: Int = 1
    ) throws -> RuleReleaseReservationContext {
        RuleReleaseReservationContext(
            ledgerState: ledgerState,
            occurrence: .reservationFixture,
            hasReleaseException: false,
            allowance: try .reservationFixture(available: freeAvailable),
            account: try .reservationFixture(available: purchasedAvailable)
        )
    }
}

private extension RestrictionOccurrence {
    static var reservationFixture: RestrictionOccurrence {
        try! RestrictionOccurrence(
            ruleID: UUID(uuidString: "00000000-0000-4000-8000-000000000403")!,
            ruleRevision: 7,
            startAt: .reservationFixture.addingTimeInterval(-600),
            endAt: .reservationFixture.addingTimeInterval(3_600),
            activatedAt: .reservationFixture.addingTimeInterval(-590)
        )
    }
}

private extension ReleaseCommand {
    static func fixture() throws -> ReleaseCommand {
        try .requested(
            commandID: UUID(uuidString: "00000000-0000-4000-8000-000000000404")!,
            occurrenceID: RestrictionOccurrence.reservationFixture.id,
            ruleID: RestrictionOccurrence.reservationFixture.ruleID,
            requestedFrom: .app,
            at: .reservationFixture
        )
    }
}
