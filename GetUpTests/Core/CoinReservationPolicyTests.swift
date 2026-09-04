import Foundation
import Testing
@testable import GetUp

@Suite("Coin reservation policy")
struct CoinReservationPolicyTests {
    @Test("Monthly allowance is selected before a purchased coin")
    func monthlyFreeHasPriority() throws {
        let source = try CoinReservationPolicy.selectFundingSource(
            ledgerState: .current(epoch: .reservationFixture()),
            requestedEpochID: LedgerEpoch.reservationFixture().epochID,
            allowance: try .reservationFixture(available: 1),
            account: try .reservationFixture(available: 3)
        )

        #expect(source == .monthlyFree)
    }

    @Test("A purchased coin is selected when the monthly allowance is exhausted")
    func purchasedCoinIsFallback() throws {
        let source = try CoinReservationPolicy.selectFundingSource(
            ledgerState: .current(epoch: .reservationFixture()),
            requestedEpochID: LedgerEpoch.reservationFixture().epochID,
            allowance: try .reservationFixture(available: 0),
            account: try .reservationFixture(available: 1)
        )

        #expect(source == .purchased)
    }

    @Test("Reservation is rejected when neither balance can fund it")
    func insufficientBalancesAreRejected() throws {
        #expect(throws: CoinReservationPolicyError.insufficientBalance) {
            try CoinReservationPolicy.selectFundingSource(
                ledgerState: .current(epoch: .reservationFixture()),
                requestedEpochID: LedgerEpoch.reservationFixture().epochID,
                allowance: try .reservationFixture(available: 0),
                account: try .reservationFixture(available: 0)
            )
        }
    }

    @Test(
        "Every non-current ledger state is rejected even when its local balance is positive",
        arguments: [
            MonthlyAllowanceLedgerState.setupRequired,
            .syncing,
            .stale,
            .unavailable,
            .deletionConfirmed,
            .resetRequired,
        ]
    )
    func nonCurrentLedgerIsRejected(_ state: MonthlyAllowanceLedgerState) throws {
        #expect(throws: CoinReservationPolicyError.ledgerNotCurrent) {
            try CoinReservationPolicy.selectFundingSource(
                ledgerState: state,
                requestedEpochID: LedgerEpoch.reservationFixture().epochID,
                allowance: try .reservationFixture(available: 2),
                account: try .reservationFixture(available: 3)
            )
        }
    }

    @Test("A request from another ledger epoch is rejected before selecting a balance")
    func epochMismatchIsRejected() throws {
        #expect(throws: CoinReservationPolicyError.ledgerEpochMismatch) {
            try CoinReservationPolicy.selectFundingSource(
                ledgerState: .current(epoch: .reservationFixture()),
                requestedEpochID: UUID(uuidString: "00000000-0000-4000-8000-000000000499")!,
                allowance: try .reservationFixture(available: 2),
                account: try .reservationFixture(available: 3)
            )
        }
    }
}

extension LedgerEpoch {
    static func reservationFixture() -> LedgerEpoch {
        LedgerEpoch(
            epochID: UUID(uuidString: "00000000-0000-4000-8000-000000000401")!,
            createdAt: .reservationFixture,
            reason: .initialSetup,
            suppressedFreeMonthID: nil,
            disclosureVersion: 1
        )
    }
}

extension MonthlyAllowance {
    static func reservationFixture(available: Int) throws -> MonthlyAllowance {
        try MonthlyAllowance(
            monthID: "2026-09",
            quota: 2,
            used: 2 - available,
            reserved: 0,
            creationDate: .reservationFixture,
            updatedAt: .reservationFixture
        )
    }
}

extension CoinAccount {
    static func reservationFixture(available: Int) throws -> CoinAccount {
        try CoinAccount(
            purchasedAvailable: available,
            purchasedReserved: 0,
            revision: 0,
            updatedAt: .reservationFixture
        )
    }
}

extension Date {
    static let reservationFixture = Date(timeIntervalSince1970: 1_788_192_000)
}
