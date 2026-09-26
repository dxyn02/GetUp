import Foundation
import Testing
@testable import GetUp

@Suite("Monthly allowance policy")
struct MonthlyAllowancePolicyTests {
    @Test("Month ID changes at midnight in Asia Seoul")
    func seoulMonthBoundary() throws {
        let beforeBoundary = try #require(Self.date("2026-08-31T14:59:59Z"))
        let boundary = try #require(Self.date("2026-08-31T15:00:00Z"))

        #expect(MonthlyAllowancePolicy.monthID(containing: beforeBoundary) == "2026-08")
        #expect(MonthlyAllowancePolicy.monthID(containing: boundary) == "2026-09")
    }

    @Test("The isolated T089 cycle changes at Seoul midnight on day thirteen")
    func t089DayThirteenBoundary() throws {
        let beforeBoundary = try #require(Self.date("2026-09-12T14:59:59Z"))
        let boundary = try #require(Self.date("2026-09-12T15:00:00Z"))

        #expect(
            MonthlyAllowancePolicy.monthID(
                containing: beforeBoundary,
                boundaryDay: 13
            ) == "2026-08"
        )
        #expect(
            MonthlyAllowancePolicy.monthID(
                containing: boundary,
                boundaryDay: 13
            ) == "2026-09"
        )
        #expect(
            MonthlyAllowancePolicy.nextPeriodStart(
                after: beforeBoundary,
                boundaryDay: 13
            ) == boundary
        )
    }

    @Test("The isolated T089 five-minute cycle changes on Seoul clock boundaries")
    func t089FiveMinuteBoundary() throws {
        let beforeBoundary = try #require(Self.date("2026-09-14T07:44:59Z"))
        let boundary = try #require(Self.date("2026-09-14T07:45:00Z"))

        #expect(
            MonthlyAllowancePolicy.periodID(
                containing: beforeBoundary,
                intervalMinutes: 5
            ) == "2026-09-14T16-40"
        )
        #expect(
            MonthlyAllowancePolicy.periodID(
                containing: boundary,
                intervalMinutes: 5
            ) == "2026-09-14T16-45"
        )
        #expect(
            MonthlyAllowancePolicy.nextPeriodStart(
                afterPeriodID: "2026-09-14T16-40",
                intervalMinutes: 5
            ) == boundary
        )
    }

    @Test("The isolated T089 five-minute cycle rolls over at Seoul midnight")
    func t089FiveMinuteMidnightRollover() throws {
        let beforeMidnight = try #require(Self.date("2026-09-14T14:59:59Z"))
        let midnight = try #require(Self.date("2026-09-14T15:00:00Z"))

        #expect(
            MonthlyAllowancePolicy.periodID(
                containing: beforeMidnight,
                intervalMinutes: 5
            ) == "2026-09-14T23-55"
        )
        #expect(
            MonthlyAllowancePolicy.periodID(
                containing: midnight,
                intervalMinutes: 5
            ) == "2026-09-15T00-00"
        )
        #expect(
            MonthlyAllowancePolicy.nextPeriodStart(
                afterPeriodID: "2026-09-14T23-55",
                intervalMinutes: 5
            ) == midnight
        )
        #expect(
            MonthlyAllowancePolicy.periodStart(
                forPeriodID: "2026-09-14T23-57",
                intervalMinutes: 5
            ) == nil
        )
    }

    @Test("A normal month has quota two and valid count bounds")
    func quotaAndBalanceInvariant() throws {
        let allowance = try MonthlyAllowancePolicy.makeAllowance(
            monthID: "2026-09",
            ledgerEpoch: .fixture(),
            serverCreationDate: try #require(Self.date("2026-09-15T00:00:00Z"))
        )

        #expect(allowance.quota == 2)
        #expect(allowance.available == 2)
        #expect(throws: LiveActivityCoinModelError.invalidMonthlyAllowanceBalance) {
            try MonthlyAllowance(
                monthID: "2026-09",
                quota: 2,
                used: 2,
                reserved: 1,
                creationDate: allowance.creationDate,
                updatedAt: allowance.updatedAt
            )
        }
    }

    @Test("Unused prior-month allowance never rolls into the current balance")
    func allowanceDoesNotRollOver() throws {
        let august = try MonthlyAllowance(
            monthID: "2026-08",
            quota: 2,
            used: 0,
            reserved: 0,
            creationDate: try #require(Self.date("2026-08-01T00:00:00Z")),
            updatedAt: try #require(Self.date("2026-08-01T00:00:00Z"))
        )
        let september = try MonthlyAllowance(
            monthID: "2026-09",
            quota: 2,
            used: 1,
            reserved: 0,
            creationDate: try #require(Self.date("2026-09-01T00:00:00Z")),
            updatedAt: try #require(Self.date("2026-09-01T00:00:00Z"))
        )

        #expect(
            MonthlyAllowancePolicy.availableCount(
                for: "2026-09",
                allowances: [august, september]
            ) == 1
        )
    }

    @Test("Reset month is suppressed to zero and the next month returns to quota two")
    func resetMonthSuppression() throws {
        let resetEpoch = LedgerEpoch.fixture(
            reason: .userConfirmedResetAfterDeletion,
            suppressedFreeMonthID: "2026-09"
        )
        let resetMonth = try MonthlyAllowancePolicy.makeAllowance(
            monthID: "2026-09",
            ledgerEpoch: resetEpoch,
            serverCreationDate: try #require(Self.date("2026-09-02T00:00:00Z"))
        )
        let nextMonth = try MonthlyAllowancePolicy.makeAllowance(
            monthID: "2026-10",
            ledgerEpoch: resetEpoch,
            serverCreationDate: try #require(Self.date("2026-10-02T00:00:00Z"))
        )

        #expect(resetMonth.quota == 0)
        #expect(resetMonth.available == 0)
        #expect(nextMonth.quota == 2)
        #expect(nextMonth.available == 2)
    }

    @Test("Server creation date must belong to the requested Seoul month")
    func serverCreationDateMustMatchMonth() throws {
        let invalidCreationDate = try #require(Self.date("2026-08-31T14:59:59Z"))

        #expect(throws: MonthlyAllowancePolicyError.serverCreationMonthMismatch) {
            try MonthlyAllowancePolicy.makeAllowance(
                monthID: "2026-09",
                ledgerEpoch: .fixture(),
                serverCreationDate: invalidCreationDate
            )
        }
    }

    private static func date(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}

extension LedgerEpoch {
    static func fixture(
        reason: LedgerEpochReason = .initialSetup,
        suppressedFreeMonthID: String? = nil
    ) -> LedgerEpoch {
        LedgerEpoch(
            epochID: UUID(uuidString: "00000000-0000-4000-8000-000000000201")!,
            createdAt: Date(timeIntervalSince1970: 1_788_192_000),
            reason: reason,
            suppressedFreeMonthID: suppressedFreeMonthID,
            disclosureVersion: 1
        )
    }
}
