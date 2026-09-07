import Foundation
import Testing
@testable import GetUp

@Suite("Monthly allowance user story", .serialized)
struct MonthlyAllowanceUserStoryTests {
    @Test("The first foreground mid-month grants exactly two new uses without rollover")
    func firstForegroundCreatesTwoWithoutRolloverOrPurchasedMutation() async throws {
        let now = try #require(Self.date("2026-09-15T03:00:00Z"))
        let previous = try MonthlyAllowance(
            monthID: "2026-08",
            quota: 2,
            used: 0,
            reserved: 0,
            creationDate: try #require(Self.date("2026-08-01T00:00:00Z")),
            updatedAt: now
        )
        let ledger = try MonthlyAllowanceUserStoryLedger(
            now: now,
            epoch: Self.epoch,
            purchasedAvailable: 5,
            allowances: [previous]
        )
        let service = MonthlyAllowanceService(repository: ledger)

        #expect(await ledger.allowance(for: "2026-09") == nil)

        let allowance = try await service.ensureAllowanceForAppForeground(
            monthID: "2026-09",
            ledgerState: .current(epoch: Self.epoch),
            existingAllowance: nil
        )

        #expect(allowance.quota == 2)
        #expect(allowance.available == 2)
        #expect(await ledger.allowance(for: "2026-08")?.available == 2)
        #expect(await ledger.purchasedUsable == 5)
        #expect(await ledger.operations == [.create(monthID: "2026-09", trigger: .appForeground)])
    }

    @Test("The first Shield request atomically creates this month and spends free before purchased")
    func firstShieldRequestCreatesAndReservesFreeWithoutSpendingPurchased() async throws {
        let now = try #require(Self.date("2026-10-15T03:00:00Z"))
        let previous = try MonthlyAllowance(
            monthID: "2026-09",
            quota: 2,
            used: 1,
            reserved: 0,
            creationDate: try #require(Self.date("2026-09-01T00:00:00Z")),
            updatedAt: now
        )
        let ledger = try MonthlyAllowanceUserStoryLedger(
            now: now,
            epoch: Self.epoch,
            purchasedAvailable: 5,
            allowances: [previous]
        )
        let occurrence = try Self.occurrence(containing: now)
        let service = RuleReleaseService(
            repository: ledger,
            now: { now },
            fetchCurrentContext: { _ in
                await ledger.context(for: occurrence, monthID: "2026-10")
            }
        )
        let request = RuleReleaseRequest(
            commandID: UUID(uuidString: "00000000-0000-4000-8000-000000000792")!,
            occurrenceID: occurrence.id,
            ruleID: occurrence.ruleID,
            ruleRevision: occurrence.ruleRevision,
            endsAt: occurrence.endAt,
            ledgerEpochID: Self.epoch.epochID,
            monthID: "2026-10",
            requestedFrom: .shield,
            requestedAt: now
        )

        #expect(await ledger.allowance(for: "2026-10") == nil)

        let reservation = try await service.reserve(request)

        #expect(reservation.command.fundingSource == .monthlyFree)
        #expect(reservation.allowance?.quota == 2)
        #expect(reservation.allowance?.reserved == 1)
        #expect(reservation.allowance?.available == 1)
        #expect(await ledger.allowance(for: "2026-09")?.available == 1)
        #expect(await ledger.purchasedUsable == 5)
        #expect(await ledger.operations == [.reserveMonthlyFree(monthID: "2026-10")])
    }

    private static let epoch = LedgerEpoch(
        epochID: UUID(uuidString: "00000000-0000-4000-8000-000000000790")!,
        createdAt: Date(timeIntervalSince1970: 1_778_000_000),
        reason: .initialSetup,
        suppressedFreeMonthID: nil,
        disclosureVersion: 1
    )

    private static func occurrence(containing date: Date) throws -> RestrictionOccurrence {
        try RestrictionOccurrence(
            ruleID: UUID(uuidString: "00000000-0000-4000-8000-000000000791")!,
            ruleRevision: 1,
            startAt: date.addingTimeInterval(-600),
            endAt: date.addingTimeInterval(3_600),
            activatedAt: date.addingTimeInterval(-590)
        )
    }

    private static func date(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}

private actor MonthlyAllowanceUserStoryLedger: CoinLedgerRepository {
    enum Operation: Equatable, Sendable {
        case create(
            monthID: String,
            trigger: MonthlyAllowanceCreationRequest.Trigger
        )
        case reserveMonthlyFree(monthID: String)
        case reservePurchased
    }

    private let now: Date
    private let epoch: LedgerEpoch
    private var account: CoinAccount
    private var allowances: [String: MonthlyAllowance]
    private(set) var operations: [Operation] = []

    init(
        now: Date,
        epoch: LedgerEpoch,
        purchasedAvailable: Int,
        allowances: [MonthlyAllowance]
    ) throws {
        self.now = now
        self.epoch = epoch
        account = try CoinAccount(
            purchasedAvailable: purchasedAvailable,
            purchasedReserved: 0,
            revision: 0,
            updatedAt: now
        )
        self.allowances = Dictionary(uniqueKeysWithValues: allowances.map { ($0.monthID, $0) })
    }

    var purchasedUsable: Int { account.purchasedUsable }

    func allowance(for monthID: String) -> MonthlyAllowance? {
        allowances[monthID]
    }

    func context(
        for occurrence: RestrictionOccurrence,
        monthID: String
    ) -> RuleReleaseReservationContext {
        RuleReleaseReservationContext(
            ledgerState: .current(epoch: epoch),
            occurrence: occurrence,
            currentRuleRevision: occurrence.ruleRevision,
            hasReleaseException: false,
            allowance: allowances[monthID],
            account: account
        )
    }

    func createAllowanceIfNeeded(
        _ request: MonthlyAllowanceCreationRequest
    ) throws -> MonthlyAllowance {
        guard request.epochID == epoch.epochID else {
            throw CoinLedgerRepositoryError.ledgerEpochMismatch
        }
        if let existing = allowances[request.monthID] {
            return existing
        }
        operations.append(.create(monthID: request.monthID, trigger: request.trigger))
        let allowance = try MonthlyAllowancePolicy.makeAllowance(
            monthID: request.monthID,
            ledgerEpoch: epoch,
            serverCreationDate: now
        )
        allowances[request.monthID] = allowance
        return allowance
    }

    func reserveMonthlyFree(
        _ request: MonthlyFreeReservationRequest
    ) throws -> CoinReleaseReservation {
        guard request.ledgerEpochID == epoch.epochID else {
            throw CoinLedgerRepositoryError.ledgerEpochMismatch
        }
        var allowance = try allowances[request.monthID] ?? MonthlyAllowancePolicy.makeAllowance(
            monthID: request.monthID,
            ledgerEpoch: epoch,
            serverCreationDate: now
        )
        guard allowance.available > 0 else {
            throw CoinLedgerRepositoryError.insufficientMonthlyAllowance
        }
        allowance = try MonthlyAllowance(
            monthID: allowance.monthID,
            quota: allowance.quota,
            used: allowance.used,
            reserved: allowance.reserved + 1,
            creationDate: allowance.creationDate,
            updatedAt: now
        )
        allowances[request.monthID] = allowance
        operations.append(.reserveMonthlyFree(monthID: request.monthID))
        let command = try reservedCommand(
            commandID: request.commandID,
            occurrenceID: request.occurrenceID,
            ruleID: request.ruleID,
            requestedFrom: request.requestedFrom,
            requestedAt: request.requestedAt,
            fundingSource: .monthlyFree
        )
        return CoinReleaseReservation(command: command, allowance: allowance, account: account)
    }

    func reservePurchasedCoin(
        _ request: PurchasedCoinReservationRequest
    ) throws -> CoinReleaseReservation {
        operations.append(.reservePurchased)
        throw CoinLedgerRepositoryError.insufficientPurchasedBalance
    }

    func fetchReleaseCommand(commandID _: UUID) throws -> ReleaseCommand? { nil }

    func markReleaseApplied(commandID _: UUID, at _: Date) throws -> ReleaseCommand {
        throw CoinLedgerRepositoryError.database(.unexpectedRequest)
    }

    func commitRelease(commandID _: UUID, at _: Date) throws -> ReleaseCommand {
        throw CoinLedgerRepositoryError.database(.unexpectedRequest)
    }

    func compensateRelease(commandID _: UUID, at _: Date) throws -> ReleaseCommand {
        throw CoinLedgerRepositoryError.database(.unexpectedRequest)
    }

    func grantPurchase(_ request: PurchaseGrantRequest) throws -> PurchaseGrant {
        throw CoinLedgerRepositoryError.database(.unexpectedRequest)
    }

    private func reservedCommand(
        commandID: UUID,
        occurrenceID: String,
        ruleID: UUID,
        requestedFrom: ReleaseRequestSource,
        requestedAt: Date,
        fundingSource: ReleaseFundingSource
    ) throws -> ReleaseCommand {
        try ReleaseCommand.requested(
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
    }
}
