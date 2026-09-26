import Foundation

enum MonthlyAllowancePolicyError: Error, Equatable, Sendable {
    case serverCreationMonthMismatch
}

enum MonthlyAllowancePolicy {
    static let monthlyQuota = 2

    static func monthID(containing date: Date) -> String {
        if let intervalMinutes = SharedIdentifiers.t089LedgerTestConfiguration()?.periodMinutes {
            return periodID(containing: date, intervalMinutes: intervalMinutes)
        }
        return monthID(
            containing: date,
            boundaryDay: SharedIdentifiers.t089LedgerTestConfiguration()?.monthlyBoundaryDay ?? 1
        )
    }

    static func periodID(containing date: Date, intervalMinutes: Int) -> String {
        let intervalMinutes = normalizedIntervalMinutes(intervalMinutes)
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let minute = ((components.minute ?? 0) / intervalMinutes) * intervalMinutes
        return String(
            format: "%04d-%02d-%02dT%02d-%02d",
            locale: Locale(identifier: "en_US_POSIX"),
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            minute
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
        if let intervalMinutes = SharedIdentifiers.t089LedgerTestConfiguration()?.periodMinutes {
            return nextPeriodStart(
                afterPeriodID: monthID,
                intervalMinutes: intervalMinutes
            )
        }
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

    static func nextPeriodStart(
        afterPeriodID periodID: String,
        intervalMinutes: Int
    ) -> Date? {
        guard let periodStart = periodStart(
            forPeriodID: periodID,
            intervalMinutes: intervalMinutes
        ) else {
            return nil
        }
        return calendar.date(
            byAdding: .minute,
            value: normalizedIntervalMinutes(intervalMinutes),
            to: periodStart
        )
    }

    static func periodStart(
        forPeriodID periodID: String,
        intervalMinutes: Int
    ) -> Date? {
        let intervalMinutes = normalizedIntervalMinutes(intervalMinutes)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm"
        formatter.isLenient = false
        guard let date = formatter.date(from: periodID),
              calendar.component(.minute, from: date).isMultiple(of: intervalMinutes),
              self.periodID(containing: date, intervalMinutes: intervalMinutes) == periodID
        else {
            return nil
        }
        return date
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

    private static func normalizedIntervalMinutes(_ intervalMinutes: Int) -> Int {
        (1...30).contains(intervalMinutes) && 60.isMultiple(of: intervalMinutes)
            ? intervalMinutes
            : 5
    }
}
