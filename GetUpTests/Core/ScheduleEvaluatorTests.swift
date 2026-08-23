import Foundation
import Testing
@testable import GetUp

@Suite("Schedule evaluator")
struct ScheduleEvaluatorTests {
    @Test("DatePicker rejects 14 minutes and accepts 15 minutes across midnight")
    func datePickerMinimumDurationBoundary() {
        #expect(
            !ScheduleEvaluator.isEndTimeSelectable(
                startTime: TimeOfDay(hour: 23, minute: 55),
                endTime: TimeOfDay(hour: 0, minute: 9)
            )
        )
        #expect(
            ScheduleEvaluator.isEndTimeSelectable(
                startTime: TimeOfDay(hour: 23, minute: 55),
                endTime: TimeOfDay(hour: 0, minute: 10)
            )
        )
    }

    @Test("A same-day interval includes its start and excludes its end")
    func sameDayBoundaries() {
        let calendar = calendar(in: utc)

        #expect(isActive(at: date("2026-08-24T05:59:00Z"), calendar: calendar) == false)
        #expect(isActive(at: date("2026-08-24T06:00:00Z"), calendar: calendar))
        #expect(isActive(at: date("2026-08-24T08:59:00Z"), calendar: calendar))
        #expect(isActive(at: date("2026-08-24T09:00:00Z"), calendar: calendar) == false)
    }

    @Test("A rule is inactive on a weekday that was not selected")
    func unselectedWeekdayIsInactive() {
        let calendar = calendar(in: utc)

        #expect(
            ScheduleEvaluator.isActive(
                weekdays: [.monday],
                startTime: TimeOfDay(hour: 6, minute: 0),
                endTime: TimeOfDay(hour: 9, minute: 0),
                at: date("2026-08-25T07:00:00Z"),
                calendar: calendar,
                timeZone: utc
            ) == false
        )
    }

    @Test("A cross-midnight interval belongs to its starting weekday")
    func crossMidnightUsesStartingWeekday() {
        let calendar = calendar(in: utc)

        #expect(
            ScheduleEvaluator.isActive(
                weekdays: [.monday],
                startTime: TimeOfDay(hour: 23, minute: 0),
                endTime: TimeOfDay(hour: 6, minute: 0),
                at: date("2026-08-25T05:59:00Z"),
                calendar: calendar,
                timeZone: utc
            )
        )
        #expect(
            ScheduleEvaluator.isActive(
                weekdays: [.monday],
                startTime: TimeOfDay(hour: 23, minute: 0),
                endTime: TimeOfDay(hour: 6, minute: 0),
                at: date("2026-08-25T06:00:00Z"),
                calendar: calendar,
                timeZone: utc
            ) == false
        )
    }

    @Test("A nonexistent DST start moves to the next valid local time")
    func springForwardMovesNonexistentStartForward() {
        let newYork = TimeZone(identifier: "America/New_York")!
        let calendar = calendar(in: newYork)

        #expect(
            isActive(
                weekdays: [.sunday],
                start: TimeOfDay(hour: 2, minute: 30),
                end: TimeOfDay(hour: 4, minute: 0),
                at: date("2026-03-08T06:59:00Z"),
                calendar: calendar,
                timeZone: newYork
            ) == false
        )
        #expect(
            isActive(
                weekdays: [.sunday],
                start: TimeOfDay(hour: 2, minute: 30),
                end: TimeOfDay(hour: 4, minute: 0),
                at: date("2026-03-08T07:00:00Z"),
                calendar: calendar,
                timeZone: newYork
            )
        )
    }

    @Test("A nonexistent DST end moves to the next valid local time")
    func springForwardMovesNonexistentEndForward() {
        let newYork = TimeZone(identifier: "America/New_York")!
        let calendar = calendar(in: newYork)

        #expect(
            isActive(
                weekdays: [.sunday],
                start: TimeOfDay(hour: 1, minute: 45),
                end: TimeOfDay(hour: 2, minute: 30),
                at: date("2026-03-08T06:59:00Z"),
                calendar: calendar,
                timeZone: newYork
            )
        )
        #expect(
            isActive(
                weekdays: [.sunday],
                start: TimeOfDay(hour: 1, minute: 45),
                end: TimeOfDay(hour: 2, minute: 30),
                at: date("2026-03-08T07:00:00Z"),
                calendar: calendar,
                timeZone: newYork
            ) == false
        )
    }

    @Test("A repeated DST interval uses the first start and second end")
    func fallBackUsesFirstStartAndSecondEnd() {
        let newYork = TimeZone(identifier: "America/New_York")!
        let calendar = calendar(in: newYork)
        let weekdays: Set<Weekday> = [.sunday]
        let start = TimeOfDay(hour: 1, minute: 30)
        let end = TimeOfDay(hour: 1, minute: 45)

        #expect(
            isActive(
                weekdays: weekdays,
                start: start,
                end: end,
                at: date("2026-11-01T05:29:00Z"),
                calendar: calendar,
                timeZone: newYork
            ) == false
        )
        #expect(
            isActive(
                weekdays: weekdays,
                start: start,
                end: end,
                at: date("2026-11-01T05:30:00Z"),
                calendar: calendar,
                timeZone: newYork
            )
        )
        #expect(
            isActive(
                weekdays: weekdays,
                start: start,
                end: end,
                at: date("2026-11-01T06:30:00Z"),
                calendar: calendar,
                timeZone: newYork
            )
        )
        #expect(
            isActive(
                weekdays: weekdays,
                start: start,
                end: end,
                at: date("2026-11-01T06:45:00Z"),
                calendar: calendar,
                timeZone: newYork
            ) == false
        )
    }

    private var utc: TimeZone {
        TimeZone(secondsFromGMT: 0)!
    }

    private func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func isActive(at date: Date, calendar: Calendar) -> Bool {
        isActive(
            weekdays: [.monday],
            start: TimeOfDay(hour: 6, minute: 0),
            end: TimeOfDay(hour: 9, minute: 0),
            at: date,
            calendar: calendar,
            timeZone: utc
        )
    }

    private func isActive(
        weekdays: Set<Weekday>,
        start: TimeOfDay,
        end: TimeOfDay,
        at date: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> Bool {
        ScheduleEvaluator.isActive(
            weekdays: weekdays,
            startTime: start,
            endTime: end,
            at: date,
            calendar: calendar,
            timeZone: timeZone
        )
    }
}
