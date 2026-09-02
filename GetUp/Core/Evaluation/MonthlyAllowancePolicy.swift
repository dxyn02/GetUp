import Foundation

enum MonthlyAllowancePolicyError: Error, Equatable, Sendable {
    case serverCreationMonthMismatch
}

enum MonthlyAllowancePolicy {
    static let monthlyQuota = 2

    static func monthID(containing date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(
            format: "%04d-%02d",
            locale: Locale(identifier: "en_US_POSIX"),
            components.year ?? 0,
            components.month ?? 0
        )
    }

    static func makeAllowance(
        monthID: String,
        ledgerEpoch: LedgerEpoch,
        serverCreationDate: Date
    ) throws -> MonthlyAllowance {
        guard Self.monthID(containing: serverCreationDate) == monthID else {
            throw MonthlyAllowancePolicyError.serverCreationMonthMismatch
        }

        let quota = ledgerEpoch.suppressedFreeMonthID == monthID ? 0 : monthlyQuota
        return try MonthlyAllowance(
            monthID: monthID,
            quota: quota,
            used: 0,
            reserved: 0,
            creationDate: serverCreationDate,
            updatedAt: serverCreationDate
        )
    }

    static func availableCount(
        for monthID: String,
        allowances: [MonthlyAllowance]
    ) -> Int {
        allowances.first(where: { $0.monthID == monthID })?.available ?? 0
    }
}
