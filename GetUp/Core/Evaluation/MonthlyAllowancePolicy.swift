import Foundation

enum MonthlyAllowancePolicyError: Error, Equatable, Sendable {
    case serverCreationMonthMismatch
}

enum MonthlyAllowancePolicy {
    static let monthlyQuota = 2

    static func monthID(containing date: Date) -> String {
        monthID(
            containing: date,
            boundaryDay: SharedIdentifiers.t089LedgerTestConfiguration()?.monthlyBoundaryDay ?? 1
        )
    }

    static func monthID(containing date: Date, boundaryDay: Int) -> String {
        let boundaryDay = normalizedBoundaryDay(boundaryDay)
        let shiftedDate = calendar.date(
            byAdding: .day,
            value: -(boundaryDay - 1),
            to: date
        ) ?? date
        let components = calendar.dateComponents([.year, .month], from: shiftedDate)
        return String(
            format: "%04d-%02d",
            locale: Locale(identifier: "en_US_POSIX"),
            components.year ?? 0,
            components.month ?? 0
        )
    }

    static func nextPeriodStart(after date: Date, boundaryDay: Int) -> Date? {
        let boundaryDay = normalizedBoundaryDay(boundaryDay)
        let shiftedDate = calendar.date(
            byAdding: .day,
            value: -(boundaryDay - 1),
            to: date
        ) ?? date
        let period = calendar.dateComponents([.year, .month], from: shiftedDate)
        guard let periodStart = calendar.date(
            from: DateComponents(
                year: period.year,
                month: period.month,
                day: boundaryDay
            )
        ) else {
            return nil
        }
        return calendar.date(byAdding: .month, value: 1, to: periodStart)
    }

    static func nextPeriodStart(afterMonthID monthID: String) -> Date? {
        let components = monthID.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 2,
              let year = Int(components[0]),
              let month = Int(components[1]),
              (1...12).contains(month)
        else {
            return nil
        }
        let boundaryDay = SharedIdentifiers.t089LedgerTestConfiguration()?.monthlyBoundaryDay ?? 1
        guard let periodStart = calendar.date(
            from: DateComponents(year: year, month: month, day: boundaryDay)
        ) else {
            return nil
        }
        return calendar.date(byAdding: .month, value: 1, to: periodStart)
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

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    private static func normalizedBoundaryDay(_ boundaryDay: Int) -> Int {
        (1...28).contains(boundaryDay) ? boundaryDay : 1
    }
}
