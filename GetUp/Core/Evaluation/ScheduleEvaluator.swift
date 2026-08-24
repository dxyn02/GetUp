import Foundation

enum ScheduleEvaluator {
    private static let minimumDurationMinutes = 15

    static func isEndTimeSelectable(
        startTime: TimeOfDay,
        endTime: TimeOfDay
    ) -> Bool {
        guard isValid(startTime), isValid(endTime) else {
            return false
        }

        let duration = durationInMinutes(from: startTime, to: endTime)
        return duration >= minimumDurationMinutes
    }

    static func isActive(
        weekdays: Set<Weekday>,
        startTime: TimeOfDay,
        endTime: TimeOfDay,
        at date: Date,
        calendar inputCalendar: Calendar,
        timeZone: TimeZone
    ) -> Bool {
        guard
            !weekdays.isEmpty,
            isValid(startTime),
            isValid(endTime),
            startTime != endTime
        else {
            return false
        }

        var calendar = inputCalendar
        calendar.timeZone = timeZone

        let currentDay = calendar.startOfDay(for: date)
        let crossesMidnight = minutes(for: endTime) < minutes(for: startTime)

        if interval(
            startingOn: currentDay,
            weekdays: weekdays,
            startTime: startTime,
            endTime: endTime,
            crossesMidnight: crossesMidnight,
            calendar: calendar
        ).contains(date) {
            return true
        }

        guard
            crossesMidnight,
            let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDay)
        else {
            return false
        }

        return interval(
            startingOn: previousDay,
            weekdays: weekdays,
            startTime: startTime,
            endTime: endTime,
            crossesMidnight: true,
            calendar: calendar
        ).contains(date)
    }

    private static func interval(
        startingOn day: Date,
        weekdays: Set<Weekday>,
        startTime: TimeOfDay,
        endTime: TimeOfDay,
        crossesMidnight: Bool,
        calendar: Calendar
    ) -> Range<Date> {
        guard
            let weekday = weekday(for: calendar.component(.weekday, from: day)),
            weekdays.contains(weekday),
            let start = boundary(
                on: day,
                time: startTime,
                repeatedTimePolicy: .first,
                calendar: calendar
            ),
            let endDay = crossesMidnight
                ? calendar.date(byAdding: .day, value: 1, to: day)
                : day,
            let end = boundary(
                on: endDay,
                time: endTime,
                repeatedTimePolicy: .last,
                calendar: calendar
            ),
            start < end
        else {
            return Date.distantPast..<Date.distantPast
        }

        return start..<end
    }

    private static func boundary(
        on day: Date,
        time: TimeOfDay,
        repeatedTimePolicy: Calendar.RepeatedTimePolicy,
        calendar: Calendar
    ) -> Date? {
        let searchStart = day.addingTimeInterval(-1)
        return calendar.nextDate(
            after: searchStart,
            matching: DateComponents(hour: time.hour, minute: time.minute),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: repeatedTimePolicy,
            direction: .forward
        )
    }

    private static func durationInMinutes(
        from startTime: TimeOfDay,
        to endTime: TimeOfDay
    ) -> Int {
        let start = minutes(for: startTime)
        let end = minutes(for: endTime)
        return (end - start + 24 * 60) % (24 * 60)
    }

    private static func minutes(for time: TimeOfDay) -> Int {
        time.hour * 60 + time.minute
    }

    private static func isValid(_ time: TimeOfDay) -> Bool {
        (0...23).contains(time.hour) && (0...59).contains(time.minute)
    }

    private static func weekday(for calendarWeekday: Int) -> Weekday? {
        switch calendarWeekday {
        case 1: .sunday
        case 2: .monday
        case 3: .tuesday
        case 4: .wednesday
        case 5: .thursday
        case 6: .friday
        case 7: .saturday
        default: nil
        }
    }
}
